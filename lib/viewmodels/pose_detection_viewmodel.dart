import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show
        ChangeNotifier,
        ValueNotifier,
        TargetPlatform,
        defaultTargetPlatform,
        kDebugMode,
        kIsWeb,
        debugPrint;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:livekit_client/livekit_client.dart';

import '../core/gravity_service.dart';
import '../core/posture_detection_service.dart';
import '../data/remote_posture.dart';
import 'pose/motion_detector.dart';
import 'pose/pose_frame.dart';
import 'pose/pose_publisher.dart';
import 'pose/posture_classifier.dart';

export 'pose/pose_frame.dart';

/// Orchestrateur de détection posturale :
/// - Supervise le pipeline matériel Zéro-Copie WebRTC et son repli Capture.
/// - Anime l'overlay local via [frameNotifier].
/// - Classifie et stabilise la posture en temps réel.
/// - Émet le flux binaire compact v7 via [PosePublisher].
class PoseDetectionViewModel extends ChangeNotifier {
  final PostureSmoothing _smoothing = PostureSmoothing(alpha: 0.5);

  final NpuPoseDetector _poseDetector = NpuPoseDetector(
    config: PoseDetectorConfig.realtime().copyWith(
      maxPoses: 1,
      minConfidence: 0.75,
      minPoseDetectionConfidence: 0.75,
      minPosePresenceConfidence: 0.75,
      minTrackingConfidence: 0.7,
      enableZEstimation: true,
      preferredAcceleration: AccelerationMode.gpu,
    ),
  );

  static const Size _fallbackSize = Size(480, 640);

  // Sub-modules
  final MotionDetector _motionDetector = MotionDetector();
  final PostureClassifier _classifier = const PostureClassifier();
  final PostureStabilizer _stabilizer = PostureStabilizer();
  final PosePublisher _publisher = PosePublisher();

  bool _running = false;
  bool _paused = false;
  Room? _room;

  bool _hadPose = false;
  DateTime _lastLostSent = DateTime.fromMillisecondsSinceEpoch(0);

  // Statistiques et mesures
  int _captureMicros = 0;
  int _captureSamples = 0;
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

  // Pipeline natif zéro-copie et FPS adaptatif
  StreamSubscription<FrameResult>? _webRtcSubscription;
  bool _isNativePipelineActive = false;
  bool _lastIsStatic = false;
  bool _lastThermalThrottled = false;
  bool _lastLowBattery = false;
  int _currentTargetFps = 30;
  double _nativeFps = 0.0;
  DateTime? _lastNativeFrameReceivedAt;
  DateTime? _lastNativeAttemptAt;
  String? _lastFailedTrackId;

  // ── Getters publics ──
  bool get isNativePipelineActive => _isNativePipelineActive;
  bool get isThermalThrottled => _lastThermalThrottled;
  bool get isLowBattery => _lastLowBattery;
  int get currentTargetFps => _currentTargetFps;
  double get nativeFps => _nativeFps;
  RemotePosture? get currentPosture => _currentPosture;
  bool get isBusy => _running;
  double get smoothingAlpha => _smoothing.alpha;

  /// Dernière pose pour l'overlay local.
  final ValueNotifier<PoseFrame?> frameNotifier = ValueNotifier<PoseFrame?>(null);

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
    final acceleration = await _poseDetector.initialize();
    final config = _poseDetector.config;
    debugPrint(
      '🧠 Pose detector ready: acceleration=${acceleration.name} '
      'mode=${config.mode.name} maxPoses=${config.maxPoses} '
      'minConfidence=${config.minConfidence} '
      'detection=${config.effectivePoseDetectionConfidence} '
      'presence=${config.effectivePosePresenceConfidence} '
      'tracking=${config.effectiveTrackingConfidence} '
      'zEstimation=${config.enableZEstimation} runningMode=VIDEO '
      'model=lite device=$_deviceModel smoothingAlpha=${_smoothing.alpha.toStringAsFixed(2)}',
    );
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
    debugPrint('🏃 Pose detection started (temps réel)');
  }

  void setDestinationIdentities(List<String>? identities) {
    _publisher.setDestinationIdentities(identities);
  }

  void stop() {
    _stopNativePipeline();
    if (_running && _hadPose) {
      _publisher.publishLost(
        room: _room,
        capturedAt: DateTime.now(),
        deviceModel: _deviceModel,
      );
    }
    _running = false;
    GravityService.instance.stop();
    _hadPose = false;
    _stabilizer.reset();
    _currentPosture = null;
    _smoothing.reset();
    frameNotifier.value = null;
  }

  void pause() {
    if (!_running || _paused) return;
    _paused = true;
    _stopNativePipeline();
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

  void _stopNativePipeline() {
    _webRtcSubscription?.cancel();
    _webRtcSubscription = null;
    _lastNativeFrameReceivedAt = null;
    _isNativePipelineActive = false;
    _motionDetector.reset();
    _poseDetector.stopWebRtcDetection().catchError((_) {});
  }

  // ---------------------------------------------------------------------------
  // Superviseur : Zéro-Copie Natif & Repli Intelligent
  // ---------------------------------------------------------------------------

  void _tryStartNativePipeline() {
    final track = _cameraTrack();
    if (track == null) return;
    final trackId = track.mediaStreamTrack.id;
    if (trackId == null || trackId.isEmpty) return;

    if (_lastFailedTrackId == trackId &&
        _lastNativeAttemptAt != null &&
        DateTime.now().difference(_lastNativeAttemptAt!) <
            const Duration(seconds: 30)) {
      return;
    }

    try {
      debugPrint('🚀 [Native Pipeline] Tentative Zéro-Copie WebRTC sur track: $trackId');
      _webRtcSubscription?.cancel();
      _webRtcSubscription = _poseDetector
          .startWebRtcDetection(
            trackId: trackId,
            nominalFps: 30,
            throttledFps: 15,
            enableAdaptiveThrottling: true,
          )
          .listen(
            _handleNativeFrameResult,
            onError: (error) {
              debugPrint('⚠️ [Native Pipeline] Erreur stream natif: $error');
              _lastFailedTrackId = trackId;
              _stopNativePipeline();
            },
            onDone: () {
              debugPrint('⏹️ [Native Pipeline] Pipeline natif terminé');
              _isNativePipelineActive = false;
              _webRtcSubscription = null;
            },
          );
    } catch (e) {
      debugPrint('⚠️ [Native Pipeline] Exception démarrage: $e');
      _lastFailedTrackId = trackId;
      _stopNativePipeline();
    }
  }

  Future<void> _poseLoop() async {
    if (kIsWeb) return;

    Future<CapturedFrame?>? next;

    while (_running) {
      if (_paused) {
        next = null;
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }

      final now = DateTime.now();
      final hasRecentNativeFrames = _lastNativeFrameReceivedAt != null &&
          now.difference(_lastNativeFrameReceivedAt!) <
              const Duration(milliseconds: 600);

      if (hasRecentNativeFrames) {
        _isNativePipelineActive = true;
        next = null;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        continue;
      }

      _isNativePipelineActive = false;

      if (_webRtcSubscription == null &&
          (_lastNativeAttemptAt == null ||
              now.difference(_lastNativeAttemptAt!) >
                  const Duration(seconds: 3))) {
        _lastNativeAttemptAt = now;
        _tryStartNativePipeline();
      }

      final loopWatch = Stopwatch()..start();
      final track = _cameraTrack();
      if (track == null) {
        next = null;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }

      final frame = await (next ?? _capture(track));
      if (!_running || _paused) break;

      if (_lastNativeFrameReceivedAt != null &&
          DateTime.now().difference(_lastNativeFrameReceivedAt!) <
              const Duration(milliseconds: 600)) {
        continue;
      }

      next = (_running && !_paused && !_isNativePipelineActive)
          ? _capture(track)
          : null;

      if (frame == null) {
        _onLost(DateTime.now());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        continue;
      }

      final detectWatch = Stopwatch()..start();
      try {
        final result = await _poseDetector.detectPoseVideo(
          frame.bytes,
          frame.videoTimestampMs,
        );
        if (!_running || _paused) break;
        detectWatch.stop();
        final detectMicros = detectWatch.elapsedMicroseconds;
        _detectMicros += detectMicros;
        _detectSamples++;
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
            _currentTargetFps = isStatic ? 15 : 30;
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
        debugPrint('⚠️ Pose detection error: $error');
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

  void _handleNativeFrameResult(FrameResult frameResult) {
    if (!_running || _paused) return;

    _lastNativeFrameReceivedAt = DateTime.now();
    _isNativePipelineActive = true;
    _lastFailedTrackId = null;

    final result = frameResult.result;
    final capturedAt =
        DateTime.fromMicrosecondsSinceEpoch(frameResult.timestampUs);
    _nativeFps = frameResult.fps;
    _currentTargetFps = frameResult.targetFps ?? 30;

    if (frameResult.isThermalThrottled != _lastThermalThrottled ||
        frameResult.isLowBattery != _lastLowBattery) {
      _lastThermalThrottled = frameResult.isThermalThrottled;
      _lastLowBattery = frameResult.isLowBattery;
    }

    if (!result.hasPoses) {
      _motionDetector.reset();
      _onLost(capturedAt);
    } else {
      final rawPose = result.firstPose!;
      final isStatic = _motionDetector.update(rawPose);
      if (isStatic != _lastIsStatic) {
        _lastIsStatic = isStatic;
        final targetFps = isStatic ? 15 : 30;
        _poseDetector.setTargetFps(targetFps);
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
        capturedAt: capturedAt,
      );
      final rawPosture = _classifier.classify(rawPose, frameSize: size);
      final posture = _stabilizePosture(rawPosture);
      _hadPose = true;
      _inferMicros += result.processingTimeMs * 1000;
      _inferSamples++;
      _detectMicros += result.processingTimeMs * 1000;
      _detectSamples++;

      _publisher.publish(
        room: _room,
        pose: pose,
        posture: posture,
        frameSize: size,
        capturedAt: capturedAt,
        deviceModel: _deviceModel,
        captureMicros: 0,
        detectMicros: result.processingTimeMs * 1000,
        inferMicros: result.processingTimeMs * 1000,
      );
    }

    _logStats();
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
      final buffer = await track.mediaStreamTrack.captureFrame();
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

    final pipelineMode = _isNativePipelineActive ? 'zero-copy-native' : 'legacy-copy';
    debugPrint(
      '📊 pose ${seconds.toStringAsFixed(2)}s '
      'pipeline=$pipelineMode '
      'model=lite resolution=$resolution '
      'device=$_deviceModel '
      'fps=${_isNativePipelineActive ? _nativeFps.toStringAsFixed(1) : (_captureSamples / seconds).toStringAsFixed(1)} '
      'targetFps=$_currentTargetFps '
      'thermal=$_lastThermalThrottled lowBat=$_lastLowBattery '
      'capture=${averageMs(_captureMicros, _captureSamples).toStringAsFixed(1)}ms '
      'detect=${averageMs(_detectMicros, _detectSamples).toStringAsFixed(1)}ms '
      'infer=${averageMs(_inferMicros, _inferSamples).toStringAsFixed(1)}ms '
      'publish=${averageMs(_publisher.publishMicros, _publisher.publishSamples).toStringAsFixed(1)}ms '
      'publishData=${(_publisher.publishedSinceStats / seconds).toStringAsFixed(1)}/s '
      'seq=${((_publisher.seq - _publisher.seqAtLastStats) / seconds).toStringAsFixed(1)}/s',
    );

    _captureMicros = 0;
    _captureSamples = 0;
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
    stop();
    frameNotifier.dispose();
    _poseDetector.dispose();
    super.dispose();
  }
}
