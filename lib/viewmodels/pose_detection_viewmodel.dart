import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show ChangeNotifier, ValueNotifier, kDebugMode, kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../core/posture_detection_service.dart';
import '../data/posture_codec.dart';
import '../data/remote_posture.dart';

/// Chemin du JPEG capturé et instant où l'image a été prise. Le timestamp
/// reste attaché à l'image : la capture N+1 tourne pendant la détection N.
class _CapturedFrame {
  const _CapturedFrame(
    this.bytes,
    this.capturedAt,
    this.videoTimestampMs,
    this.captureMicros,
  );

  final Uint8List bytes;
  final DateTime capturedAt;
  final int videoTimestampMs;
  final int captureMicros;
}

/// Dernière pose détectée, prête à être dessinée par l'UI.
class PoseFrame {
  const PoseFrame({
    required this.pose,
    required this.frameSize,
    required this.capturedAt,
  });

  final Pose pose;
  final Size frameSize;
  final DateTime capturedAt;
}

/// Capture la caméra locale, détecte la pose (MediaPipe lite en mode VIDEO) et publie le squelette
/// en binaire sur le topic `posture`. La dernière pose est aussi exposée via
/// [frameNotifier] pour le rendu local du squelette.
///
/// Choix pour le temps réel :
///  - pipeline à 2 étages : la capture N+1 démarre pendant la détection N ;
///  - aucune limitation de cadence ni delta encoding (≈8.25 Ko/s à 30 poses/s) ;
///  - canal lossy, `publishData` non attendu ;
///  - capture JPEG gardée en mémoire et dimensions lues depuis le résultat ;
///  - paquet « pose perdue » pour que le web efface le squelette.
class PoseDetectionViewModel extends ChangeNotifier {
  final PostureSmoothing _smoothing = PostureSmoothing();

  final NpuPoseDetector _poseDetector = NpuPoseDetector(
    // Le backend GPU MediaPipe est le plus rapide pour un flux caméra continu.
    // Le mode NPU/QNN vise l'autonomie mais est plus lent et nécessite des
    // bibliothèques QNN supplémentaires non embarquées dans l'application.
    config: PoseDetectorConfig.realtime().copyWith(
      maxPoses: 1,
      minConfidence: 0.5,
      minPoseDetectionConfidence: 0.5,
      minPosePresenceConfidence: 0.5,
      minTrackingConfidence: 0.5,
      enableZEstimation: true,
      preferredAcceleration: AccelerationMode.gpu,
    ),
  );

  /// Nombre de frames consécutives requises pour changer de label.
  static const int _labelHoldFrames = 3;
  static const Size _fallbackSize = Size(480, 640);

  bool _running = false;
  Room? _room;
  List<String>? _destinationIdentities;
  int _seq = 0;

  bool _hadPose = false;
  DateTime _lastLostSent = DateTime.fromMillisecondsSinceEpoch(0);

  // Mesures (moyennes et débits calculés sur une fenêtre d'une seconde).
  int _captureMicros = 0;
  int _captureSamples = 0;
  int _detectMicros = 0;
  int _detectSamples = 0;
  int _inferMicros = 0;
  int _inferSamples = 0;
  int _publishMicros = 0;
  int _publishSamples = 0;
  int _publishedSinceStats = 0;
  int _seqAtLastStats = 0;
  DateTime _statsWindowStart = DateTime.now();
  DateTime _lastRuntimeLandmarkLog = DateTime.fromMillisecondsSinceEpoch(0);
  Size? _lastFrameSize;

  final Stopwatch _videoClock = Stopwatch()..start();


  // Stabilisation du label (hystérésis)
  String? _stableLabel;
  String? _candidateLabel;
  int _candidateCount = 0;

  RemotePosture? _currentPosture;

  /// Dernière pose (coordonnées source + taille de frame) pour l'overlay local.
  final ValueNotifier<PoseFrame?> frameNotifier = ValueNotifier<PoseFrame?>(
    null,
  );

  RemotePosture? get currentPosture => _currentPosture;
  bool get isBusy => _running;

  Future<void> init() async {
    final acceleration = await _poseDetector.initialize();
    final config = _poseDetector.config;
    debugPrint(
      '🧠 Pose detector ready: acceleration=${acceleration.name} '
      'mode=${config.mode.name} maxPoses=${config.maxPoses} '
      'minConfidence=${config.minConfidence} '
      'detection=${config.effectivePoseDetectionConfidence} '
      'presence=${config.effectivePosePresenceConfidence} '
      'tracking=${config.effectiveTrackingConfidence} '
      'zEstimation=${config.enableZEstimation} runningMode=VIDEO',
    );
  }

  /// [destinationIdentities] : si seul le viewer web consomme le squelette,
  /// renseigne son identité pour éviter le fan-out vers les autres participants.
  void start(Room room, {List<String>? destinationIdentities}) {
    _room = room;
    setDestinationIdentities(destinationIdentities);
    if (_running) return;
    _running = true;
    _statsWindowStart = DateTime.now();
    _seqAtLastStats = _seq;
    unawaited(_poseLoop());
    debugPrint('🏃 Pose detection started (temps réel)');
  }

  /// Met à jour les destinataires sans redémarrer la boucle. Une liste vide
  /// (aucun viewer connu) revient au comportement par défaut : tous les
  /// participants, car LiveKit traite une liste vide comme un broadcast.
  void setDestinationIdentities(List<String>? identities) {
    _destinationIdentities = (identities == null || identities.isEmpty)
        ? null
        : List<String>.unmodifiable(identities);
  }

  void stop() {
    if (_running && _hadPose) _publishLost(DateTime.now());
    _running = false;
    _hadPose = false;
    _stableLabel = null;
    _candidateLabel = null;
    _candidateCount = 0;
    _currentPosture = null;
    _smoothing.reset();
    frameNotifier.value = null;
  }

  // ---------------------------------------------------------------------------
  // Boucle capture -> détection -> publication
  // ---------------------------------------------------------------------------

  Future<void> _poseLoop() async {
    if (kIsWeb) return;
    Future<_CapturedFrame?>? next;

    while (_running) {
      final track = _cameraTrack();
      if (track == null) {
        next = null;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }

      // La frame courante a été capturée pendant la détection précédente ;
      // son timestamp de capture voyage avec ses octets.
      final frame = await (next ?? _capture(track));
      // Lance déjà la capture suivante, en parallèle de la détection.
      next = _running ? _capture(track) : null;

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
        if (!_running) break;
        detectWatch.stop();
        final detectMicros = detectWatch.elapsedMicroseconds;
        _detectMicros += detectMicros;
        _detectSamples++;
        _inferMicros += result.processingTimeMs * 1000;
        _inferSamples++;

        if (!result.hasPoses) {
          _onLost(frame.capturedAt);
        } else {
          final size = result.imageWidth > 0 && result.imageHeight > 0
              ? Size(
                  result.imageWidth.toDouble(),
                  result.imageHeight.toDouble(),
                )
              : _fallbackSize;
          _lastFrameSize = size;
          final pose = _smoothing.smooth(result.firstPose!);
          _logRuntimeLandmarks(pose);
          frameNotifier.value = PoseFrame(
            pose: pose,
            frameSize: size,
            capturedAt: frame.capturedAt,
          );
          final posture = _stabilizedPosture(classifyPosture(pose));
          _hadPose = true;
          _publish(
            pose,
            posture,
            size,
            capturedAt: frame.capturedAt,
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

      // Rend la main à la boucle d'événements.
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Runtime evidence: prints detector image-z and MediaPipe metric world-z
  /// ranges so the on-device configuration/output can be checked in logcat.
  void _logRuntimeLandmarks(Pose pose) {
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

  /// Moyennes capture/détection/publication et débits sur la dernière seconde.
  /// `publishData/s` doit être égal au débit de `seq`.
  void _logStats() {
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

    debugPrint(
      '📊 pose ${seconds.toStringAsFixed(2)}s '
      'model=lite resolution=$resolution '
      'capture=${averageMs(_captureMicros, _captureSamples).toStringAsFixed(1)}ms '
      'detect=${averageMs(_detectMicros, _detectSamples).toStringAsFixed(1)}ms '
      'infer=${averageMs(_inferMicros, _inferSamples).toStringAsFixed(1)}ms '
      'publish=${averageMs(_publishMicros, _publishSamples).toStringAsFixed(1)}ms '
      'capture=${(_captureSamples / seconds).toStringAsFixed(1)}fps '
      'publishData=${(_publishedSinceStats / seconds).toStringAsFixed(1)}/s '
      'seq=${((_seq - _seqAtLastStats) / seconds).toStringAsFixed(1)}/s',
    );

    _captureMicros = 0;
    _captureSamples = 0;
    _detectMicros = 0;
    _detectSamples = 0;
    _inferMicros = 0;
    _inferSamples = 0;
    _publishMicros = 0;
    _publishSamples = 0;
    _publishedSinceStats = 0;
    _seqAtLastStats = _seq;
    _statsWindowStart = now;
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

  Future<_CapturedFrame?> _capture(LocalVideoTrack track) async {
    final watch = Stopwatch()..start();
    // Horodatage AVANT la capture : c'est l'instant où l'image est prise, pas
    // celui où l'inférence se termine ni celui de la publication.
    final capturedAt = DateTime.now();
    final videoTimestampMs = _videoClock.elapsedMilliseconds;
    try {
      final buffer = await track.mediaStreamTrack.captureFrame();
      final captureMicros = watch.elapsedMicroseconds;
      return _CapturedFrame(
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

  // ---------------------------------------------------------------------------
  // Publication
  // ---------------------------------------------------------------------------

  void _publish(
    Pose pose,
    RemotePosture? posture,
    Size frameSize, {
    required DateTime capturedAt,
    required int captureMicros,
    required int detectMicros,
    required int inferMicros,
  }) {
    if (_room?.localParticipant == null) return;

    final seq = ++_seq;
    final bytes = PostureCodec.encode(
      label: posture?.label ?? 'inconnu',
      confidence: posture?.confidence,
      landmarks: pose.landmarks,
      worldLandmarks: pose.worldLandmarks,
      frameSize: frameSize,
      seq: seq,
      timestampMs: capturedAt.millisecondsSinceEpoch,
    );
    _send(
      bytes,
      'posture',
      frameSeq: seq,
      frameSize: frameSize,
      captureMicros: captureMicros,
      detectMicros: detectMicros,
      inferMicros: inferMicros,
    );
  }

  void _publishLost(DateTime capturedAt) {
    if (_room?.localParticipant == null) return;
    _send(
      PostureCodec.encodeLost(
        ++_seq,
        timestampMs: capturedAt.millisecondsSinceEpoch,
      ),
      'lost',
    );
  }

  /// Envoi lossy non attendu, avec mesure de la durée jusqu'au retour du futur.
  void _send(
    Uint8List bytes,
    String kind, {
    int? frameSeq,
    Size? frameSize,
    int? captureMicros,
    int? detectMicros,
    int? inferMicros,
  }) {
    final participant = _room?.localParticipant;
    if (participant == null) return;

    _publishedSinceStats++;
    final watch = Stopwatch()..start();
    unawaited(
      participant
          .publishData(
            bytes,
            reliable: false,
            topic: 'posture',
            destinationIdentities: _destinationIdentities,
          )
          .then((_) {
            watch.stop();
            _publishMicros += watch.elapsedMicroseconds;
            _publishSamples++;
            if (kDebugMode && frameSeq != null && frameSize != null) {
              debugPrint(
                '📊 pose-frame seq=$frameSeq model=lite '
                'resolution=${frameSize.width.toInt()}x${frameSize.height.toInt()} '
                'capture=${(captureMicros ?? 0) / 1000.0}ms '
                'detect=${(detectMicros ?? 0) / 1000.0}ms '
                'infer=${(inferMicros ?? 0) / 1000.0}ms '
                'publish=${watch.elapsedMicroseconds / 1000.0}ms',
              );
            }
          })
          .catchError((Object e) {
            watch.stop();
            _publishMicros += watch.elapsedMicroseconds;
            _publishSamples++;
            debugPrint('⚠️ Failed to publish $kind: $e');
          }),
    );
  }

  /// Pose absente : un paquet « perdu » à la transition, puis un rappel
  /// toutes les 500 ms tant que la pose reste absente.
  void _onLost(DateTime capturedAt) {
    final now = DateTime.now();
    if (_hadPose ||
        now.difference(_lastLostSent) > const Duration(milliseconds: 500)) {
      _hadPose = false;
      _lastLostSent = now;
      _publishLost(capturedAt);
    }
    // Keep the last stable label through transient detector dropouts; otherwise
    // the next first frame bypasses the three-frame hysteresis.
    _candidateLabel = null;
    _candidateCount = 0;
    _smoothing.reset();
    frameNotifier.value = null;
    if (_currentPosture != null) {
      _currentPosture = null;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Classification
  // ---------------------------------------------------------------------------

  /// Hystérésis : le label ne change qu'après [_labelHoldFrames] frames
  /// consécutives identiques. N'affecte pas le squelette, seulement le label.
  RemotePosture? _stabilizedPosture(RemotePosture? raw) {
    if (raw == null) {
      _candidateLabel = null;
      _candidateCount = 0;
      if (_currentPosture != null) {
        _currentPosture = null;
        notifyListeners();
      }
      return null;
    }

    if (_stableLabel == null) {
      _stableLabel = raw.label;
    } else if (raw.label == _stableLabel) {
      _candidateLabel = null;
      _candidateCount = 0;
    } else if (raw.label == _candidateLabel) {
      if (++_candidateCount >= _labelHoldFrames) {
        _stableLabel = raw.label;
        _candidateLabel = null;
        _candidateCount = 0;
      }
    } else {
      _candidateLabel = raw.label;
      _candidateCount = 1;
    }

    final stabilized = RemotePosture(
      label: _stableLabel!,
      confidence: raw.confidence,
      receivedAt: raw.receivedAt,
    );

    // On ne notifie l'UI que si le label change (pas à chaque frame).
    if (_currentPosture?.label != stabilized.label) {
      _currentPosture = stabilized;
      notifyListeners();
    } else {
      _currentPosture = stabilized;
    }
    return stabilized;
  }

  RemotePosture? classifyPosture(Pose pose) {
    PoseLandmark? landmark(LandmarkType type) => pose.getLandmark(type);
    bool visible(LandmarkType type) =>
        (landmark(type)?.visibility ?? 0) >= 0.5;

    double averageLikelihood(List<PoseLandmark?> landmarks) {
      final values = landmarks
          .whereType<PoseLandmark>()
          .map((item) => item.visibility)
          .toList();
      if (values.isEmpty) return 0.0;
      return values.reduce((a, b) => a + b) / values.length;
    }

    Offset? midpoint(LandmarkType a, LandmarkType b) {
      final left = landmark(a);
      final right = landmark(b);
      if (left == null || right == null) return null;
      return Offset((left.x + right.x) / 2, (left.y + right.y) / 2);
    }

    const torsoPoints = [
      LandmarkType.leftShoulder,
      LandmarkType.rightShoulder,
      LandmarkType.leftHip,
      LandmarkType.rightHip,
    ];
    if (!torsoPoints.every(visible)) return null;

    final shoulderMid = midpoint(
      LandmarkType.leftShoulder,
      LandmarkType.rightShoulder,
    );
    final hipMid = midpoint(LandmarkType.leftHip, LandmarkType.rightHip);
    if (shoulderMid == null || hipMid == null) return null;

    final kneeMid = midpoint(LandmarkType.leftKnee, LandmarkType.rightKnee);
    final ankleMid = midpoint(LandmarkType.leftAnkle, LandmarkType.rightAnkle);

    final torsoDx = shoulderMid.dx - hipMid.dx;
    final torsoDy = hipMid.dy - shoulderMid.dy;
    final torsoAngleDeg =
        math.atan2(
          torsoDx.abs(),
          torsoDy.abs().clamp(1e-6, double.infinity).toDouble(),
        ) *
        180 /
        math.pi;

    // A horizontal torso is enough to identify lying down. For seated/standing,
    // require visible knees and ankles instead of interpreting missing points
    // at (0, 0) as a standing posture.
    late final String label;
    if (torsoAngleDeg > 48) {
      label = 'allong\u00e9';
    } else {
      const legPoints = [
        LandmarkType.leftKnee,
        LandmarkType.rightKnee,
        LandmarkType.leftAnkle,
        LandmarkType.rightAnkle,
      ];
      if (!legPoints.every(visible)) return null;
      final legTorsoLength = math.max((hipMid.dy - shoulderMid.dy).abs(), 1e-6);
      final kneeDrop = kneeMid == null
          ? 0.0
          : (kneeMid.dy - hipMid.dy) / legTorsoLength;
      final ankleDrop = ankleMid == null
          ? 0.0
          : (ankleMid.dy - hipMid.dy) / legTorsoLength;
      label = kneeDrop < 0.35 && ankleDrop < 0.7 ? 'assis' : 'debout';
    }

    final confidence = averageLikelihood([
      landmark(LandmarkType.leftShoulder),
      landmark(LandmarkType.rightShoulder),
      landmark(LandmarkType.leftHip),
      landmark(LandmarkType.rightHip),
    ]);

    return RemotePosture(
      label: label,
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
      receivedAt: DateTime.now(),
    );
  }

  @override
  void dispose() {
    stop();
    frameNotifier.dispose();
    _poseDetector.dispose();
    super.dispose();
  }
}
