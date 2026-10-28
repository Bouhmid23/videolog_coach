import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

import '../../data/posture_codec.dart';
import '../../theme.dart';
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
  DateTime? _lastCapturedAt;

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
      _lastCapturedAt = null;
      _animation.reset();
      return;
    }

    // Décidé une fois par pose : un point légèrement hors du cadre (x ou y hors de [0, 1])
    // reste normalisé. Sinon il serait pris pour des pixels et tomberait dans le coin (0, 0).
    final pixels = PostureCodec.isPixelSpace(frame.pose.landmarks);
    final points = <LandmarkType, Offset>{};
    final confidence = <LandmarkType, double>{};
    for (final landmark in frame.pose.landmarks) {
      if (landmark.visibility < 0.12) continue;

      points[landmark.type] = Offset(
        pixels ? landmark.x : landmark.x * frame.frameSize.width,
        pixels ? landmark.y : landmark.y * frame.frameSize.height,
      );
      confidence[landmark.type] = landmark.visibility
          .clamp(0.0, 1.0)
          .toDouble();
    }

    // Durée de la transition = intervalle réel entre deux poses : le squelette atteint sa
    // cible quand la pose suivante arrive (à 19 poses/s, 85 ms fixes le faisaient traîner).
    final last = _lastCapturedAt;
    _lastCapturedAt = frame.capturedAt;
    final interval = last == null
        ? const Duration(milliseconds: 85)
        : frame.capturedAt.difference(last);
    final duration = Duration(
      milliseconds: interval.inMilliseconds.clamp(30, 120).toInt(),
    );

    final pose = InterpolatedPose(points: points, confidence: confidence);
    if (initial || _animation.currentPose == null) {
      _animation.jumpToPose(pose);
    } else {
      _animation.updatePose(pose, duration: duration);
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

  static const List<SkeletonBone> _allBones = [
    ...HumanSkeletonBones.standardBones,
    ...HumanSkeletonBones.detailBones,
  ];
  static final Set<LandmarkType> _mainJoints = {
    for (final bone in HumanSkeletonBones.standardBones) ...[bone.from, bone.to],
  };

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

    for (final bone in _allBones) {
      final from = points[bone.from];
      final to = points[bone.to];
      if (from == null || to == null) continue;

      final strength = math
          .min(confidence[bone.from] ?? 0.0, confidence[bone.to] ?? 0.0)
          .toDouble();
      if (strength < 0.18) continue;

      final visibility = (0.68 + strength * 0.32).clamp(0.0, 1.0).toDouble();
      final width = (2.25 + strength * 0.5) * bone.widthMultiplier;
      final colorFrom = _colorForLandmark(bone.from);
      final colorTo = _colorForLandmark(bone.to);
      final colorShader = ui.Gradient.linear(from, to, [colorFrom, colorTo]);
      canvas.drawLine(
        from,
        to,
        Paint()
          ..color = Color.lerp(
            colorFrom,
            colorTo,
            0.5,
          )!.withValues(alpha: 0.28 * visibility)
          ..strokeWidth = width + 3.8
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0)
          ..isAntiAlias = true,
      );
      canvas.drawLine(
        from,
        to,
        Paint()
          ..color = const Color(0xFF07111F).withValues(alpha: 0.72)
          ..strokeWidth = width + 1.8
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
      canvas.drawLine(
        from,
        to,
        Paint()
          ..shader = colorShader
          ..color = Colors.white.withValues(alpha: visibility)
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
      canvas.drawLine(
        from,
        to,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.42 * visibility)
          ..strokeWidth = math.max(0.7, width * 0.22)
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
    }

    // Un repère par point visible : les 33 (corps, visage, mains, pieds). Les points de
    // détail sont dessinés plus petits que les articulations principales.
    final joints = points.keys.toList();
    for (final type in joints) {
      final point = points[type];
      final strength = confidence[type] ?? 0.0;
      if (point == null || strength < 0.28) continue;
      final color = _colorForLandmark(type);
      final scale = _mainJoints.contains(type) ? 1.0 : 0.6;
      final visibility = (0.72 + strength * 0.28).clamp(0.0, 1.0).toDouble();
      canvas.drawCircle(
        point,
        6.0 * scale,
        Paint()
          ..color = color.withValues(alpha: 0.38 * visibility)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
          ..isAntiAlias = true,
      );
      canvas.drawCircle(
        point,
        4.0 * scale,
        Paint()
          ..color = const Color(0xFF07111F).withValues(alpha: 0.82)
          ..isAntiAlias = true,
      );
      canvas.drawCircle(
        point,
        3.25 * scale,
        Paint()
          ..color = color.withValues(alpha: 0.96 * visibility)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..isAntiAlias = true,
      );
      canvas.drawCircle(
        point,
        1.35 * scale,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.94 * visibility)
          ..isAntiAlias = true,
      );
    }
  }

  Color _colorForLandmark(LandmarkType type) {
    final name = type.name;
    if (name.startsWith('left')) return LKColors.logoLight;
    if (name.startsWith('right')) return LKColors.logoBlue;
    return LKColors.primary;
  }

  @override
  bool shouldRepaint(covariant _PoseSkeletonPainter oldDelegate) =>
      pose != oldDelegate.pose ||
      frameSize != oldDelegate.frameSize ||
      fit != oldDelegate.fit ||
      mirrorX != oldDelegate.mirrorX;
}
