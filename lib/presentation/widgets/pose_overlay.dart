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
  final Map<LandmarkType, Offset> _pointsCache = {};
  final Map<LandmarkType, double> _confidenceCache = {};

  @override
  void initState() {
    super.initState();
    _animation = PoseAnimationController(
      vsync: this,
      transitionDuration: const Duration(milliseconds: 85),
      enableButterworthFilter: true,
      cutoffFrequency: 5.0,
      samplingRate: 30.0,
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
    _pointsCache.clear();
    _confidenceCache.clear();
    for (final landmark in frame.pose.landmarks) {
      if (landmark.visibility < 0.12) continue;

      _pointsCache[landmark.type] = Offset(
        pixels ? landmark.x : landmark.x * frame.frameSize.width,
        pixels ? landmark.y : landmark.y * frame.frameSize.height,
      );
      _confidenceCache[landmark.type] = landmark.visibility
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

    final pose = InterpolatedPose(
      points: Map<LandmarkType, Offset>.of(_pointsCache),
      confidence: Map<LandmarkType, double>.of(_confidenceCache),
    );
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
            return RepaintBoundary(
              child: CustomPaint(
                painter: _PoseSkeletonPainter(
                  pose: pose,
                  frameSize: frame.frameSize,
                  fit: widget.fit,
                  mirrorX: widget.mirrorX,
                ),
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

  /// Table de couleur précalculée par `LandmarkType.index` (évite `name.startsWith` à 60 Hz).
  static final List<Color> _landmarkColors = List<Color>.generate(
    LandmarkType.values.length,
    (index) {
      final name = LandmarkType.values[index].name;
      if (name.startsWith('left')) return LKColors.logoLight;
      if (name.startsWith('right')) return LKColors.logoBlue;
      return LKColors.primary;
    },
    growable: false,
  );

  // Objets Paint et structures réutilisés à chaque frame (zéro allocation GC dans la boucle).
  static final List<Offset?> _pointsByIndex =
      List<Offset?>.filled(LandmarkType.values.length, null);
  static final List<double> _confidenceByIndex =
      List<double>.filled(LandmarkType.values.length, 0.0);

  static final Paint _boneGlowPaint = Paint()
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  static final Paint _boneOutlinePaint = Paint()
    ..color = const Color(0xB807111F)
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  static final Paint _boneMainPaint = Paint()
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  static final Paint _boneCorePaint = Paint()
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  static final Paint _jointHaloPaint = Paint()..isAntiAlias = true;
  static final Paint _jointBackPaint = Paint()
    ..color = const Color(0xD107111F)
    ..isAntiAlias = true;
  static final Paint _jointRingPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..isAntiAlias = true;
  static final Paint _jointCenterPaint = Paint()..isAntiAlias = true;

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

    final scaleX = destinationRect.width / sourceRect.width;
    final scaleY = destinationRect.height / sourceRect.height;

    // Réutilisation des tableaux indexés statiques (évite les allocations de Map à 60 fps).
    _pointsByIndex.fillRange(0, _pointsByIndex.length, null);
    _confidenceByIndex.fillRange(0, _confidenceByIndex.length, 0.0);

    for (final entry in pose.points.entries) {
      final visibility = (pose.confidence[entry.key] ?? 0.0)
          .clamp(0.0, 1.0)
          .toDouble();
      if (visibility < 0.12) continue;

      final idx = entry.key.index;
      final x = mirrorX ? frameSize.width - entry.value.dx : entry.value.dx;
      final y = entry.value.dy;
      _pointsByIndex[idx] = Offset(
        destinationRect.left + (x - sourceRect.left) * scaleX,
        destinationRect.top + (y - sourceRect.top) * scaleY,
      );
      _confidenceByIndex[idx] = visibility;
    }

    for (final bone in _allBones) {
      final from = _pointsByIndex[bone.from.index];
      final to = _pointsByIndex[bone.to.index];
      if (from == null || to == null) continue;

      final strength = math
          .min(
            _confidenceByIndex[bone.from.index],
            _confidenceByIndex[bone.to.index],
          )
          .toDouble();
      if (strength < 0.18) continue;

      final visibility = (0.68 + strength * 0.32).clamp(0.0, 1.0).toDouble();
      final width = (2.25 + strength * 0.5) * bone.widthMultiplier;
      final colorFrom = _landmarkColors[bone.from.index];
      final colorTo = _landmarkColors[bone.to.index];
      final midColor = Color.lerp(colorFrom, colorTo, 0.5)!;

      _boneGlowPaint
        ..color = midColor.withValues(alpha: 0.22 * visibility)
        ..strokeWidth = width + 4.2;
      canvas.drawLine(from, to, _boneGlowPaint);

      _boneOutlinePaint.strokeWidth = width + 1.8;
      canvas.drawLine(from, to, _boneOutlinePaint);

      _boneMainPaint
        ..shader = colorFrom == colorTo
            ? null
            : ui.Gradient.linear(from, to, [colorFrom, colorTo])
        ..color = colorFrom.withValues(alpha: visibility)
        ..strokeWidth = width;
      canvas.drawLine(from, to, _boneMainPaint);

      _boneCorePaint
        ..color = Colors.white.withValues(alpha: 0.42 * visibility)
        ..strokeWidth = math.max(0.7, width * 0.22);
      canvas.drawLine(from, to, _boneCorePaint);
    }

    // Un repère par point visible : les 33 (corps, visage, mains, pieds). Les points de
    // détail sont dessinés plus petits que les articulations principales.
    for (var i = 0; i < LandmarkType.values.length; i++) {
      final point = _pointsByIndex[i];
      if (point == null) continue;
      final strength = _confidenceByIndex[i];
      if (strength < 0.28) continue;
      final type = LandmarkType.values[i];
      final color = _landmarkColors[i];
      final scale = _mainJoints.contains(type) ? 1.0 : 0.6;
      final visibility = (0.72 + strength * 0.28).clamp(0.0, 1.0).toDouble();

      _jointHaloPaint.color = color.withValues(alpha: 0.26 * visibility);
      canvas.drawCircle(point, 6.2 * scale, _jointHaloPaint);

      canvas.drawCircle(point, 4.0 * scale, _jointBackPaint);

      _jointRingPaint.color = color.withValues(alpha: 0.96 * visibility);
      canvas.drawCircle(point, 3.25 * scale, _jointRingPaint);

      _jointCenterPaint.color = Colors.white.withValues(alpha: 0.94 * visibility);
      canvas.drawCircle(point, 1.35 * scale, _jointCenterPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PoseSkeletonPainter oldDelegate) =>
      pose != oldDelegate.pose ||
      frameSize != oldDelegate.frameSize ||
      fit != oldDelegate.fit ||
      mirrorX != oldDelegate.mirrorX;
}
