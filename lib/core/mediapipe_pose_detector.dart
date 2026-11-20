import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:mediapipe_vision/mediapipe_vision.dart';

import '../data/pose_models.dart';

/// Variantes MediaPipe PoseLandmarker disponibles pour comparaison A/B.
enum PoseModelVariant {
  lite('lite'),
  full('full');

  const PoseModelVariant(this.label);

  final String label;

  static const String fullAssetPath = 'assets/models/pose_landmarker_full.task';

  static const String _envModel =
      String.fromEnvironment('POSE_MODEL', defaultValue: 'lite');

  static PoseModelVariant get defaultFromEnvironment => fromName(_envModel);

  static PoseModelVariant fromName(String? value) {
    if (value?.trim().toLowerCase() == 'full') {
      return PoseModelVariant.full;
    }
    return PoseModelVariant.lite;
  }

  PoseModelVariant get opposite =>
      this == PoseModelVariant.lite ? PoseModelVariant.full : PoseModelVariant.lite;
}

/// Adaptateur officiel `mediapipe_vision` ([PoseLandmarker]) pour le pipeline
/// temps réel VideoLog, avec bascule à chaud `lite` / `full` (`RunningMode.video`).
class MediaPipeVisionPoseDetector {
  MediaPipeVisionPoseDetector({
    PoseModelVariant? initialModel,
    this.numPoses = 1,
    this.minPoseDetectionConfidence = 0.85,
    this.minPosePresenceConfidence = 0.85,
    this.minTrackingConfidence = 0.80,
    this.preferGpu = true,
    this.decodeTargetWidth = 320,
  }) : _modelVariant = initialModel ?? PoseModelVariant.defaultFromEnvironment;

  final int numPoses;
  final double minPoseDetectionConfidence;
  final double minPosePresenceConfidence;
  final double minTrackingConfidence;
  final bool preferGpu;

  /// Largeur cible lors du décodage JPEG/PNG → RGBA afin de limiter le coût
  /// mémoire/FFI sur des caméras 720p/1080p. `null` conserve la résolution source.
  final int? decodeTargetWidth;

  PoseModelVariant _modelVariant;
  PoseLandmarker? _landmarker;
  Uint8List? _fullModelBytesCache;
  Delegate _activeDelegate = Delegate.cpu;
  int _lastTimestampMs = -1;
  bool _disposed = false;

  bool get isInitialized => _landmarker != null && !_disposed;
  Delegate get activeDelegate => _activeDelegate;
  String get delegateName => _activeDelegate.name;
  PoseModelVariant get modelVariant => _modelVariant;
  String get modelLabel => _modelVariant.label;

  /// Garantit un horodatage strictement croissant en millisecondes, requis par
  /// `PoseLandmarker.detectForVideo`.
  int nextMonotonicTimestampMs(int rawTimestampMs) {
    final candidate = rawTimestampMs < 0 ? 0 : rawTimestampMs;
    final next = candidate > _lastTimestampMs ? candidate : _lastTimestampMs + 1;
    _lastTimestampMs = next;
    return next;
  }

  /// Initialise [PoseLandmarker] en interrogeant d'abord les capacités de la
  /// plateforme (évite un crash `RuntimeUnavailableException` si le GPU n'est
  /// pas supporté, ex. Android LiteRT 1.2.3).
  Future<Delegate> initialize() async {
    if (_disposed) {
      throw StateError('MediaPipeVisionPoseDetector is already disposed');
    }
    if (_landmarker != null) return _activeDelegate;

    final capabilities = await queryPoseLandmarkerCapabilities();
    final canUseGpu =
        preferGpu && capabilities.supportedDelegates.contains(Delegate.gpu);

    if (preferGpu && !canUseGpu) {
      final reason = capabilities.unavailableReasons[Delegate.gpu];
      debugPrint(
        'ℹ️ [MediaPipeVision] GPU indisponible pour PoseLandmarker, '
        'repli CPU${reason != null ? ' ($reason)' : ''}',
      );
    }

    if (canUseGpu) {
      try {
        _landmarker = await _createLandmarker(Delegate.gpu, _modelVariant);
        _activeDelegate = _landmarker!.delegate;
        return _activeDelegate;
      } catch (error) {
        debugPrint(
          '⚠️ [MediaPipeVision] Échec init GPU ($error), repli CPU...',
        );
      }
    }

    _landmarker = await _createLandmarker(Delegate.cpu, _modelVariant);
    _activeDelegate = _landmarker!.delegate;
    return _activeDelegate;
  }

  /// Change la variante de modèle (`lite` ↔ `full`) à chaud en libérant
  /// proprement l'instance précédente de [PoseLandmarker].
  Future<Delegate> switchModel(PoseModelVariant variant) async {
    if (_disposed) {
      throw StateError('MediaPipeVisionPoseDetector is already disposed');
    }
    if (_modelVariant == variant && _landmarker != null) {
      return _activeDelegate;
    }

    final previous = _landmarker;
    _landmarker = null;
    _modelVariant = variant;
    _lastTimestampMs = -1;

    if (previous != null) {
      await previous.dispose();
    }

    return initialize();
  }

  Future<Uint8List> _loadFullModelBytes() async {
    final cached = _fullModelBytesCache;
    if (cached != null) return cached;
    final data = await rootBundle.load(PoseModelVariant.fullAssetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    _fullModelBytesCache = bytes;
    return bytes;
  }

  Future<PoseLandmarker> _createLandmarker(
    Delegate delegate,
    PoseModelVariant variant,
  ) async {
    if (variant == PoseModelVariant.full) {
      final bytes = await _loadFullModelBytes();
      return PoseLandmarker.create(
        PoseLandmarkerOptions(
          modelBytes: bytes,
          runningMode: RunningMode.video,
          delegate: delegate,
          numPoses: numPoses,
          minPoseDetectionConfidence: minPoseDetectionConfidence,
          minPosePresenceConfidence: minPosePresenceConfidence,
          minTrackingConfidence: minTrackingConfidence,
          outputSegmentationMasks: false,
        ),
      );
    }

    return PoseLandmarker.create(
      PoseLandmarkerOptions(
        model: VisionModels.poseLandmarker,
        runningMode: RunningMode.video,
        delegate: delegate,
        numPoses: numPoses,
        minPoseDetectionConfidence: minPoseDetectionConfidence,
        minPosePresenceConfidence: minPosePresenceConfidence,
        minTrackingConfidence: minTrackingConfidence,
        outputSegmentationMasks: false,
      ),
    );
  }

  /// Décode une image encodée (JPEG/PNG issu de `captureFrame()`) en RGBA puis
  /// exécute `PoseLandmarker.detectForVideo`.
  Future<PoseDetectionResult> detectPoseVideo(
    Uint8List encodedBytes,
    int videoTimestampMs,
  ) async {
    final landmarker = _landmarker;
    if (landmarker == null || _disposed) {
      throw StateError('MediaPipeVisionPoseDetector is not initialized');
    }

    final decodeWatch = Stopwatch()..start();
    final decoded = await _decodeToRgba(encodedBytes);
    decodeWatch.stop();
    final decodeTimeMs = decodeWatch.elapsedMilliseconds;

    if (decoded == null) {
      return PoseDetectionResult(
        poses: const [],
        processingTimeMs: 0,
        decodeTimeMs: decodeTimeMs,
        imageWidth: 0,
        imageHeight: 0,
        delegateName: delegateName,
      );
    }

    final image = VisionImage.fromPixels(
      pixels: decoded.rgba,
      width: decoded.width,
      height: decoded.height,
      format: VisionPixelFormat.rgba,
    );

    final timestampMs = nextMonotonicTimestampMs(videoTimestampMs);
    final inferWatch = Stopwatch()..start();
    final mpResult = await landmarker.detectForVideo(
      image,
      timestampMilliseconds: timestampMs,
    );
    inferWatch.stop();

    return mapResult(
      mpResult,
      processingTimeMs: inferWatch.elapsedMilliseconds,
      decodeTimeMs: decodeTimeMs,
      delegateName: delegateName,
    );
  }

  Future<({Uint8List rgba, int width, int height})?> _decodeToRgba(
    Uint8List encodedBytes,
  ) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(
        encodedBytes,
        targetWidth: decodeTargetWidth,
      );
      final frameInfo = await codec.getNextFrame();
      image = frameInfo.image;
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return null;
      return (
        rgba: byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
        width: image.width,
        height: image.height,
      );
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  /// Convertit un [PoseLandmarkerResult] de `mediapipe_vision` vers les modèles
  /// internes VideoLog ([PoseDetectionResult]).
  static PoseDetectionResult mapResult(
    PoseLandmarkerResult result, {
    required int processingTimeMs,
    int decodeTimeMs = 0,
    String delegateName = 'cpu',
  }) {
    final poses = <Pose>[];

    for (var p = 0; p < result.poseLandmarks.length; p++) {
      final rawLandmarks = result.poseLandmarks[p];
      final rawWorld = p < result.poseWorldLandmarks.length
          ? result.poseWorldLandmarks[p]
          : const <Landmark>[];

      final landmarks = List<PoseLandmark>.generate(
        LandmarkType.count,
        (index) {
          final type = LandmarkType.fromIndex(index);
          if (index >= rawLandmarks.length) {
            return PoseLandmark.notDetected(type);
          }
          final lm = rawLandmarks[index];
          return PoseLandmark(
            type: type,
            x: lm.x,
            y: lm.y,
            z: lm.z,
            visibility: (lm.visibility ?? 0.0).clamp(0.0, 1.0),
          );
        },
        growable: false,
      );

      final worldLandmarks = List<WorldLandmark>.generate(
        rawWorld.length,
        (index) {
          final w = rawWorld[index];
          return WorldLandmark(
            typeIndex: index,
            x: w.x,
            y: w.y,
            z: w.z,
            visibility: (w.visibility ?? 0.0).clamp(0.0, 1.0),
          );
        },
        growable: false,
      );

      var visSum = 0.0;
      var visCount = 0;
      for (final lm in landmarks) {
        if (lm.isDetected) {
          visSum += lm.visibility;
          visCount++;
        }
      }
      final score = visCount > 0 ? visSum / visCount : 0.0;

      poses.add(
        Pose(
          landmarks: landmarks,
          worldLandmarks: worldLandmarks,
          score: score,
        ),
      );
    }

    return PoseDetectionResult(
      poses: poses,
      processingTimeMs: processingTimeMs,
      decodeTimeMs: decodeTimeMs,
      imageWidth: result.imageWidth,
      imageHeight: result.imageHeight,
      delegateName: delegateName,
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final landmarker = _landmarker;
    _landmarker = null;
    if (landmarker != null) {
      await landmarker.dispose();
    }
  }
}
