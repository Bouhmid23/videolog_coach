import 'package:flutter/material.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

import 'pose_animation.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

/// Widget qui expose le painter avec animations fluides et style moderne
class SmoothedPoseAvatarWidget extends StatefulWidget {
  final Pose? pose;
  final Size frameSize;
  final bool mirrorX;
  final bool isMiniature;
  final Duration animationDuration;
  final bool enableColorByConfidence;
  final bool enableBoneThickness;
  final SkeletonRenderStyle? renderStyle;
  final bool showSkeletonInfo;
  final Color? backgroundColor;

  const SmoothedPoseAvatarWidget({
    required this.pose,
    required this.frameSize,
    required this.mirrorX,
    this.isMiniature = false,
    this.animationDuration = const Duration(milliseconds: 100),
    this.enableColorByConfidence = true,
    this.enableBoneThickness = true,
    this.renderStyle,
    this.showSkeletonInfo = false,
    this.backgroundColor,
    super.key,
  });

  @override
  State<SmoothedPoseAvatarWidget> createState() => _SmoothedPoseAvatarWidgetState();
}

class _SmoothedPoseAvatarWidgetState extends State<SmoothedPoseAvatarWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  InterpolatedPose? _currentPose;
  InterpolatedPose? _targetPose;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    _animationController.addListener(_onAnimationUpdate);

    if (widget.pose != null) {
      _initializePose(widget.pose!);
    }
  }

  void _initializePose(Pose pose) {
    final interpolated = InterpolatedPose.fromPose(
      pose,
      widget.frameSize,
      Size.infinite,
      mirrorX: widget.mirrorX,
    );

    if (_currentPose == null) {
      _currentPose = interpolated;
    } else {
      _targetPose = interpolated;
      _animationController.forward(from: 0.0);
    }
  }

  void _onAnimationUpdate() {
    if (_currentPose != null && _targetPose != null) {
      setState(() {
        _currentPose = InterpolatedPose.lerp(
          _currentPose!,
          _targetPose!,
          _animationController.value,
        );
      });
    }
  }

  @override
  void didUpdateWidget(covariant SmoothedPoseAvatarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.pose != null && widget.pose != oldWidget.pose) {
      _initializePose(widget.pose!);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final renderStyle = widget.renderStyle ?? SkeletonRenderStyle.defaultStyle;
    
    if (_currentPose == null) {
      return Container(
        color: widget.backgroundColor ?? Colors.transparent,
        child: Center(
          child: SizedBox(
            width: widget.isMiniature ? 20 : 40,
            height: widget.isMiniature ? 20 : 40,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(LKColors.primary),
            ),
          ),
        ),
      );
    }

    return Container(
      color: widget.backgroundColor ?? Colors.transparent,
      child: Stack(
        children: [
          CustomPaint(
            painter: _SmoothedPoseAvatarPainter(
              pose: _currentPose!,
              mirrorX: widget.mirrorX,
              isMiniature: widget.isMiniature,
              enableColorByConfidence: widget.enableColorByConfidence,
              enableBoneThickness: widget.enableBoneThickness,
              renderStyle: renderStyle,
            ),
            child: Container(),
          ),
          if (widget.showSkeletonInfo && !widget.isMiniature)
            Positioned(
              top: UIUtils.sm,
              right: UIUtils.sm,
              child: Container(
                padding: UIUtils.paddingSM,
                decoration: BoxDecoration(
                  color: LKColors.surfaceElevated.withValues(alpha: 0.9),
                  borderRadius: UIUtils.borderRadiusAllMD,
                  border: Border.all(color: LKColors.border, width: 0.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Squelette',
                      style: UIUtils.bodySmall(context).copyWith(
                            color: LKColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      'Points: ${_currentPose!.points.length}',
                      style: UIUtils.bodySmall(context).copyWith(
                            color: LKColors.textHint,
                            fontSize: 10,
                          ),
                    ),
                    Text(
                      'Valid: ${_currentPose!.isValid ? 'Oui' : 'Non'}',
                      style: UIUtils.bodySmall(context).copyWith(
                            color: _currentPose!.isValid ? LKColors.success : LKColors.danger,
                            fontSize: 10,
                          ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Painter pour le widget avec animation fluide et style moderne
class _SmoothedPoseAvatarPainter extends CustomPainter {
  final InterpolatedPose pose;
  final bool mirrorX;
  final bool isMiniature;
  final bool enableColorByConfidence;
  final bool enableBoneThickness;
  final SkeletonRenderStyle renderStyle;

  _SmoothedPoseAvatarPainter({
    required this.pose,
    required this.mirrorX,
    this.isMiniature = false,
    this.enableColorByConfidence = true,
    this.enableBoneThickness = true,
    this.renderStyle = SkeletonRenderStyle.defaultStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final points = pose.points;
    final confidence = pose.confidence;

    if (points.isEmpty) return;

    // Appliquer le style basé sur la confiance moyenne si activé
    final avgConfidence = confidence.values.isEmpty 
        ? 0.0 
        : confidence.values.reduce((a, b) => a + b) / confidence.values.length;
    
    final effectiveStyle = enableColorByConfidence
        ? SkeletonRenderStyle.fromConfidence(avgConfidence)
        : renderStyle;

    // Dessiner les os du squelette en premier (en arrière-plan)
    _drawBones(canvas, points, confidence, effectiveStyle);

    // Dessiner les articulations par-dessus
    _drawJoints(canvas, points, confidence, effectiveStyle);

    // Optionnel : Afficher les indicateurs de confiance
    if (!isMiniature) {
      _drawConfidenceIndicators(canvas, points, confidence, effectiveStyle);
    }

    // Dessiner le centre de masse
    if (!isMiniature) {
      _drawCenterOfMass(canvas, pose, effectiveStyle);
    }
  }

  void _drawBones(
    Canvas canvas,
    Map<LandmarkType, Offset> points,
    Map<LandmarkType, double> confidence,
    SkeletonRenderStyle style,
  ) {
    for (final bone in HumanSkeletonBones.standardBones) {
      if (!points.containsKey(bone.from) || !points.containsKey(bone.to)) return;

      final fromPoint = points[bone.from]!;
      final toPoint = points[bone.to]!;
      final fromConf = confidence[bone.from] ?? 0.0;
      final toConf = confidence[bone.to] ?? 0.0;
      final avgConf = (fromConf + toConf) / 2;

      // Utiliser la couleur du style ou celle basée sur la confiance
      final boneColor = enableColorByConfidence
          ? ConfidenceColorPalette.getBoneColor(avgConf)
          : style.boneColor;

      // Épaisseur basée sur la confiance ou fixe
      final strokeWidth = enableBoneThickness
          ? ConfidenceColorPalette.getBoneWidth(avgConf) * bone.widthMultiplier
          : style.boneWidth * bone.widthMultiplier;

      // Dégradé pour les os
      final gradient = LinearGradient(
        colors: [
          boneColor,
          boneColor.withValues(alpha: 0.5),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      );

      final paint = Paint()
        ..shader = gradient.createShader(Rect.fromPoints(fromPoint, toPoint))
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      // Dessiner l'ombre pour la profondeur
      if (avgConf > 0.7) {
        final shadowPaint = Paint()
          ..color = boneColor.withValues(alpha: 0.3)
          ..strokeWidth = strokeWidth * 1.5
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
        canvas.drawLine(fromPoint, toPoint, shadowPaint);
      }

      // Dessiner le trait principal
      canvas.drawLine(fromPoint, toPoint, paint);
    }
  }

  void _drawJoints(
    Canvas canvas,
    Map<LandmarkType, Offset> points,
    Map<LandmarkType, double> confidence,
    SkeletonRenderStyle style,
  ) {
    for (final entry in points.entries) {
      final point = entry.value;
      final conf = confidence[entry.key] ?? 0.0;

      // Taille de l'articulation basée sur la confiance ou fixe
      final radius = enableColorByConfidence
          ? ConfidenceColorPalette.getPointSize(conf) * (isMiniature ? 0.5 : 1.0)
          : style.jointSize * (isMiniature ? 0.5 : 1.0);

      // Couleur de l'articulation
      final jointColor = enableColorByConfidence
          ? ConfidenceColorPalette.getJointColor(conf)
          : style.jointColor;
      final outlineColor = enableColorByConfidence
          ? jointColor.withValues(alpha: 0.8)
          : style.jointOutlineColor;

      // Créer un dégradé radial pour l'articulation
      final gradient = RadialGradient(
        colors: [
          jointColor,
          jointColor.withValues(alpha: 0.7),
          outlineColor,
        ],
        stops: const [0.0, 0.5, 1.0],
      );

      final paint = Paint()
        ..shader = gradient.createShader(Rect.fromCircle(
          center: point,
          radius: radius * 1.5,
        ))
        ..style = PaintingStyle.fill;

      // Dessiner l'articulation principale
      canvas.drawCircle(point, radius, paint);

      // Halo de profondeur pour les articulations confiantes
      if (conf > 0.6) {
        final haloPaint = Paint()
          ..color = jointColor.withValues(alpha: 0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * 0.5;
        canvas.drawCircle(point, radius * 1.5, haloPaint);
      }

      // Effet de lueur supplémentaire pour les articulations très confiantes
      if (conf > 0.8) {
        final glowPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * 0.3
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
        canvas.drawCircle(point, radius * 1.8, glowPaint);
      }
    }
  }

  void _drawConfidenceIndicators(
    Canvas canvas,
    Map<LandmarkType, Offset> points,
    Map<LandmarkType, double> confidence,
    SkeletonRenderStyle style,
  ) {
    for (final bone in HumanSkeletonBones.standardBones) {
      if (!points.containsKey(bone.from) || !points.containsKey(bone.to)) continue;

      final fromConf = confidence[bone.from] ?? 0.0;
      final toConf = confidence[bone.to] ?? 0.0;
      final avgConf = (fromConf + toConf) / 2;

      // Pour les basses confiances, utiliser un style pointillé
      if (avgConf < 0.5) {
        _drawDashedLine(
          canvas,
          points[bone.from]!,
          points[bone.to]!,
          Paint()
            ..color = LKColors.warning.withValues(alpha: 0.5)
            ..strokeWidth = isMiniature ? 1 : 2
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  void _drawCenterOfMass(
    Canvas canvas,
    InterpolatedPose pose,
    SkeletonRenderStyle style,
  ) {
    final center = pose.centerOfMass;
    if (center == Offset.zero) return;

    // Dessiner le point central
    canvas.drawCircle(
      center,
      isMiniature ? 3 : 6,
      Paint()
        ..color = LKColors.secondary
        ..style = PaintingStyle.fill,
    );

    // Dessiner le halo
    canvas.drawCircle(
      center,
      isMiniature ? 8 : 16,
      Paint()
        ..color = LKColors.secondary.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Dessiner une ligne vers le bas (indicateur de gravité)
    canvas.drawLine(
      center,
      Offset(center.dx, center.dy + (isMiniature ? 20 : 40)),
      Paint()
        ..color = LKColors.secondary.withValues(alpha: 0.5)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashWidth = 5.0;
    const dashSpace = 3.0;
    final distance = (p2 - p1).distance;
    final steps = (distance / (dashWidth + dashSpace)).ceil();

    for (int i = 0; i < steps; i++) {
      final t1 = (i * (dashWidth + dashSpace)) / distance;
      final t2 = (i * (dashWidth + dashSpace) + dashWidth) / distance;

      if (t2 <= 1.0) {
        canvas.drawLine(
          Offset.lerp(p1, p2, t1)!,
          Offset.lerp(p1, p2, t2.clamp(0, 1))!,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SmoothedPoseAvatarPainter oldDelegate) {
    return pose != oldDelegate.pose ||
        mirrorX != oldDelegate.mirrorX ||
        isMiniature != oldDelegate.isMiniature ||
        enableColorByConfidence != oldDelegate.enableColorByConfidence ||
        enableBoneThickness != oldDelegate.enableBoneThickness ||
        renderStyle != oldDelegate.renderStyle;
  }
}
