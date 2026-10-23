import 'package:flutter/material.dart';

import '../../theme.dart';
import '../utils/ui_utils.dart';
import '../models/map_tile_source.dart';

/// Bouton flottant pour changer la source de tuiles de la carte.
///
/// Design moderne avec :
/// - Icône clairement visible
/// - Animation au survol
/// - Tooltip informatif
/// - Style cohérent avec la charte graphique
class TileSourceToggle extends StatelessWidget {
  final MapTileSource current;
  final VoidCallback onToggle;

  const TileSourceToggle({
    super.key,
    required this.current,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: UIUtils.lg,
      right: UIUtils.md,
      child: AnimatedContainer(
        duration: UIUtils.animationDuration,
        curve: UIUtils.animationCurve,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              LKColors.surfaceElevated,
              LKColors.primary.withValues(alpha: 0.3),
            ],
          ),
          borderRadius: BorderRadius.circular(UIUtils.borderRadiusFull),
          border: Border.all(
            color: LKColors.border.withValues(alpha: 0.5),
            width: 1,
          ),
          boxShadow: UIUtils.shadowLG,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onToggle,
            hoverColor: LKColors.primary.withValues(alpha: 0.1),
            splashColor: LKColors.primary.withValues(alpha: 0.3),
            highlightColor: LKColors.primary.withValues(alpha: 0.2),
            child: AnimatedPadding(
              duration: UIUtils.animationDuration,
              padding: EdgeInsets.all(UIUtils.md),
              child: Tooltip(
                message: current.nextTooltip,
                decoration: BoxDecoration(
                  color: LKColors.surfaceElevated,
                  borderRadius: UIUtils.borderRadiusAllSM,
                  border: Border.all(color: LKColors.border, width: 0.5),
                ),
                textStyle: const TextStyle(
                  color: LKColors.textPrimary,
                  fontSize: 11,
                ),
                preferBelow: false,
                margin: EdgeInsets.all(UIUtils.sm),
                child:
                    Icon(
                      current.nextIcon,
                      size: 20,
                      color: LKColors.primary,
                      shadows: [
                        Shadow(
                          color: LKColors.primary.withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
