import 'package:flutter/material.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

import '../../theme.dart';

/// Structure pour interpoler entre deux poses avec des métadonnées supplémentaires
class InterpolatedPose {
  final Map<LandmarkType, Offset> points;
  final Map<LandmarkType, double> confidence;
  final DateTime timestamp;

  InterpolatedPose({
    required this.points,
    required this.confidence,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory InterpolatedPose.fromPose(
    Pose pose,
    Size frameSize,
    Size displaySize, {
    required bool mirrorX,
    BoxFit fit = BoxFit.contain,
  }) {
    final points = <LandmarkType, Offset>{};
    final confidence = <LandmarkType, double>{};

    // Calculer l'ajustement de la boîte englobante
    // (doit correspondre au fit utilisé par le renderer vidéo : cover = recadrage)
    final fitted = applyBoxFit(fit, frameSize, displaySize);
    final sourceRect = Alignment.center.inscribe(fitted.source, Offset.zero & frameSize);
    final destinationRect = Alignment.center.inscribe(fitted.destination, Offset.zero & displaySize);

    for (final landmark in pose.landmarks) {
      if (landmark.visibility < 0.2) continue;

      confidence[landmark.type] = landmark.visibility;

      // Some detectors return normalized coordinates (0..1), others return pixel coords.
      // Detect and convert normalized coords to pixel space when needed.
      double lx = landmark.x;
      double ly = landmark.y;
      final maybeNormalized = (lx.abs() <= 1.01 && ly.abs() <= 1.01);
      if (maybeNormalized) {
        lx = lx * frameSize.width;
        ly = ly * frameSize.height;
      }

      final x = mirrorX ? frameSize.width - lx : lx;
      final y = ly;

      final srcW = sourceRect.width == 0 ? 1.0 : sourceRect.width;
      final srcH = sourceRect.height == 0 ? 1.0 : sourceRect.height;
      final normalizedX = (x - sourceRect.left) / srcW;
      final normalizedY = (y - sourceRect.top) / srcH;

      points[landmark.type] = Offset(
        destinationRect.left + normalizedX * destinationRect.width,
        destinationRect.top + normalizedY * destinationRect.height,
      );
    }

    return InterpolatedPose(points: points, confidence: confidence);
  }

  /// Interpole entre deux poses avec un facteur (0.0 = première pose, 1.0 = deuxième pose)
  /// Ajoute un easing pour une transition plus naturelle
  static InterpolatedPose lerp(
    InterpolatedPose a,
    InterpolatedPose b,
    double t,
  ) {
    final interpolatedPoints = <LandmarkType, Offset>{};
    final interpolatedConfidence = <LandmarkType, double>{};

    // Fusionner les clés de points existant dans les deux poses
    final allKeys = {...a.points.keys, ...b.points.keys};

    for (final key in allKeys) {
      final pointA = a.points[key];
      final pointB = b.points[key];
      final confA = a.confidence[key] ?? 0.0;
      final confB = b.confidence[key] ?? 0.0;

      if (pointA != null && pointB != null) {
        // Interpoler le point avec easing
        interpolatedPoints[key] = Offset.lerp(pointA, pointB, t)!;
        // Interpoler la confiance
        interpolatedConfidence[key] = (confA * (1 - t)) + (confB * t);
      } else if (pointA != null) {
        interpolatedPoints[key] = pointA;
        interpolatedConfidence[key] = confA * (1 - t);
      } else if (pointB != null) {
        interpolatedPoints[key] = pointB;
        interpolatedConfidence[key] = confB * t;
      }
    }

    return InterpolatedPose(
      points: interpolatedPoints,
      confidence: interpolatedConfidence,
    );
  }

  /// Vérifie si une pose est valide (a suffisamment de points de confiance)
  bool get isValid {
    final confidentPoints = confidence.values.where((c) => c > 0.6).length;
    return confidentPoints >= 10; // Au moins 10 points avec bonne confiance
  }

  /// Calcule le centre de masse de la pose (barycentre)
  Offset get centerOfMass {
    if (points.isEmpty) return Offset.zero;
    
    double sumX = 0, sumY = 0, count = 0;
    for (final entry in points.entries) {
      // Pondérer par la confiance
      final weight = confidence[entry.key] ?? 0.0;
      if (weight > 0.3) {
        sumX += entry.value.dx * weight;
        sumY += entry.value.dy * weight;
        count += weight;
      }
    }
    
    if (count > 0) {
      return Offset(sumX / count, sumY / count);
    }
    return Offset.zero;
  }
}

/// Palette de couleurs basée sur la confiance, alignée avec la charte graphique
class ConfidenceColorPalette {
  /// Retourne la couleur pour un point de repère basé sur sa confiance
  static Color getPointColor(double confidence) {
    if (confidence > 0.8) {
      return LKColors.success; // Très confiant
    } else if (confidence > 0.6) {
      return LKColors.warning; // Confiant
    } else if (confidence > 0.4) {
      return LKColors.danger; // Modéré
    } else {
      return LKColors.textHint; // Faible confiance
    }
  }

  /// Retourne la couleur pour un os du squelette
  static Color getBoneColor(double confidence) {
    if (confidence > 0.8) {
      return LKColors.success;
    } else if (confidence > 0.6) {
      return LKColors.secondary;
    } else if (confidence > 0.4) {
      return LKColors.warning;
    } else {
      return LKColors.border;
    }
  }

  /// Retourne la couleur pour un joint (point d'articulation)
  static Color getJointColor(double confidence) {
    if (confidence > 0.8) {
      return LKColors.success;
    } else if (confidence > 0.6) {
      return LKColors.secondary;
    } else if (confidence > 0.4) {
      return LKColors.warning;
    } else {
      return LKColors.danger;
    }
  }

  /// Retourne un dégradé de couleur pour l'affichage des points
  static LinearGradient getPointGradient(double confidence) {
    return LinearGradient(
      colors: [
        getPointColor(confidence).withValues(alpha: 0.8),
        getPointColor(confidence),
        Colors.white,
      ],
      stops: const [0.0, 0.5, 1.0],
    );
  }

  /// Retourne la taille d'un point basée sur la confiance
  static double getPointSize(double confidence) {
    if (confidence > 0.8) {
      return 12.0;
    } else if (confidence > 0.6) {
      return 10.0;
    } else if (confidence > 0.4) {
      return 8.0;
    } else {
      return 6.0;
    }
  }

  /// Retourne l'épaisseur d'un os basée sur la confiance
  static double getBoneWidth(double confidence) {
    if (confidence > 0.8) {
      return 4.0;
    } else if (confidence > 0.6) {
      return 3.0;
    } else if (confidence > 0.4) {
      return 2.0;
    } else {
      return 1.0;
    }
  }
}

/// Contrôleur d'animation pour les poses avec easing personnalisé
class PoseAnimationController extends ChangeNotifier {
  InterpolatedPose? _currentPose;
  InterpolatedPose? _targetPose;
  late AnimationController _controller;
  late Animation<double> _animation;
  final Duration transitionDuration;

  InterpolatedPose? get currentPose => _currentPose;

  PoseAnimationController({
    required TickerProvider vsync,
    this.transitionDuration = const Duration(milliseconds: 100),
  }) {
    _controller = AnimationController(
      duration: transitionDuration,
      vsync: vsync,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.addListener(_onAnimationUpdate);
  }

  void _onAnimationUpdate() {
    if (_currentPose != null && _targetPose != null) {
      _currentPose = InterpolatedPose.lerp(
        _currentPose!,
        _targetPose!,
        _animation.value,
      );
      notifyListeners();
    }
  }

  /// Met à jour la pose cible avec une animation fluide
  void updatePose(InterpolatedPose newPose) {
    if (_currentPose == null) {
      _currentPose = newPose;
      _targetPose = newPose;
      notifyListeners();
    } else {
      _targetPose = newPose;
      _controller.forward(from: 0.0);
    }
  }

  /// Met à jour immédiatement la pose (sans animation)
  void jumpToPose(InterpolatedPose newPose) {
    _currentPose = newPose;
    _targetPose = newPose;
    _controller.reset();
    notifyListeners();
  }

  /// Réinitialise la pose
  void reset() {
    _currentPose = null;
    _targetPose = null;
    _controller.reset();
    notifyListeners();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// État pour l'animation (nécessaire pour le vsync)
class AnimatedPoseState extends State<StatefulWidget> {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}

/// Structure définissant les connexions du squelette humain avec des métadonnées supplémentaires
class SkeletonBone {
  final LandmarkType from;
  final LandmarkType to;
  final String name;
  final Color color;
  final double widthMultiplier;

  const SkeletonBone({
    required this.from,
    required this.to,
    required this.name,
    this.color = LKColors.primary,
    this.widthMultiplier = 1.0,
  });

  /// Calcule la couleur finale basée sur la confiance moyenne des deux points
  Color getFinalColor(Map<LandmarkType, double> confidence) {
    final confFrom = confidence[from] ?? 0.0;
    final confTo = confidence[to] ?? 0.0;
    final avgConfidence = (confFrom + confTo) / 2.0;
    return color.withValues(alpha: avgConfidence.clamp(0.3, 1.0));
  }

  /// Calcule l'épaisseur finale basée sur la confiance moyenne
  double getFinalWidth(Map<LandmarkType, double> confidence) {
    final confFrom = confidence[from] ?? 0.0;
    final confTo = confidence[to] ?? 0.0;
    final avgConfidence = (confFrom + confTo) / 2.0;
    return ConfidenceColorPalette.getBoneWidth(avgConfidence) * widthMultiplier;
  }
}

/// Ensemble standard de connexions squelettiques humaines avec des couleurs thématiques
class HumanSkeletonBones {
  static const List<SkeletonBone> standardBones = [
    // Colonne vertébrale (bleu primaire)
    SkeletonBone(
      from: LandmarkType.leftShoulder,
      to: LandmarkType.rightShoulder,
      name: 'Shoulders',
      color: LKColors.primary,
      widthMultiplier: 1.2,
    ),
    SkeletonBone(
      from: LandmarkType.leftShoulder,
      to: LandmarkType.leftHip,
      name: 'Left Torso',
      color: LKColors.primary,
      widthMultiplier: 1.2,
    ),
    SkeletonBone(
      from: LandmarkType.rightShoulder,
      to: LandmarkType.rightHip,
      name: 'Right Torso',
      color: LKColors.primary,
      widthMultiplier: 1.2,
    ),
    SkeletonBone(
      from: LandmarkType.leftHip,
      to: LandmarkType.rightHip,
      name: 'Hips',
      color: LKColors.primary,
      widthMultiplier: 1.2,
    ),

    // Bras gauche (cyan secondaire)
    SkeletonBone(
      from: LandmarkType.leftShoulder,
      to: LandmarkType.leftElbow,
      name: 'Left Upper Arm',
      color: LKColors.secondary,
      widthMultiplier: 1.0,
    ),
    SkeletonBone(
      from: LandmarkType.leftElbow,
      to: LandmarkType.leftWrist,
      name: 'Left Forearm',
      color: LKColors.secondary,
      widthMultiplier: 0.8,
    ),

    // Bras droit (cyan secondaire)
    SkeletonBone(
      from: LandmarkType.rightShoulder,
      to: LandmarkType.rightElbow,
      name: 'Right Upper Arm',
      color: LKColors.secondary,
      widthMultiplier: 1.0,
    ),
    SkeletonBone(
      from: LandmarkType.rightElbow,
      to: LandmarkType.rightWrist,
      name: 'Right Forearm',
      color: LKColors.secondary,
      widthMultiplier: 0.8,
    ),

    // Jambe gauche (vert succès)
    SkeletonBone(
      from: LandmarkType.leftHip,
      to: LandmarkType.leftKnee,
      name: 'Left Thigh',
      color: LKColors.success,
      widthMultiplier: 1.2,
    ),
    SkeletonBone(
      from: LandmarkType.leftKnee,
      to: LandmarkType.leftAnkle,
      name: 'Left Calf',
      color: LKColors.success,
      widthMultiplier: 1.0,
    ),

    // Jambe droite (vert succès)
    SkeletonBone(
      from: LandmarkType.rightHip,
      to: LandmarkType.rightKnee,
      name: 'Right Thigh',
      color: LKColors.success,
      widthMultiplier: 1.2,
    ),
    SkeletonBone(
      from: LandmarkType.rightKnee,
      to: LandmarkType.rightAnkle,
      name: 'Right Calf',
      color: LKColors.success,
      widthMultiplier: 1.0,
    ),
  ];

  /// Retne les os avec des couleurs basées sur la confiance
  static List<SkeletonBone> getBonesWithConfidenceColors(InterpolatedPose pose) {
    return standardBones.map((bone) {
      final confFrom = pose.confidence[bone.from] ?? 0.0;
      final confTo = pose.confidence[bone.to] ?? 0.0;
      final avgConfidence = (confFrom + confTo) / 2.0;
      
      return SkeletonBone(
        from: bone.from,
        to: bone.to,
        name: bone.name,
        color: ConfidenceColorPalette.getBoneColor(avgConfidence),
        widthMultiplier: bone.widthMultiplier,
      );
    }).toList();
  }
}

/// Styles de rendu du squelette
class SkeletonRenderStyle {
  final Color jointColor;
  final Color jointOutlineColor;
  final double jointSize;
  final Color boneColor;
  final double boneWidth;
  final bool showLabels;
  final TextStyle labelStyle;

  const SkeletonRenderStyle({
    this.jointColor = LKColors.primary,
    this.jointOutlineColor = Colors.white,
    this.jointSize = 10.0,
    this.boneColor = LKColors.primary,
    this.boneWidth = 3.0,
    this.showLabels = false,
    this.labelStyle = const TextStyle(
      color: Colors.white,
      fontSize: 10,
      fontWeight: FontWeight.bold,
      shadows: [Shadow(color: Colors.black, blurRadius: 2)],
    ),
  });

  /// Style pour les poses avec bonne confiance
  static const SkeletonRenderStyle highConfidence = SkeletonRenderStyle(
    jointColor: LKColors.success,
    jointOutlineColor: Colors.white,
    jointSize: 12.0,
    boneColor: LKColors.success,
    boneWidth: 4.0,
  );

  /// Style pour les poses avec confiance moyenne
  static const SkeletonRenderStyle mediumConfidence = SkeletonRenderStyle(
    jointColor: LKColors.warning,
    jointOutlineColor: Colors.white,
    jointSize: 10.0,
    boneColor: LKColors.warning,
    boneWidth: 3.0,
  );

  /// Style pour les poses avec faible confiance
  static const SkeletonRenderStyle lowConfidence = SkeletonRenderStyle(
    jointColor: LKColors.danger,
    jointOutlineColor: Colors.white,
    jointSize: 8.0,
    boneColor: LKColors.danger,
    boneWidth: 2.0,
  );

  /// Style par défaut avec la charte graphique
  static const SkeletonRenderStyle defaultStyle = SkeletonRenderStyle(
    jointColor: LKColors.primary,
    jointOutlineColor: Colors.white,
    jointSize: 10.0,
    boneColor: LKColors.secondary,
    boneWidth: 3.0,
  );

  /// Crée un style basé sur la confiance moyenne de la pose
  static SkeletonRenderStyle fromConfidence(double confidence) {
    if (confidence > 0.7) {
      return highConfidence;
    } else if (confidence > 0.4) {
      return mediumConfidence;
    } else {
      return lowConfidence;
    }
  }

  /// Applique une opacité basée sur la confiance
  SkeletonRenderStyle withOpacity(double opacity) {
    return SkeletonRenderStyle(
      jointColor: jointColor.withValues(alpha: opacity),
      jointOutlineColor: jointOutlineColor.withValues(alpha: opacity),
      jointSize: jointSize,
      boneColor: boneColor.withValues(alpha: opacity),
      boneWidth: boneWidth,
      showLabels: showLabels,
      labelStyle: labelStyle.copyWith(color: labelStyle.color!.withValues(alpha: opacity)),
    );
  }
}
