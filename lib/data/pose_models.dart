import 'dart:math' as math;
import 'dart:ui';

/// Les 33 repères anatomiques de la topologie MediaPipe BlazePose.
enum LandmarkType {
  nose(0),
  leftEyeInner(1),
  leftEye(2),
  leftEyeOuter(3),
  rightEyeInner(4),
  rightEye(5),
  rightEyeOuter(6),
  leftEar(7),
  rightEar(8),
  mouthLeft(9),
  mouthRight(10),
  leftShoulder(11),
  rightShoulder(12),
  leftElbow(13),
  rightElbow(14),
  leftWrist(15),
  rightWrist(16),
  leftPinky(17),
  rightPinky(18),
  leftIndex(19),
  rightIndex(20),
  leftThumb(21),
  rightThumb(22),
  leftHip(23),
  rightHip(24),
  leftKnee(25),
  rightKnee(26),
  leftAnkle(27),
  rightAnkle(28),
  leftHeel(29),
  rightHeel(30),
  leftFootIndex(31),
  rightFootIndex(32);

  final int value;

  const LandmarkType(this.value);

  static LandmarkType fromIndex(int idx) {
    if (idx < 0 || idx >= count) {
      throw ArgumentError.value(idx, 'index', 'Must be between 0 and 32');
    }
    return LandmarkType.values[idx];
  }

  static const int count = 33;
}

/// Point anatomique en espace image (coordonnées normalisées par MediaPipe).
class PoseLandmark {
  final LandmarkType type;
  final double x;
  final double y;
  final double z;
  final double visibility;

  const PoseLandmark({
    required this.type,
    required this.x,
    required this.y,
    this.z = 0.0,
    required this.visibility,
  });

  const PoseLandmark.notDetected(this.type)
      : x = 0.0,
        y = 0.0,
        z = 0.0,
        visibility = 0.0;

  bool get isDetected => visibility > 0;

  bool isReliable({double threshold = 0.5}) => visibility >= threshold;

  Offset toPixelCoordinates(int imageWidth, int imageHeight) =>
      Offset(x * imageWidth, y * imageHeight);
}

/// Point anatomique en coordonnées métriques 3D (origine au centre des hanches).
class WorldLandmark {
  const WorldLandmark({
    required this.typeIndex,
    required this.x,
    required this.y,
    required this.z,
    required this.visibility,
  });

  final int typeIndex;
  final double x;
  final double y;
  final double z;
  final double visibility;
}

/// Une pose détectée composée des 33 repères image et des world landmarks 3D.
class Pose {
  final List<PoseLandmark> landmarks;
  final List<WorldLandmark> worldLandmarks;
  final double score;

  const Pose({
    required this.landmarks,
    required this.score,
    this.worldLandmarks = const [],
  });

  PoseLandmark getLandmark(LandmarkType type) => landmarks[type.value];

  PoseLandmark operator [](int index) => landmarks[index];

  List<PoseLandmark> getVisibleLandmarks({double threshold = 0.5}) =>
      landmarks.where((l) => l.visibility >= threshold).toList();

  double? calculateAngle(
    LandmarkType point1,
    LandmarkType vertex,
    LandmarkType point2,
  ) {
    final p1 = getLandmark(point1);
    final v = getLandmark(vertex);
    final p2 = getLandmark(point2);
    if (!p1.isDetected || !v.isDetected || !p2.isDetected) {
      return null;
    }

    final v1x = p1.x - v.x;
    final v1y = p1.y - v.y;
    final v2x = p2.x - v.x;
    final v2y = p2.y - v.y;
    final mag1 = math.sqrt(v1x * v1x + v1y * v1y);
    final mag2 = math.sqrt(v2x * v2x + v2y * v2y);
    if (mag1 == 0 || mag2 == 0) return null;

    final cosAngle = ((v1x * v2x + v1y * v2y) / (mag1 * mag2)).clamp(-1.0, 1.0);
    return math.acos(cosAngle) * 180.0 / math.pi;
  }
}

/// Résultat d'une inférence de détection de pose avec métriques de latence.
class PoseDetectionResult {
  const PoseDetectionResult({
    required this.poses,
    required this.processingTimeMs,
    this.decodeTimeMs = 0,
    required this.imageWidth,
    required this.imageHeight,
    required this.delegateName,
  });

  final List<Pose> poses;
  final int processingTimeMs;
  final int decodeTimeMs;
  final int imageWidth;
  final int imageHeight;
  final String delegateName;

  bool get hasPoses => poses.isNotEmpty;
  Pose? get firstPose => poses.isNotEmpty ? poses.first : null;
}
