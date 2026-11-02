import 'dart:math' as math;
import 'dart:ui' show Offset, Size;
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import '../../data/remote_posture.dart';

/// Classification géométrique des postures (debout, assis, allongé)
/// d'après les repères anatomiques 33 points MediaPipe.
class PostureClassifier {
  const PostureClassifier();

  RemotePosture? classify(
    Pose pose, {
    required Size frameSize,
  }) {
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

    final torsoDx = (shoulderMid.dx - hipMid.dx) * frameSize.width;
    final torsoDy = (hipMid.dy - shoulderMid.dy) * frameSize.height;
    final torsoAngleDeg =
        math.atan2(
          torsoDx.abs(),
          torsoDy.abs().clamp(1e-6, double.infinity).toDouble(),
        ) *
        180 /
        math.pi;

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
      final legTorsoLength =
          math.max((hipMid.dy - shoulderMid.dy).abs() * frameSize.height, 1e-6);
      final kneeDrop = kneeMid == null
          ? 0.0
          : (kneeMid.dy - hipMid.dy) * frameSize.height / legTorsoLength;
      final ankleDrop = ankleMid == null
          ? 0.0
          : (ankleMid.dy - hipMid.dy) * frameSize.height / legTorsoLength;
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
}

/// Stabilisateur de label postural par hystérésis.
/// Le label ne change qu'après [_labelHoldFrames] frames consécutives identiques.
class PostureStabilizer {
  static const int _labelHoldFrames = 3;

  String? _stableLabel;
  String? _candidateLabel;
  int _candidateCount = 0;
  DateTime? _lossStartedAt;

  void onPoseLost() {
    _lossStartedAt ??= DateTime.now();
  }

  void reset() {
    _stableLabel = null;
    _candidateLabel = null;
    _candidateCount = 0;
    _lossStartedAt = null;
  }

  RemotePosture? stabilize(RemotePosture? raw) {
    if (raw == null) {
      _candidateLabel = null;
      _candidateCount = 0;
      return null;
    }

    final lossStartedAt = _lossStartedAt;
    if (lossStartedAt != null &&
        DateTime.now().difference(lossStartedAt) >
            const Duration(milliseconds: 900)) {
      _candidateLabel = null;
      _candidateCount = 0;
    }
    _lossStartedAt = null;

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

    return RemotePosture(
      label: _stableLabel!,
      confidence: raw.confidence,
      receivedAt: raw.receivedAt,
    );
  }
}

