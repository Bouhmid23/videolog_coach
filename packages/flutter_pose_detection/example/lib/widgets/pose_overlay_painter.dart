import 'package:flutter/material.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

/// Custom painter for drawing pose skeleton overlay on images.
class PoseOverlayPainter extends CustomPainter {
  final Pose pose;
  final int? imageWidth;
  final int? imageHeight;
  final double minVisibility;
  final Color lineColor;
  final Color pointColor;
  final bool mirror;

  PoseOverlayPainter({
    required this.pose,
    this.imageWidth,
    this.imageHeight,
    this.minVisibility = 0.3,
    this.lineColor = Colors.green,
    this.pointColor = Colors.red,
    this.mirror = false,
  });

  /// Skeleton connections for drawing lines between landmarks.
  static const List<List<LandmarkType>> connections = [
    // Face
    [LandmarkType.leftEar, LandmarkType.leftEye],
    [LandmarkType.leftEye, LandmarkType.nose],
    [LandmarkType.nose, LandmarkType.rightEye],
    [LandmarkType.rightEye, LandmarkType.rightEar],

    // Torso
    [LandmarkType.leftShoulder, LandmarkType.rightShoulder],
    [LandmarkType.leftShoulder, LandmarkType.leftHip],
    [LandmarkType.rightShoulder, LandmarkType.rightHip],
    [LandmarkType.leftHip, LandmarkType.rightHip],

    // Left arm
    [LandmarkType.leftShoulder, LandmarkType.leftElbow],
    [LandmarkType.leftElbow, LandmarkType.leftWrist],

    // Right arm
    [LandmarkType.rightShoulder, LandmarkType.rightElbow],
    [LandmarkType.rightElbow, LandmarkType.rightWrist],

    // Left leg
    [LandmarkType.leftHip, LandmarkType.leftKnee],
    [LandmarkType.leftKnee, LandmarkType.leftAnkle],
    [LandmarkType.leftAnkle, LandmarkType.leftHeel],

    // Right leg
    [LandmarkType.rightHip, LandmarkType.rightKnee],
    [LandmarkType.rightKnee, LandmarkType.rightAnkle],
    [LandmarkType.rightAnkle, LandmarkType.rightHeel],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = pointColor
      ..style = PaintingStyle.fill;

    // For camera mode (normalized coordinates), use size directly
    // For image mode, scale from image dimensions to display size
    final effectiveWidth = imageWidth?.toDouble() ?? 1.0;
    final effectiveHeight = imageHeight?.toDouble() ?? 1.0;

    // Calculate scale factors
    final scaleX = size.width / effectiveWidth;
    final scaleY = size.height / effectiveHeight;

    Offset scaleAndMirror(double x, double y) {
      final scaledX = x * effectiveWidth * scaleX;
      final scaledY = y * effectiveHeight * scaleY;

      if (mirror) {
        return Offset(size.width - scaledX, scaledY);
      }
      return Offset(scaledX, scaledY);
    }

    // Draw skeleton connections
    for (final connection in connections) {
      final p1 = pose.getLandmark(connection[0]);
      final p2 = pose.getLandmark(connection[1]);

      if (p1.visibility >= minVisibility && p2.visibility >= minVisibility) {
        final offset1 = scaleAndMirror(p1.x, p1.y);
        final offset2 = scaleAndMirror(p2.x, p2.y);

        canvas.drawLine(offset1, offset2, linePaint);
      }
    }

    // Draw landmark points
    for (final landmark in pose.landmarks) {
      if (landmark.visibility >= minVisibility) {
        final offset = scaleAndMirror(landmark.x, landmark.y);

        // Draw outer circle
        canvas.drawCircle(offset, 6, pointPaint);

        // Draw inner circle (for visibility feedback)
        final innerPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        canvas.drawCircle(offset, 3, innerPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PoseOverlayPainter oldDelegate) {
    return oldDelegate.pose != pose ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight ||
        oldDelegate.mirror != mirror;
  }
}
