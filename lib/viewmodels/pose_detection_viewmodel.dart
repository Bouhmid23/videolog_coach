import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart'
    show
        ChangeNotifier,
        ValueListenable,
        ValueNotifier,
        TargetPlatform,
        defaultTargetPlatform,
        kDebugMode,
        kIsWeb,
        debugPrint;
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../core/gravity_service.dart';
import '../core/mediapipe_pose_detector.dart';
import '../core/posture_detection_service.dart';
import '../core/thermal_service.dart';
import '../data/pose_models.dart';
import '../data/remote_posture.dart';
import 'pose/motion_detector.dart';
import 'pose/pose_frame.dart';
import 'pose/pose_publisher.dart';
import 'pose/posture_classifier.dart';

export '../core/mediapipe_pose_detector.dart' show PoseModelVariant;
export 'pose/pose_frame.dart';

/// Orchestrateur de détection posturale (branche POC `mediapipe_vision`) :
/// - Capture les frames de la piste caméra LiveKit (prefetch N+1 pendant N).
/// - Exécute l'inférence via le package officiel `mediapipe_vision` (switch `lite` / `full`).
/// - Anime l'overlay local via [frameNotifier].
/// - Classifie et stabilise la posture en temps réel.
/// - Émet le flux binaire compact v7 via [PosePublisher].
class PoseDetectionViewModel extends ChangeNotifier {
  PoseDetectionViewModel({
    MediaPipeVisionPoseDetector? poseDetector,
    ThermalService? thermalService,
  })  : _poseDetector = poseDetector ?? MediaPipeVisionPoseDetector(),
        _thermalService = thermalService ?? ThermalService.instance,
        _modelVariantNotifier = ValueNotifier<PoseModelVariant>(
          (poseDetector ?? MediaPipeVisionPoseDetector()).modelVariant,
        ) {
    _thermalService.thermalInfo.addListener(_onThermalChanged);
    _applyThermalState(_thermalService.thermalInfo.value, notify: false);
  }

  final PostureSmoothing _smoothing = PostureSmoothing(alpha: 0.5);
  final MediaPipeVisionPoseDetector _poseDetector;
  final ThermalService _thermalService;
  final ValueNotifier<PoseModelVariant> _modelVariantNotifier;

  static const Size _fallbackSize = Size(720, 1280);

  // Sub-modules
  final MotionDetector _motionDetector = MotionDetector();
  final PostureClassifier _classifier = const PostureClassifier();
  final PostureStabilizer _stabilizer = PostureStabilizer();
  final PosePublisher _publisher = PosePublisher();

  bool _running = false;
  bool _paused = false;
  bool _cameraSwitching = false;
  bool _modelSwitching = false;
  Future<void>? _inFlightDetection;
  Room? _room;

  bool _hadPose = false;
  DateTime _lastLostSent = DateTime.fromMillisecondsSinceEpoch(0);

  // Statistiques et mesures de benchmark
  int _captureMicros = 0;
  int _captureSamples = 0;
  int _decodeMicros = 0;
  int _decodeSamples = 0;
  int _detectMicros = 0;
  int _detectSamples = 0;
  int _inferMicros = 0;
  int _inferSamples = 0;
  DateTime _statsWindowStart = DateTime.now();
  DateTime _lastRuntimeLandmarkLog = DateTime.fromMillisecondsSinceEpoch(0);
  Size? _lastFrameSize;
  String _deviceModel = 'unknown';

  final Stopwatch _videoClock = Stopwatch()..start();

  RemotePosture? _currentPosture;

  // FPS adaptatif mouvement (15 FPS statique / 30 FPS actif) + throttling thermique
  bool _lastIsStatic = false;
  bool _thermalThrottled = false;
  int _currentTargetFps = 30;
  double _measuredFps = 0.0;

  // ── Getters publics ──
  bool get isThermalThrottled => _thermalThrottled;
  int get currentTargetFps => _currentTargetFps;
  double get nativeFps => _measuredFps;
  String get delegateName => _poseDetector.delegateName;
  PoseModelVariant get modelVariant => _poseDetector.modelVariant;
  ValueListenable<PoseModelVariant> get modelVariantListenable =>
      _modelVariantNotifier;
  String get modelLabel => _poseDetector.modelLabel;
  bool get isSwitchingModel => _modelSwitching;
  RemotePosture? get currentPosture => _currentPosture;
  bool get isBusy => _running;

  /// Dernière pose pour l'overlay local.
  final ValueNotifier<PoseFrame?> frameNotifier = ValueNotifier<PoseFrame?>(null);

  int _computeTargetFps() {
    if (_thermalThrottled) {
      final status = _thermalService.thermalInfo.value.status;
      // Surchauffe sévère/critique (>= 3) : 10 FPS, sinon 15 FPS max.
      return status >= 3 ? 10 : 15;
    }
    return _lastIsStatic ? 15 : 30;
  }

  void _onThermalChanged() {
    _applyThermalState(_thermalService.thermalInfo.value, notify: true);
  }

  void _applyThermalState(ThermalInfo info, {required bool notify}) {
    final wasThrottled = _thermalThrottled;
    _thermalThrottled = info.isOverheating;
    final previousFps = _currentTargetFps;
    _currentTargetFps = _computeTargetFps();

    if (_thermalThrottled && !wasThrottled) {
      debugPrint(
        '🔥 Pose thermal throttling activated '
        '(status=${info.statusName}, targetFps=$_currentTargetFps)',
      );
      if (_poseDetector.modelVariant == PoseModelVariant.full) {
        debugPrint('🔥 Downgrading pose model from full to lite due to overheating');
        unawaited(setModelVariant(PoseModelVariant.lite));
      }
    } else if (!_thermalThrottled && wasThrottled) {
      debugPrint(
        '❄️ Pose thermal throttling cleared (targetFps=$_currentTargetFps)',
      );
    }

    if (notify &&
        (wasThrottled != _thermalThrottled ||
            previousFps != _currentTargetFps)) {
      notifyListeners();
    }
  }

  Future<void> init() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final device = await DeviceInfoPlugin().androidInfo;
        _deviceModel = '${device.manufacturer} ${device.model}'.trim();
      } catch (error) {
        debugPrint('[Pose] Could not read Android model: $error');
      }
    }
    _smoothing.alpha = 0.5;
    final delegate = await _poseDetector.initialize();
    _modelVariantNotifier.value = _poseDetector.modelVariant;
    debugPrint(
      '🧠 Pose detector ready (mediapipe_vision): delegate=${delegate.name} '
      'numPoses=${_poseDetector.numPoses} '
      'detection=${_poseDetector.minPoseDetectionConfidence} '
      'presence=${_poseDetector.minPosePresenceConfidence} '
      'tracking=${_poseDetector.minTrackingConfidence} '
      'runningMode=VIDEO model=${_poseDetector.modelLabel} '
      'decodeTargetWidth=${_poseDetector.decodeTargetWidth} '
      'device=$_deviceModel smoothingAlpha=${_smoothing.alpha.toStringAsFixed(2)}',
    );
  }

  /// Bascule à chaud entre `PoseModelVariant.lite` et `PoseModelVariant.full`.
  Future<void> toggleModelVariant() =>
      setModelVariant(_poseDetector.modelVariant.opposite);

  /// Charge la variante demandée en attendant la fin de l'inférence en cours
  /// puis réinitialise les compteurs de benchmark `📊 pose`.
  Future<void> setModelVariant(PoseModelVariant variant) async {
    if (_modelSwitching) return;
    if (_poseDetector.modelVariant == variant && _poseDetector.isInitialized) {
      return;
    }

    _modelSwitching = true;
    notifyListeners();
    try {
      final inFlight = _inFlightDetection;
      if (inFlight != null) {
        try {
          await inFlight;
        } catch (_) {}
      }

      final delegate = await _poseDetector.switchModel(variant);
      _modelVariantNotifier.value = _poseDetector.modelVariant;
      _motionDetector.reset();
      _smoothing.reset();
      _stabilizer.reset();
      _resetBenchmarkCounters();
      debugPrint(
        '🔄 Pose model switched (mediapipe_vision): '
        'model=${_poseDetector.modelLabel} delegate=${delegate.name}',
      );
    } catch (error) {
      debugPrint('⚠️ Pose model switch to ${variant.label} failed: $error');
    } finally {
      _modelSwitching = false;
      notifyListeners();
    }
  }

  void _resetBenchmarkCounters() {
    _captureMicros = 0;
    _captureSamples = 0;
    _decodeMicros = 0;
    _decodeSamples = 0;
    _detectMicros = 0;
    _detectSamples = 0;
    _inferMicros = 0;
    _inferSamples = 0;
    _measuredFps = 0.0;
    _publisher.resetStats(_publisher.seq);
    _statsWindowStart = DateTime.now();
  }

  void start(Room room, {List<String>? destinationIdentities}) {
    _room = room;
    setDestinationIdentities(destinationIdentities);
    if (_running) return;
    _running = true;
    GravityService.instance.start();
    _statsWindowStart = DateTime.now();
    _publisher.resetStats(_publisher.seq);
    unawaited(_poseLoop());
    debugPrint(
      '🏃 Pose detection started (mediapipe_vision model=${_poseDetector.modelLabel})',
    );
  }

  void setDestinationIdentities(List<String>? identities) {
    _publisher.setDestinationIdentities(identities);
  }

  void stop() {
    if (_running && _hadPose) {
      _publisher.publishLost(
        room: _room,
        capturedAt: DateTime.now(),
        deviceModel: _deviceModel,
      );
    }
    _running = false;
    _cameraSwitching = false;
    GravityService.instance.stop();
    _hadPose = false;
    _lastIsStatic = false;
    _currentTargetFps = _computeTargetFps();
    _measuredFps = 0.0;
    _motionDetector.reset();
    _stabilizer.reset();
    _currentPosture = null;
    _smoothing.reset();
    frameNotifier.value = null;
  }

  void pause() {
    if (!_running || _paused) return;
    _paused = true;
    if (_hadPose) {
      _publisher.publishLost(
        room: _room,
        capturedAt: DateTime.now(),
        deviceModel: _deviceModel,
      );
    }
    _hadPose = false;
    frameNotifier.value = null;
    debugPrint('⏸️ Pose detection paused (background)');
  }

  void resume() {
    if (!_running || !_paused) return;
    _paused = false;
    _statsWindowStart = DateTime.now();
    _publisher.resetStats(_publisher.seq);
    unawaited(_poseLoop());
    debugPrint('▶️ Pose detection resumed (foreground)');
  }

  /// Appelé juste avant un basculement matériel de caméra (front <-> back).
  Future<void> beginCameraSwitch() async {
    if (!_running) return;
    _cameraSwitching = true;
    _motionDetector.reset();
    _smoothing.reset();
    _stabilizer.reset();
    frameNotifier.value = null;
  }

  /// Appelé une fois la bascule matérielle de caméra terminée.
  void endCameraSwitch() {
    _cameraSwitching = false;
  }

  Future<void> _poseLoop() async {
    if (kIsWeb) return;

    Future<CapturedFrame?>? next;

    while (_running) {
      if (_paused || _cameraSwitching || _modelSwitching) {
        next = null;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }

      if (!_poseDetector.isInitialized) {
        try {
          await _poseDetector.initialize();
        } catch (error) {
          debugPrint('⚠️ MediaPipeVision init failed in loop: $error');
          await Future<void>.delayed(const Duration(milliseconds: 500));
          continue;
        }
      }

      final loopWatch = Stopwatch()..start();
      final track = _cameraTrack();
      if (track == null) {
        next = null;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }

      final frame = await (next ?? _capture(track));
      if (!_running || _paused || _cameraSwitching || _modelSwitching) {
        next = null;
        continue;
      }

      next = (_running && !_paused && !_cameraSwitching && !_modelSwitching)
          ? _capture(track)
          : null;

      if (frame == null) {
        _onLost(DateTime.now());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        continue;
      }

      final detectWatch = Stopwatch()..start();
      final completer = Completer<void>();
      _inFlightDetection = completer.future;
      try {
        final result = await _poseDetector.detectPoseVideo(
          frame.bytes,
          frame.videoTimestampMs,
        );
        if (!_running || _paused || _modelSwitching) continue;
        detectWatch.stop();

        final detectMicros = detectWatch.elapsedMicroseconds;
        _detectMicros += detectMicros;
        _detectSamples++;
        _decodeMicros += result.decodeTimeMs * 1000;
        _decodeSamples++;
        _inferMicros += result.processingTimeMs * 1000;
        _inferSamples++;

        if (!result.hasPoses) {
          _motionDetector.reset();
          _onLost(frame.capturedAt);
        } else {
          final rawPose = result.firstPose!;
          final isStatic = _motionDetector.update(rawPose);
          if (isStatic != _lastIsStatic) {
            _lastIsStatic = isStatic;
            _currentTargetFps = _computeTargetFps();
          }

          final size = result.imageWidth > 0 && result.imageHeight > 0
              ? Size(
                  result.imageWidth.toDouble(),
                  result.imageHeight.toDouble(),
                )
              : _fallbackSize;
          _lastFrameSize = size;
          final pose = _smoothing.smooth(rawPose);
          _logRuntimeLandmarks(pose);
          frameNotifier.value = PoseFrame(
            pose: pose,
            frameSize: size,
            capturedAt: frame.capturedAt,
          );
          final rawPosture = _classifier.classify(rawPose, frameSize: size);
          final posture = _stabilizePosture(rawPosture);
          _hadPose = true;

          _publisher.publish(
            room: _room,
            pose: pose,
            posture: posture,
            frameSize: size,
            capturedAt: frame.capturedAt,
            deviceModel: _deviceModel,
            modelLabel: _poseDetector.modelLabel,
            captureMicros: frame.captureMicros,
            detectMicros: detectMicros,
            inferMicros: result.processingTimeMs * 1000,
          );
        }
      } catch (error) {
        if (detectWatch.isRunning) {
          detectWatch.stop();
          _detectMicros += detectWatch.elapsedMicroseconds;
          _detectSamples++;
        }
        debugPrint('⚠️ Pose detection error (mediapipe_vision): $error');
      } finally {
        if (!completer.isCompleted) completer.complete();
        if (identical(_inFlightDetection, completer.future)) {
          _inFlightDetection = null;
        }
      }

      _logStats();

      loopWatch.stop();
      final elapsedMicros = loopWatch.elapsedMicroseconds;
      final targetIntervalMicros = (1000000 / _currentTargetFps).round();
      if (elapsedMicros < targetIntervalMicros) {
        final remainingMicros = targetIntervalMicros - elapsedMicros;
        await Future<void>.delayed(Duration(microseconds: remainingMicros));
      } else {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  RemotePosture? _stabilizePosture(RemotePosture? raw) {
    final stabilized = _stabilizer.stabilize(raw);
    if (stabilized == null) {
      if (_currentPosture != null) {
        _currentPosture = null;
        notifyListeners();
      }
      return null;
    }
    if (_currentPosture?.label != stabilized.label) {
      _currentPosture = stabilized;
      notifyListeners();
    } else {
      _currentPosture = stabilized;
    }
    return stabilized;
  }

  void _onLost(DateTime capturedAt) {
    final now = DateTime.now();
    if (_hadPose ||
        now.difference(_lastLostSent) > const Duration(milliseconds: 500)) {
      _hadPose = false;
      _lastLostSent = now;
      _publisher.publishLost(
        room: _room,
        capturedAt: capturedAt,
        deviceModel: _deviceModel,
      );
    }
    _stabilizer.onPoseLost();
    if (_smoothing.alpha < 1.0) _smoothing.reset();
    frameNotifier.value = null;
    if (_currentPosture != null) {
      _currentPosture = null;
      notifyListeners();
    }
  }

  LocalVideoTrack? _cameraTrack() {
    final participant = _room?.localParticipant;
    if (participant == null) return null;
    for (final publication in participant.videoTrackPublications) {
      final track = publication.track;
      if (track != null && track.source == TrackSource.camera) return track;
    }
    return null;
  }

  Future<CapturedFrame?> _capture(LocalVideoTrack track) async {
    final watch = Stopwatch()..start();
    final capturedAt = DateTime.now();
    final videoTimestampMs = _videoClock.elapsedMilliseconds;
    try {
      final buffer = await track.mediaStreamTrack
          .captureFrame()
          .timeout(const Duration(milliseconds: 800));
      final captureMicros = watch.elapsedMicroseconds;
      return CapturedFrame(
        Uint8List.view(buffer),
        capturedAt,
        videoTimestampMs,
        captureMicros,
      );
    } catch (error) {
      debugPrint('⚠️ Pose capture failed: $error');
      return null;
    } finally {
      watch.stop();
      _captureMicros += watch.elapsedMicroseconds;
      _captureSamples++;
    }
  }

  void _logRuntimeLandmarks(Pose pose) {
    if (!kDebugMode) return;
    final now = DateTime.now();
    if (now.difference(_lastRuntimeLandmarkLog) < const Duration(seconds: 2)) {
      return;
    }
    _lastRuntimeLandmarkLog = now;
    final imageZ = pose.landmarks
        .where((point) => point.visibility >= 0.5)
        .map((point) => point.z)
        .toList();
    final world = pose.worldLandmarks
        .where((point) => point.visibility >= 0.5)
        .toList();
    double minOf(List<double> values) =>
        values.isEmpty ? 0 : values.reduce(math.min);
    double maxOf(List<double> values) =>
        values.isEmpty ? 0 : values.reduce(math.max);
    debugPrint(
      '📐 pose-runtime imageZ=${minOf(imageZ).toStringAsFixed(3)}..'
      '${maxOf(imageZ).toStringAsFixed(3)} worldCount=${world.length}/33 '
      'worldZ=${minOf(world.map((point) => point.z).toList()).toStringAsFixed(3)}..'
      '${maxOf(world.map((point) => point.z).toList()).toStringAsFixed(3)}m',
    );
  }

  void _logStats() {
    if (!kDebugMode) return;
    final now = DateTime.now();
    final elapsed = now.difference(_statsWindowStart);
    if (elapsed < const Duration(seconds: 1)) return;

    final seconds = elapsed.inMicroseconds / 1000000.0;
    double averageMs(int micros, int samples) =>
        samples == 0 ? 0 : micros / samples / 1000.0;
    final size = _lastFrameSize;
    final resolution = size == null
        ? 'unknown'
        : '${size.width.toInt()}x${size.height.toInt()}';
    _measuredFps = _detectSamples / seconds;

    debugPrint(
      '📊 pose ${seconds.toStringAsFixed(2)}s '
      'pipeline=mediapipe-vision '
      'delegate=${_poseDetector.delegateName} '
      'model=${_poseDetector.modelLabel} '
      'resolution=$resolution '
      'device=$_deviceModel '
      'fps=${_measuredFps.toStringAsFixed(1)} '
      'targetFps=$_currentTargetFps '
      'capture=${averageMs(_captureMicros, _captureSamples).toStringAsFixed(1)}ms '
      'decode=${averageMs(_decodeMicros, _decodeSamples).toStringAsFixed(1)}ms '
      'infer=${averageMs(_inferMicros, _inferSamples).toStringAsFixed(1)}ms '
      'detect=${averageMs(_detectMicros, _detectSamples).toStringAsFixed(1)}ms '
      'publish=${averageMs(_publisher.publishMicros, _publisher.publishSamples).toStringAsFixed(1)}ms '
      'publishData=${(_publisher.publishedSinceStats / seconds).toStringAsFixed(1)}/s '
      'seq=${((_publisher.seq - _publisher.seqAtLastStats) / seconds).toStringAsFixed(1)}/s',
    );

    _captureMicros = 0;
    _captureSamples = 0;
    _decodeMicros = 0;
    _decodeSamples = 0;
    _detectMicros = 0;
    _detectSamples = 0;
    _inferMicros = 0;
    _inferSamples = 0;
    _publisher.resetStats(_publisher.seq);
    _statsWindowStart = now;
  }

  /// Méthode publique de classification pour compatibilité ascendante.
  RemotePosture? classifyPosture(Pose pose, {required Size frameSize}) =>
      _classifier.classify(pose, frameSize: frameSize);

  @override
  void dispose() {
    _thermalService.thermalInfo.removeListener(_onThermalChanged);
    stop();
    frameNotifier.dispose();
    _modelVariantNotifier.dispose();
    unawaited(_poseDetector.dispose());
    super.dispose();
  }
}
