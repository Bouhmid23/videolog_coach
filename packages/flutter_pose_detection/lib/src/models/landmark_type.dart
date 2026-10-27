/// Enumeration of all 33 body landmarks in MediaPipe BlazePose format.
///
/// This enum follows the MediaPipe 33-keypoint topology used by BlazePose,
/// providing comprehensive body tracking including hands and feet.
///
/// ## Landmark Indices
///
/// | Index | Name | Description |
/// |-------|------|-------------|
/// | 0 | nose | Nose tip |
/// | 1 | leftEyeInner | Left eye inner corner |
/// | 2 | leftEye | Left eye center |
/// | 3 | leftEyeOuter | Left eye outer corner |
/// | 4 | rightEyeInner | Right eye inner corner |
/// | 5 | rightEye | Right eye center |
/// | 6 | rightEyeOuter | Right eye outer corner |
/// | 7 | leftEar | Left ear |
/// | 8 | rightEar | Right ear |
/// | 9 | mouthLeft | Left mouth corner |
/// | 10 | mouthRight | Right mouth corner |
/// | 11 | leftShoulder | Left shoulder |
/// | 12 | rightShoulder | Right shoulder |
/// | 13 | leftElbow | Left elbow |
/// | 14 | rightElbow | Right elbow |
/// | 15 | leftWrist | Left wrist |
/// | 16 | rightWrist | Right wrist |
/// | 17 | leftPinky | Left pinky finger |
/// | 18 | rightPinky | Right pinky finger |
/// | 19 | leftIndex | Left index finger |
/// | 20 | rightIndex | Right index finger |
/// | 21 | leftThumb | Left thumb |
/// | 22 | rightThumb | Right thumb |
/// | 23 | leftHip | Left hip |
/// | 24 | rightHip | Right hip |
/// | 25 | leftKnee | Left knee |
/// | 26 | rightKnee | Right knee |
/// | 27 | leftAnkle | Left ankle |
/// | 28 | rightAnkle | Right ankle |
/// | 29 | leftHeel | Left heel |
/// | 30 | rightHeel | Right heel |
/// | 31 | leftFootIndex | Left foot index toe |
/// | 32 | rightFootIndex | Right foot index toe |
enum LandmarkType {
  /// Nose tip (index 0)
  nose(0),

  /// Left eye inner corner (index 1)
  leftEyeInner(1),

  /// Left eye center (index 2)
  leftEye(2),

  /// Left eye outer corner (index 3)
  leftEyeOuter(3),

  /// Right eye inner corner (index 4)
  rightEyeInner(4),

  /// Right eye center (index 5)
  rightEye(5),

  /// Right eye outer corner (index 6)
  rightEyeOuter(6),

  /// Left ear (index 7)
  leftEar(7),

  /// Right ear (index 8)
  rightEar(8),

  /// Left mouth corner (index 9)
  mouthLeft(9),

  /// Right mouth corner (index 10)
  mouthRight(10),

  /// Left shoulder (index 11)
  leftShoulder(11),

  /// Right shoulder (index 12)
  rightShoulder(12),

  /// Left elbow (index 13)
  leftElbow(13),

  /// Right elbow (index 14)
  rightElbow(14),

  /// Left wrist (index 15)
  leftWrist(15),

  /// Right wrist (index 16)
  rightWrist(16),

  /// Left pinky finger (index 17)
  leftPinky(17),

  /// Right pinky finger (index 18)
  rightPinky(18),

  /// Left index finger (index 19)
  leftIndex(19),

  /// Right index finger (index 20)
  rightIndex(20),

  /// Left thumb (index 21)
  leftThumb(21),

  /// Right thumb (index 22)
  rightThumb(22),

  /// Left hip (index 23)
  leftHip(23),

  /// Right hip (index 24)
  rightHip(24),

  /// Left knee (index 25)
  leftKnee(25),

  /// Right knee (index 26)
  rightKnee(26),

  /// Left ankle (index 27)
  leftAnkle(27),

  /// Right ankle (index 28)
  rightAnkle(28),

  /// Left heel (index 29)
  leftHeel(29),

  /// Right heel (index 30)
  rightHeel(30),

  /// Left foot index toe (index 31)
  leftFootIndex(31),

  /// Right foot index toe (index 32)
  rightFootIndex(32);

  /// The numeric index of this landmark (0-32).
  final int value;

  const LandmarkType(this.value);

  /// Create a [LandmarkType] from its numeric index.
  ///
  /// Throws [ArgumentError] if the index is out of range (0-32).
  static LandmarkType fromIndex(int idx) {
    if (idx < 0 || idx > 32) {
      throw ArgumentError.value(idx, 'index', 'Must be between 0 and 32');
    }
    return LandmarkType.values[idx];
  }

  /// The total number of landmarks (33).
  static const int count = 33;
}
