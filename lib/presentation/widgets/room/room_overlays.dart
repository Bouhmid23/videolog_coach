import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../utils/ui_utils.dart';

/// Bannière flottante de confirmation gestuelle (double-tap micro, swipe participant, mode plein soleil).
class RoomGestureFeedbackBanner extends StatelessWidget {
  const RoomGestureFeedbackBanner({
    super.key,
    required this.message,
    this.icon,
    required this.outdoorSunMode,
  });

  final String message;
  final IconData? icon;
  final bool outdoorSunMode;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 74,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: outdoorSunMode
                ? Colors.black
                : Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: outdoorSunMode ? Colors.white : LKColors.primary,
              width: outdoorSunMode ? 1.5 : 1,
            ),
            boxShadow: UIUtils.shadowMD,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  color: outdoorSunMode
                      ? const Color(0xFFFFB800)
                      : LKColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                message,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight:
                      outdoorSunMode ? FontWeight.w900 : FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// État vide affiché lorsqu'aucun participant principal n'est présent dans la salle.
class RoomEmptyParticipantState extends StatelessWidget {
  const RoomEmptyParticipantState({
    super.key,
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: LKColors.surface,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.videocam_off_rounded,
              size: 64,
              color: LKColors.textSecondary,
            ),
            SizedBox(height: UIUtils.md),
            Text(
              message,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: LKColors.textSecondary),
            ),
            SizedBox(height: UIUtils.sm),
            Text(
              'En attente des participants...',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: LKColors.textHint),
            ),
          ],
        ),
      ),
    );
  }
}
