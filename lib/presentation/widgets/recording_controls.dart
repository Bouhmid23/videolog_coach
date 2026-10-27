import 'package:flutter/material.dart';

import '../../core/recording_controller.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

/// Pastille de statut et actions de contrôle Egress.
class RecordingControls extends StatelessWidget {
  const RecordingControls({required this.controller, super.key});

  final RecordingController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        final isActive = controller.isRecording;
        final isPending = controller.isPending;
        final visible = controller.canControl || isActive || isPending;
        if (!visible) return const SizedBox.shrink();

        final color = isActive
            ? LKColors.danger
            : isPending
                ? LKColors.warning
                : LKColors.textSecondary;
        final label = state?.label ?? 'Enregistrement';

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: EdgeInsets.only(
                left: UIUtils.md,
                right: controller.canControl ? UIUtils.xs : UIUtils.md,
                top: UIUtils.xs,
                bottom: UIUtils.xs,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: UIUtils.borderRadiusAllFull,
                border: Border.all(color: color.withValues(alpha: 0.6)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (controller.loading)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    )
                  else
                    Icon(
                      isActive
                          ? Icons.fiber_manual_record_rounded
                          : Icons.circle,
                      size: isActive ? 12 : 7,
                      color: color,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: UIUtils.bodySmall(context).copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                  if (controller.canControl) ...[
                    const SizedBox(width: 2),
                    if (isPending)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              LKColors.warning,
                            ),
                          ),
                        ),
                      )
                    else if (isActive)
                      IconButton(
                        onPressed: controller.canStop ? controller.stop : null,
                        icon: const Icon(Icons.stop_circle_rounded, size: 20),
                        color: LKColors.danger,
                        tooltip: 'Arrêter l\'enregistrement',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      )
                    else
                      PopupMenuButton<String>(
                        enabled: controller.canStart,
                        tooltip: 'Démarrer l\'enregistrement',
                        onSelected: controller.startWithLayout,
                        color: LKColors.surfaceElevated,
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'grid', child: Text('Grille')),
                          PopupMenuItem(
                            value: 'speaker',
                            child: Text('Intervenant actif'),
                          ),
                          PopupMenuItem(
                            value: 'single-speaker',
                            child: Text('Intervenant unique'),
                          ),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(
                            Icons.fiber_manual_record_rounded,
                            size: 20,
                            color: controller.canStart
                                ? LKColors.danger
                                : LKColors.textHint,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            if (controller.error != null)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: EdgeInsets.symmetric(
                  horizontal: UIUtils.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: LKColors.danger.withValues(alpha: 0.9),
                  borderRadius: UIUtils.borderRadiusAllSM,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    controller.error!,
                    style: UIUtils.bodySmall(context).copyWith(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
