import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show ChangeNotifier, ValueNotifier, kIsWeb, debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:livekit_client/livekit_client.dart';

import '../core/posture_detection_service.dart';
import '../data/posture_codec.dart';
import '../data/remote_posture.dart';

/// Octets d'une frame et instant où elle a été capturée. Le timestamp reste
/// attaché à l'image : la capture N+1 tourne pendant la détection N.
class _CapturedFrame {
  const _CapturedFrame(this.bytes, this.capturedAt);

  final Uint8List bytes;
  final DateTime capturedAt;
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

/// Capture la caméra locale, détecte la pose (NPU) et publie le squelette
/// en binaire sur le topic `posture`. La dernière pose est aussi exposée via
/// [frameNotifier] pour le rendu local du squelette.
///
/// Choix pour le temps réel :
///  - pipeline à 2 étages : la capture N+1 démarre pendant la détection N ;
///  - aucune limitation de cadence ni delta encoding (≈3 Ko/s à 30 fps) ;
///  - canal lossy, `publishData` non attendu ;
///  - taille de frame lue dans l'en-tête PNG (pas de décodage d'image) ;
///  - paquet « pose perdue » pour que le web efface le squelette.
class PoseDetectionViewModel extends ChangeNotifier {
  final PostureSmoothing _smoothing = PostureSmoothing();

  final NpuPoseDetector _poseDetector = NpuPoseDetector(
    // Force the plugin's TFLite/QNN path. Its default MediaPipe path requires
    // libmediapipe_tasks_vision_jni.so, which is missing for x86_64 and can
    // fail to load on some device builds. TFLite falls back to CPU when QNN
    // is unavailable, including on Google Tensor and non-Snapdragon devices.
    config: PoseDetectorConfig(
      //maxPoses: ,
      //preferredAcceleration: AccelerationMode.cpu,
      enableZEstimation: true,
      minConfidence: 0.6,
      mode: DetectionMode.fast,
    ),
  );

  /// Nombre de frames consécutives requises pour changer de label.
  static const int _labelHoldFrames = 3;
  static const Size _fallbackSize = Size(480, 640);

  bool _running = false;
  Room? _room;
  List<String>? _destinationIdentities;
  int _seq = 0;

  Size? _lastSize;
  bool _hadPose = false;
  DateTime _lastLostSent = DateTime.fromMillisecondsSinceEpoch(0);

  // Mesures (moyennes et débits calculés sur une fenêtre d'une seconde).
  int _captureMicros = 0;
  int _captureSamples = 0;
  int _detectMicros = 0;
  int _detectSamples = 0;
  int _publishMicros = 0;
  int _publishSamples = 0;
  int _publishedSinceStats = 0;
  int _seqAtLastStats = 0;
  DateTime _statsWindowStart = DateTime.now();

  // Stabilisation du label (hystérésis)
  String? _stableLabel;
  String? _candidateLabel;
  int _candidateCount = 0;

  RemotePosture? _currentPosture;

  /// Dernière pose (coordonnées source + taille de frame) pour l'overlay local.
  final ValueNotifier<PoseFrame?> frameNotifier = ValueNotifier<PoseFrame?>(null);

  RemotePosture? get currentPosture => _currentPosture;
  bool get isBusy => _running;

  Future<void> init() async {
    final acceleration = await _poseDetector.initialize();
    final config = _poseDetector.config;
    debugPrint('🧠 Pose detector ready: acceleration=${acceleration.name} '
        'mode=${config.mode.name} maxPoses=${config.maxPoses} '
        'zEstimation=${config.enableZEstimation}');
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
    _lastSize = null;
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
        final result = await _poseDetector.detectPose(frame.bytes);
        if (!_running) break;
        detectWatch.stop();
        _detectMicros += detectWatch.elapsedMicroseconds;
        _detectSamples++;

        if (!result.hasPoses) {
          _onLost(frame.capturedAt);
        } else {
          final size = await _frameSize(frame.bytes);
          if (kDebugMode) _debugLog(frame.bytes, result.firstPose!, size);
          _lastSize = size;
          final pose = _smoothing.smooth(result.firstPose!);
          frameNotifier.value = PoseFrame(
            pose: pose,
            frameSize: size,
            capturedAt: frame.capturedAt,
          );
          final posture = _stabilizedPosture(classifyPosture(pose));
          _hadPose = true;
          _publish(pose, posture, size, capturedAt: frame.capturedAt);
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

  /// Moyennes capture/détection/publication et débits sur la dernière seconde.
  /// `publishData/s` doit être égal au débit de `seq`.
  void _logStats() {
    final now = DateTime.now();
    final elapsed = now.difference(_statsWindowStart);
    if (elapsed < const Duration(seconds: 1)) return;

    final seconds = elapsed.inMicroseconds / 1000000.0;
    double averageMs(int micros, int samples) =>
        samples == 0 ? 0 : micros / samples / 1000.0;

    debugPrint(
      '📊 pose ${seconds.toStringAsFixed(2)}s '
      'capture=${averageMs(_captureMicros, _captureSamples).toStringAsFixed(1)}ms '
      'detect=${averageMs(_detectMicros, _detectSamples).toStringAsFixed(1)}ms '
      'publish=${averageMs(_publishMicros, _publishSamples).toStringAsFixed(1)}ms '
      'capture=${(_captureSamples / seconds).toStringAsFixed(1)}fps '
      'publishData=${(_publishedSinceStats / seconds).toStringAsFixed(1)}/s '
      'seq=${((_seq - _seqAtLastStats) / seconds).toStringAsFixed(1)}/s',
    );

    _captureMicros = 0;
    _captureSamples = 0;
    _detectMicros = 0;
    _detectSamples = 0;
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
    try {
      final buffer = await track.mediaStreamTrack.captureFrame();
      return _CapturedFrame(Uint8List.view(buffer), capturedAt);
    } catch (error) {
      debugPrint('⚠️ Pose capture failed: $error');
      return null;
    } finally {
      watch.stop();
      _captureMicros += watch.elapsedMicroseconds;
      _captureSamples++;
    }
  }

  DateTime _sizeCheckedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastDebug = DateTime.fromMillisecondsSinceEpoch(0);

  /// Taille de la frame capturée : en-tête PNG/JPEG (gratuit) ; sinon décodage
  /// de l'image, mis en cache et revérifié toutes les 3 s (rotation).
  /// Une taille fausse fausse toute la normalisation des landmarks.
  Future<Size> _frameSize(Uint8List bytes) async {
    final header = _pngSize(bytes) ?? _jpegSize(bytes);
    if (header != null) {
      _lastSize = header;
      return header;
    }
    final now = DateTime.now();
    if (_lastSize == null ||
        now.difference(_sizeCheckedAt) > const Duration(seconds: 3)) {
      _sizeCheckedAt = now;
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        try {
          final frame = await codec.getNextFrame();
          _lastSize = Size(
            frame.image.width.toDouble(),
            frame.image.height.toDouble(),
          );
          frame.image.dispose();
        } finally {
          codec.dispose();
        }
      } catch (error) {
        debugPrint('⚠️ Frame size decode failed: $error');
      }
    }
    return _lastSize ?? _fallbackSize;
  }

  /// Taille d'un JPEG lue dans le marqueur SOF. Renvoie null si [b] n'est pas un JPEG.
  Size? _jpegSize(Uint8List b) {
    if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
    var i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = b[i + 1];
      if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      final len = (b[i + 2] << 8) | b[i + 3];
      final isSof = marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isSof) {
        final h = (b[i + 5] << 8) | b[i + 6];
        final w = (b[i + 7] << 8) | b[i + 8];
        return Size(w.toDouble(), h.toDouble());
      }
      i += 2 + len;
    }
    return null;
  }

  /// Une ligne toutes les 2 s (debug uniquement) : sert à vérifier la taille de
  /// frame et l'espace des coordonnées (pixels ou 0..1) renvoyés par le détecteur.
  void _debugLog(Uint8List bytes, Pose pose, Size size) {
    final now = DateTime.now();
    if (now.difference(_lastDebug) < const Duration(seconds: 2)) return;
    _lastDebug = now;
    final shoulder = pose.getLandmark(LandmarkType.leftShoulder);
    final hip = pose.getLandmark(LandmarkType.leftHip);
    final zs = pose.landmarks
        .where((l) => l.visibility > 0.5)
        .map((l) => l.z)
        .toList();
    final zMin = zs.isEmpty ? 0.0 : zs.reduce(math.min);
    final zMax = zs.isEmpty ? 0.0 : zs.reduce(math.max);
    debugPrint('📐 frame=${size.width.toInt()}x${size.height.toInt()} '
        'magic=${bytes[0].toRadixString(16)}${bytes[1].toRadixString(16)} '
        'shoulder=(${shoulder.x}, ${shoulder.y}) '
        'hip=(${hip.x}, ${hip.y}, vis=${hip.visibility}) '
        'z[min..max]=${zMin.toStringAsFixed(3)}..${zMax.toStringAsFixed(3)}');
  }

  /// Taille d'un PNG lue dans l'en-tête IHDR (largeur 16-19, hauteur 20-23).
  /// Renvoie null si [b] n'est pas un PNG.
  Size? _pngSize(Uint8List b) {
    if (b.length < 24 || b[0] != 0x89 || b[1] != 0x50) return null;
    final bd = ByteData.sublistView(b);
    return Size(bd.getUint32(16).toDouble(), bd.getUint32(20).toDouble());
  }

  // ---------------------------------------------------------------------------
  // Publication
  // ---------------------------------------------------------------------------

  void _publish(
    Pose pose,
    RemotePosture? posture,
    Size frameSize, {
    required DateTime capturedAt,
  }) {
    if (_room?.localParticipant == null) return;

    final bytes = PostureCodec.encode(
      label: posture?.label ?? 'inconnu',
      confidence: posture?.confidence,
      landmarks: pose.landmarks,
      frameSize: frameSize,
      seq: ++_seq,
      timestampMs: capturedAt.millisecondsSinceEpoch,
    );
    _send(bytes, 'posture');
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
  void _send(Uint8List bytes, String kind) {
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
    if (_hadPose || now.difference(_lastLostSent) > const Duration(milliseconds: 500)) {
      _hadPose = false;
      _lastLostSent = now;
      _publishLost(capturedAt);
    }
    _stableLabel = null;
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
    final torsoAngleDeg = math.atan2(
      torsoDx.abs(),
      torsoDy.abs().clamp(1e-6, double.infinity).toDouble(),
    ) *
        180 /
        math.pi;

    // Plancher minuscule (et non 1.0) : valable que les coordonnées soient
    // en pixels ou normalisées 0..1.
    final torsoLength = math.max((hipMid.dy - shoulderMid.dy).abs(), 1e-6);
    final kneeDrop =
    kneeMid == null ? 0.0 : (kneeMid.dy - hipMid.dy) / torsoLength;
    final ankleDrop =
    ankleMid == null ? 0.0 : (ankleMid.dy - hipMid.dy) / torsoLength;

    final confidence = averageLikelihood([
      landmark(LandmarkType.leftShoulder),
      landmark(LandmarkType.rightShoulder),
      landmark(LandmarkType.leftHip),
      landmark(LandmarkType.rightHip),
    ]);

    final label = torsoAngleDeg > 48
        ? 'allong\u00e9'
        : (kneeDrop < 0.35 && ankleDrop < 0.7 ? 'assis' : 'debout');

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

