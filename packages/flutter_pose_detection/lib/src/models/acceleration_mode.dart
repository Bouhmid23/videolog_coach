/// Hardware acceleration mode used for ML inference.
///
/// The plugin automatically selects the best available acceleration mode
/// for the current device. You can check which mode is being used via
/// [NpuPoseDetector.accelerationMode] after initialization.
///
/// ## Platform Behavior
///
/// ### iOS
/// - Always uses Neural Engine when available (automatic via Vision Framework)
/// - Reports [npu] on devices with Neural Engine (A12+)
/// - Falls back to [cpu] on older devices
///
/// ### Android
/// - Tries GPU delegate first (most reliable acceleration)
/// - Falls back to NNAPI on API 27-34 if GPU fails
/// - Falls back to CPU with XNNPack if all else fails
///
/// ## Example
///
/// ```dart
/// final detector = NpuPoseDetector();
/// final mode = await detector.initialize();
///
/// switch (mode) {
///   case AccelerationMode.npu:
///     print('Using Neural Engine / NPU');
///     break;
///   case AccelerationMode.gpu:
///     print('Using GPU acceleration');
///     break;
///   case AccelerationMode.cpu:
///     print('Using CPU (performance may be reduced)');
///     break;
///   case AccelerationMode.unknown:
///     print('Acceleration mode not determined');
///     break;
/// }
/// ```
enum AccelerationMode {
  /// Neural Processing Unit acceleration.
  ///
  /// On iOS, this indicates the Neural Engine is being used (automatic).
  /// On Android, this indicates NNAPI is being used (API 27-34 only).
  npu,

  /// GPU-accelerated inference.
  ///
  /// On iOS, GPU is handled internally by Vision Framework.
  /// On Android, this indicates the TensorFlow Lite GPU delegate is active.
  gpu,

  /// CPU-only inference (fallback).
  ///
  /// This mode is used when hardware acceleration is not available.
  /// Performance will be reduced compared to accelerated modes.
  cpu,

  /// Acceleration mode not yet determined.
  ///
  /// This value is returned before the detector is initialized.
  unknown;

  /// Create an [AccelerationMode] from its string representation.
  ///
  /// Returns [unknown] if the string doesn't match any known mode.
  static AccelerationMode fromString(String value) {
    return AccelerationMode.values.firstWhere(
      (mode) => mode.name == value.toLowerCase(),
      orElse: () => AccelerationMode.unknown,
    );
  }
}
