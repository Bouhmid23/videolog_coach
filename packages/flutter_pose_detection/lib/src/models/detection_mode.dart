/// Detection mode controlling the speed/accuracy trade-off.
///
/// Choose a mode based on your use case:
/// - [fast] for realtime camera streams where frame rate matters
/// - [balanced] for general use with good accuracy
/// - [accurate] for still images or video analysis where precision matters
///
/// ## Performance Comparison
///
/// | Mode | Target FPS | Use Case |
/// |------|-----------|----------|
/// | fast | 30+ | Realtime camera, games |
/// | balanced | 20+ | General purpose |
/// | accurate | 15+ | Photo analysis, form checking |
///
/// ## Android Model Selection
///
/// On Android, the detection mode affects which MoveNet model variant is used:
/// - [fast] and [balanced]: MoveNet Lightning (192x192 input)
/// - [accurate]: MoveNet Thunder (256x256 input)
///
/// ## Example
///
/// ```dart
/// // For camera stream
/// final config = PoseDetectorConfig(mode: DetectionMode.fast);
///
/// // For photo analysis
/// final config = PoseDetectorConfig(mode: DetectionMode.accurate);
/// ```
enum DetectionMode {
  /// Optimized for speed.
  ///
  /// Best for realtime applications where frame rate is critical.
  /// Uses MoveNet Lightning model on Android.
  /// Target: 30+ FPS.
  fast,

  /// Balanced speed and accuracy.
  ///
  /// Good for general purpose use.
  /// Uses MoveNet Lightning model on Android.
  /// Target: 20+ FPS.
  balanced,

  /// Optimized for accuracy.
  ///
  /// Best for still images or when precision matters more than speed.
  /// Uses MoveNet Thunder model on Android.
  /// Target: 15+ FPS.
  accurate;

  /// Create a [DetectionMode] from its string representation.
  ///
  /// Returns [balanced] if the string doesn't match any known mode.
  static DetectionMode fromString(String value) {
    return DetectionMode.values.firstWhere(
      (mode) => mode.name == value.toLowerCase(),
      orElse: () => DetectionMode.balanced,
    );
  }
}
