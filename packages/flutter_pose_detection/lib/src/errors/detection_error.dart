/// Error codes for pose detection failures.
///
/// Use these codes for programmatic error handling.
///
/// ## Example
///
/// ```dart
/// try {
///   final result = await detector.detectPose(imageBytes);
/// } on DetectionError catch (e) {
///   switch (e.code) {
///     case DetectionErrorCode.invalidImageFormat:
///       showError('Unsupported image format');
///       break;
///     case DetectionErrorCode.modelLoadFailed:
///       showError('Failed to load ML model');
///       break;
///     default:
///       showError(e.message);
///   }
/// }
/// ```
enum DetectionErrorCode {
  /// Camera permission was not granted.
  ///
  /// Recovery: Request camera permission from the user.
  cameraPermissionDenied,

  /// Storage/file permission was not granted.
  ///
  /// Recovery: Request storage permission from the user.
  storagePermissionDenied,

  /// The image format is not supported.
  ///
  /// Recovery: Use JPEG or PNG format.
  invalidImageFormat,

  /// The video format is not supported.
  ///
  /// Recovery: Use MP4 or MOV format.
  invalidVideoFormat,

  /// The specified file was not found.
  ///
  /// Recovery: Verify the file path is correct.
  fileNotFound,

  /// The ML model failed to load.
  ///
  /// Recovery: Ensure the model file is included in assets.
  modelLoadFailed,

  /// Model inference failed during detection.
  ///
  /// Recovery: Try with a different image or restart the detector.
  inferenceFailed,

  /// Out of memory during processing.
  ///
  /// Recovery: Use a smaller image or close other apps.
  outOfMemory,

  /// The operation was cancelled by the user.
  cancelled,

  /// The current platform is not supported.
  platformNotSupported,

  /// The detector has not been initialized.
  ///
  /// Recovery: Call [NpuPoseDetector.initialize] first.
  notInitialized,

  /// An unknown error occurred.
  unknown;

  /// Get a human-readable description of this error code.
  String get description {
    switch (this) {
      case DetectionErrorCode.cameraPermissionDenied:
        return 'Camera permission denied';
      case DetectionErrorCode.storagePermissionDenied:
        return 'Storage permission denied';
      case DetectionErrorCode.invalidImageFormat:
        return 'Invalid image format';
      case DetectionErrorCode.invalidVideoFormat:
        return 'Invalid video format';
      case DetectionErrorCode.fileNotFound:
        return 'File not found';
      case DetectionErrorCode.modelLoadFailed:
        return 'ML model load failed';
      case DetectionErrorCode.inferenceFailed:
        return 'Inference failed';
      case DetectionErrorCode.outOfMemory:
        return 'Out of memory';
      case DetectionErrorCode.cancelled:
        return 'Operation cancelled';
      case DetectionErrorCode.platformNotSupported:
        return 'Platform not supported';
      case DetectionErrorCode.notInitialized:
        return 'Detector not initialized';
      case DetectionErrorCode.unknown:
        return 'Unknown error';
    }
  }

  /// Get a recovery suggestion for this error.
  String? get recoverySuggestion {
    switch (this) {
      case DetectionErrorCode.cameraPermissionDenied:
        return 'Grant camera permission in device settings';
      case DetectionErrorCode.storagePermissionDenied:
        return 'Grant storage permission in device settings';
      case DetectionErrorCode.invalidImageFormat:
        return 'Use JPEG or PNG image format';
      case DetectionErrorCode.invalidVideoFormat:
        return 'Use MP4 or MOV video format';
      case DetectionErrorCode.fileNotFound:
        return 'Verify the file path is correct';
      case DetectionErrorCode.modelLoadFailed:
        return 'Ensure the ML model is included in app assets';
      case DetectionErrorCode.inferenceFailed:
        return 'Try with a different image or restart the detector';
      case DetectionErrorCode.outOfMemory:
        return 'Use a smaller image or close other applications';
      case DetectionErrorCode.notInitialized:
        return 'Call initialize() before using the detector';
      case DetectionErrorCode.cancelled:
      case DetectionErrorCode.platformNotSupported:
      case DetectionErrorCode.unknown:
        return null;
    }
  }

  /// Create a [DetectionErrorCode] from its string representation.
  static DetectionErrorCode fromString(String value) {
    return DetectionErrorCode.values.firstWhere(
      (code) => code.name == value,
      orElse: () => DetectionErrorCode.unknown,
    );
  }
}

/// Structured error for pose detection failures.
///
/// This exception provides detailed information about detection errors,
/// including error codes for programmatic handling and recovery suggestions.
///
/// ## Example
///
/// ```dart
/// try {
///   final result = await detector.detectPose(imageBytes);
/// } on DetectionError catch (e) {
///   print('Error: ${e.message}');
///   print('Code: ${e.code}');
///
///   if (e.recoverySuggestion != null) {
///     print('Suggestion: ${e.recoverySuggestion}');
///   }
///
///   if (e.platformMessage != null) {
///     print('Platform details: ${e.platformMessage}');
///   }
/// }
/// ```
class DetectionError implements Exception {
  /// The error code for programmatic handling.
  final DetectionErrorCode code;

  /// Human-readable error message.
  final String message;

  /// Platform-specific error details (optional).
  ///
  /// This may contain additional technical details from the native platform.
  final String? platformMessage;

  /// Suggested action to recover from this error (optional).
  final String? recoverySuggestion;

  /// Creates a new [DetectionError].
  const DetectionError({
    required this.code,
    required this.message,
    this.platformMessage,
    this.recoverySuggestion,
  });

  /// Creates a [DetectionError] from an error code with default message.
  factory DetectionError.fromCode(
    DetectionErrorCode code, {
    String? platformMessage,
  }) {
    return DetectionError(
      code: code,
      message: code.description,
      platformMessage: platformMessage,
      recoverySuggestion: code.recoverySuggestion,
    );
  }

  /// Create a [DetectionError] from a JSON map.
  factory DetectionError.fromJson(Map<String, dynamic> json) {
    final code = DetectionErrorCode.fromString(json['code'] as String? ?? '');
    return DetectionError(
      code: code,
      message: json['message'] as String? ?? code.description,
      platformMessage: json['platformMessage'] as String?,
      recoverySuggestion:
          json['recoverySuggestion'] as String? ?? code.recoverySuggestion,
    );
  }

  /// Convert this error to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'code': code.name,
      'message': message,
      if (platformMessage != null) 'platformMessage': platformMessage,
      if (recoverySuggestion != null) 'recoverySuggestion': recoverySuggestion,
    };
  }

  /// Whether this error is potentially recoverable.
  ///
  /// Errors like [DetectionErrorCode.platformNotSupported] are not recoverable.
  bool get isRecoverable => code != DetectionErrorCode.platformNotSupported;

  @override
  String toString() => 'DetectionError($code): $message';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DetectionError &&
        other.code == code &&
        other.message == message &&
        other.platformMessage == platformMessage;
  }

  @override
  int get hashCode => Object.hash(code, message, platformMessage);
}
