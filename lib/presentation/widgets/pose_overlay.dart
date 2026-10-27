import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

import '../../viewmodels/pose_detection_viewmodel.dart';
import 'pose_animation.dart';

/// Squelette local discret, interpolé entre les images de détection.
class PoseOverlay extends StatefulWidget {
  final PoseFrame? frame;
  final BoxFit fit;
  final bool mirrorX;

  const PoseOverlay({
    required this.frame,
    this.fit = BoxFit.cover,
    this.mirrorX = false,
    super.key,
  });

  @override
  State<PoseOverlay> createState() => _PoseOverlayState();
}

class _PoseOverlayState extends State<PoseOverlay>
    with SingleTickerProviderStateMixin {
  late final PoseAnimationController _animation;

  @override
  void initState() {
    super.initState();
    _animation = PoseAnimationController(
      vsync: this,
      transitionDuration: const Duration(milliseconds: 85),
    );
    _updateFrame(widget.frame, initial: true);
  }

  @override
  void didUpdateWidget(covariant PoseOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.frame?.capturedAt != oldWidget.frame?.capturedAt ||
        (widget.frame == null) != (oldWidget.frame == null)) {
      _updateFrame(widget.frame);
    }
  }

  void _updateFrame(PoseFrame? frame, {bool initial = false}) {
    if (frame == null) {
      _animation.reset();
      return;
    }

    final points = <LandmarkType, Offset>{};
    final confidence = <LandmarkType, double>{};
    for (final landmark in frame.pose.landmarks) {
      if (landmark.visibility < 0.12) continue;

      final normalized = landmark.x.abs() <= 1.01 && landmark.y.abs() <= 1.01;
      points[landmark.type] = Offset(
        normalized ? landmark.x * frame.frameSize.width : landmark.x,
        normalized ? landmark.y * frame.frameSize.height : landmark.y,
      );
      confidence[landmark.type] = landmark.visibility
          .clamp(0.0, 1.0)
          .toDouble();
    }

    final pose = InterpolatedPose(points: points, confidence: confidence);
    if (initial || _animation.currentPose == null) {
      _animation.jumpToPose(pose);
    } else {
      _animation.updatePose(pose);
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = widget.frame;
    if (frame == null) return const SizedBox.shrink();

    return IgnorePointer(
      child: SizedBox.expand(
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, _) {
            final pose = _animation.currentPose;
            if (pose == null) return const SizedBox.shrink();
            return CustomPaint(
              painter: _PoseSkeletonPainter(
                pose: pose,
                frameSize: frame.frameSize,
                fit: widget.fit,
                mirrorX: widget.mirrorX,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PoseSkeletonPainter extends CustomPainter {
  final InterpolatedPose pose;
  final Size frameSize;
  final BoxFit fit;
  final bool mirrorX;

  const _PoseSkeletonPainter({
    required this.pose,
    required this.frameSize,
    required this.fit,
    required this.mirrorX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || frameSize.width <= 0 || frameSize.height <= 0) return;

    final fitted = applyBoxFit(fit, frameSize, size);
    final sourceRect = Alignment.center.inscribe(
      fitted.source,
      Offset.zero & frameSize,
    );
    final destinationRect = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    if (sourceRect.width <= 0 || sourceRect.height <= 0) return;

    final points = <LandmarkType, Offset>{};
    final confidence = <LandmarkType, double>{};
    for (final entry in pose.points.entries) {
      final visibility = (pose.confidence[entry.key] ?? 0.0)
          .clamp(0.0, 1.0)
          .toDouble();
      if (visibility < 0.12) continue;

      final x = mirrorX ? frameSize.width - entry.value.dx : entry.value.dx;
      final y = entry.value.dy;
      points[entry.key] = Offset(
        destinationRect.left +
            (x - sourceRect.left) / sourceRect.width * destinationRect.width,
        destinationRect.top +
            (y - sourceRect.top) / sourceRect.height * destinationRect.height,
      );
      confidence[entry.key] = visibility;
    }

    for (final bone in HumanSkeletonBones.standardBones) {
      final from = points[bone.from];
      final to = points[bone.to];
      if (from == null || to == null) continue;

      final strength = math
          .min(confidence[bone.from] ?? 0.0, confidence[bone.to] ?? 0.0)
          .toDouble();
      if (strength < 0.18) continue;

      final fade = ((strength - 0.12) / 0.55).clamp(0.0, 1.0).toDouble();
      final width = (1.15 + fade * 0.45) * bone.widthMultiplier;
      canvas.drawLine(
        from,
        to,
        Paint()
          ..color = const Color(0xFF06131B).withValues(alpha: 0.20 * fade)
          ..strokeWidth = width + 1.1
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
      canvas.drawLine(
        from,
        to,
        Paint()
          ..color = const Color(0xFFE8F8FC).withValues(alpha: 0.50 * fade)
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
    }

    // De minuscules repères aux articulations principales remplacent les
    // anciens anneaux lumineux, qui surchargeaient l'image de la caméra.
    final joints = <LandmarkType>{
      for (final bone in HumanSkeletonBones.standardBones) ...[
        bone.from,
        bone.to,
      ],
    };
    for (final type in joints) {
      final point = points[type];
      final strength = confidence[type] ?? 0.0;
      if (point == null || strength < 0.42) continue;
      canvas.drawCircle(
        point,
        1.35,
        Paint()
          ..color = const Color(0xFFE8F8FC).withValues(alpha: 0.56 * strength)
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PoseSkeletonPainter oldDelegate) =>
      pose != oldDelegate.pose ||
      frameSize != oldDelegate.frameSize ||
      fit != oldDelegate.fit ||
      mirrorX != oldDelegate.mirrorX;
}
