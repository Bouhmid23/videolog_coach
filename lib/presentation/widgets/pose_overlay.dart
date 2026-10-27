import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

import '../../theme.dart';
import '../../viewmodels/pose_detection_viewmodel.dart';
import 'pose_animation.dart';

/// Superpose le squelette de la pose locale sur le flux vidéo.
class PoseOverlay extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final current = frame;
    if (current == null) return const SizedBox.shrink();

    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _PoseSkeletonPainter(
            pose: current.pose,
            frameSize: current.frameSize,
            fit: fit,
            mirrorX: mirrorX,
          ),
        ),
      ),
    );
  }
}

/// Squelette « néon » aux couleurs Videolog : dégradé de bleus du logo,
/// cyan du thème, halo lumineux et articulations en anneau.
class _PoseSkeletonPainter extends CustomPainter {
  final Pose pose;
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

    for (final landmark in pose.landmarks) {
      if (landmark.visibility < 0.2) continue;

      final normalized = landmark.x.abs() <= 1.01 && landmark.y.abs() <= 1.01;
      var x = normalized ? landmark.x * frameSize.width : landmark.x;
      final y = normalized ? landmark.y * frameSize.height : landmark.y;
      if (mirrorX) x = frameSize.width - x;

      points[landmark.type] = Offset(
        destinationRect.left +
            (x - sourceRect.left) / sourceRect.width * destinationRect.width,
        destinationRect.top +
            (y - sourceRect.top) / sourceRect.height * destinationRect.height,
      );
      confidence[landmark.type] = landmark.visibility;
    }

    for (final bone in HumanSkeletonBones.standardBones) {
      final from = points[bone.from];
      final to = points[bone.to];
      if (from == null || to == null) continue;

      final average =
          ((confidence[bone.from] ?? 0) + (confidence[bone.to] ?? 0)) / 2;
      _drawBone(canvas, bone, from, to, average);
    }

    for (final entry in points.entries) {
      _drawJoint(canvas, entry.key, entry.value, confidence[entry.key] ?? 0);
    }
  }

  void _drawBone(
    Canvas canvas,
    SkeletonBone bone,
    Offset from,
    Offset to,
    double confidence,
  ) {
    final fromColor = _colorForLandmark(bone.from);
    final toColor = _colorForLandmark(bone.to);
    final strength = confidence.clamp(0.0, 1.0).toDouble();
    final width = (1.4 + strength * 2.5) * bone.widthMultiplier;
    final isWeak = strength < 0.45;

    final haloPaint = Paint()
      ..color = Color.lerp(
        fromColor,
        toColor,
        0.5,
      )!.withValues(alpha: 0.08 + strength * 0.08)
      ..strokeWidth = width * 2.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final gradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        fromColor.withValues(alpha: 0.5 + strength * 0.5),
        toColor.withValues(alpha: 0.5 + strength * 0.5),
      ],
    ).createShader(Rect.fromPoints(from, to));

    final corePaint = Paint()
      ..shader = gradient
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    if (isWeak) {
      _drawDashedLine(canvas, from, to, haloPaint);
      _drawDashedLine(canvas, from, to, corePaint);
      return;
    }

    canvas.drawLine(from, to, haloPaint);
    canvas.drawLine(from, to, corePaint);

    final highlightPaint = Paint()
      ..color = Color.lerp(
        Color.lerp(fromColor, toColor, 0.5)!,
        Colors.white,
        0.7,
      )!.withValues(alpha: 0.18 + strength * 0.2)
      ..strokeWidth = math.max(0.8, width * 0.28)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    canvas.drawLine(from, to, highlightPaint);
  }

  void _drawJoint(
    Canvas canvas,
    LandmarkType type,
    Offset point,
    double confidence,
  ) {
    final strength = confidence.clamp(0.0, 1.0).toDouble();
    final color = _colorForLandmark(type);
    final radius = 1.6 + strength * 3.4;

    final auraPaint = Paint()
      ..color = color.withValues(alpha: 0.06 + strength * 0.08)
      ..isAntiAlias = true;
    canvas.drawCircle(point, radius * 2.5, auraPaint);

    final ringPaint = Paint()
      ..color = color.withValues(alpha: 0.4 + strength * 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1 + strength * 0.5
      ..isAntiAlias = true;
    canvas.drawCircle(point, radius, ringPaint);

    final corePaint = Paint()
      ..color = Color.lerp(
        color,
        Colors.white,
        0.2,
      )!.withValues(alpha: 0.5 + strength * 0.4)
      ..isAntiAlias = true;
    canvas.drawCircle(point, math.max(0.8, radius * 0.5), corePaint);

    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3 + strength * 0.55)
      ..isAntiAlias = true;
    canvas.drawCircle(point, math.max(0.6, radius * 0.18), highlightPaint);
  }

  Color _colorForLandmark(LandmarkType type) {
    final name = type.name;
    if (name.startsWith('left')) return LKColors.logoLight;
    if (name.startsWith('right')) return LKColors.logoBlue;
    return LKColors.secondary;
  }

  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    final delta = to - from;
    final distance = delta.distance;
    if (distance <= 0) return;

    final direction = delta / distance;
    const dashLength = 7.0;
    const gapLength = 5.0;
    var start = 0.0;

    while (start < distance) {
      final end = math.min(start + dashLength, distance);
      canvas.drawLine(from + direction * start, from + direction * end, paint);
      start += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _PoseSkeletonPainter oldDelegate) =>
      pose != oldDelegate.pose ||
      frameSize != oldDelegate.frameSize ||
      fit != oldDelegate.fit ||
      mirrorX != oldDelegate.mirrorX;
}
