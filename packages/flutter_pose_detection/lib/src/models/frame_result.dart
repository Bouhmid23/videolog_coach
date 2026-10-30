import 'pose_result.dart';

/// Result for realtime camera frame processing.
///
/// Contains the detection result along with frame metadata useful for
/// tracking performance and synchronization in realtime applications.
class FrameResult {
  /// Detection result for this frame
  final PoseResult result;

  /// Frame sequence number (monotonically increasing)
  final int frameNumber;

  /// Frame timestamp from camera in microseconds
  final int timestampUs;

  /// Current frames per second (rolling average)
  final double fps;

  /// Whether device is thermally throttled (MODERATE/SEVERE thermal state)
  final bool isThermalThrottled;

  /// Whether battery level is below low threshold (< 20% and not charging)
  final bool isLowBattery;

  /// Battery level as percentage [0.0 - 1.0]
  final double? batteryLevel;

  /// Current effective target FPS enforced by dynamic throttling
  final int? targetFps;

  const FrameResult({
    required this.result,
    required this.frameNumber,
    required this.timestampUs,
    required this.fps,
    this.isThermalThrottled = false,
    this.isLowBattery = false,
    this.batteryLevel,
    this.targetFps,
  });

  /// Create from JSON map (platform channel)
  factory FrameResult.fromJson(Map<String, dynamic> json) {
    return FrameResult(
      result: PoseResult.fromJson(json['result'] as Map<String, dynamic>),
      frameNumber: json['frameNumber'] as int,
      timestampUs: json['timestampUs'] as int,
      fps: (json['fps'] as num).toDouble(),
      isThermalThrottled: json['isThermalThrottled'] as bool? ?? false,
      isLowBattery: json['isLowBattery'] as bool? ?? false,
      batteryLevel: (json['batteryLevel'] as num?)?.toDouble(),
      targetFps: json['targetFps'] as int?,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() => {
        'result': result.toJson(),
        'frameNumber': frameNumber,
        'timestampUs': timestampUs,
        'fps': fps,
        'isThermalThrottled': isThermalThrottled,
        'isLowBattery': isLowBattery,
        if (batteryLevel != null) 'batteryLevel': batteryLevel,
        if (targetFps != null) 'targetFps': targetFps,
      };

  @override
  String toString() =>
      'FrameResult(frame: $frameNumber, fps: ${fps.toStringAsFixed(1)}, poses: ${result.poses.length})';
}
