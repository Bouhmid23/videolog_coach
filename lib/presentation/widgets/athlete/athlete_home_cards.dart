import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/account_models.dart';
import '../../../data/training_models.dart';
import '../../../theme.dart';
import '../../utils/ui_utils.dart';

/// Carte d'accès rapide au check-in « Forme du jour (10 s) » sur [AthleteHomeScreen].
class AthleteWellnessQuickCard extends StatelessWidget {
  const AthleteWellnessQuickCard({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: UIUtils.borderRadiusAllLG,
      child: Container(
        padding: UIUtils.paddingMD,
        decoration: BoxDecoration(
          color: LKColors.primary.withValues(alpha: 0.1),
          borderRadius: UIUtils.borderRadiusAllLG,
          border: Border.all(color: LKColors.primary.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: LKColors.primary.withValues(alpha: 0.16),
                borderRadius: UIUtils.borderRadiusAllMD,
              ),
              child: const Icon(
                Icons.favorite_rounded,
                color: LKColors.primary,
                size: 20,
              ),
            ),
            SizedBox(width: UIUtils.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Forme du jour (10 s)',
                    style: UIUtils.titleSmall(context),
                  ),
                  Text(
                    'Sommeil, fatigue, courbatures, stress & humeur',
                    style: UIUtils.bodySmall(context).copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: LKColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte du profil sportif et du statut de consentement RGPD santé sur [AthleteHomeScreen].
class AthleteProfileConsentCard extends StatelessWidget {
  const AthleteProfileConsentCard({
    super.key,
    required this.profile,
    required this.hasHealthConsent,
    required this.onTap,
  });

  final ServerAthleteProfile? profile;
  final bool hasHealthConsent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final consentColor = hasHealthConsent ? LKColors.success : LKColors.warning;
    final basicParts = <String>[
      if (profile != null) profile!.sport,
      if (profile != null) profile!.level,
      if (hasHealthConsent && profile?.hrMax != null)
        'FC max ${profile!.hrMax} bpm',
      if (hasHealthConsent && profile?.hrRest != null)
        'FC repos ${profile!.hrRest} bpm',
      if (hasHealthConsent && profile?.weightKg != null)
        '${profile!.weightKg!.toStringAsFixed(1)} kg',
    ];

    return InkWell(
      onTap: onTap,
      borderRadius: UIUtils.borderRadiusAllMD,
      child: Container(
        padding: UIUtils.paddingMD,
        decoration: BoxDecoration(
          color: LKColors.surfaceElevated,
          borderRadius: UIUtils.borderRadiusAllMD,
          border: Border.all(color: LKColors.border, width: 0.6),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: consentColor.withValues(alpha: 0.14),
                borderRadius: UIUtils.borderRadiusAllSM,
              ),
              child: Icon(
                hasHealthConsent
                    ? Icons.verified_user_rounded
                    : Icons.privacy_tip_outlined,
                color: consentColor,
                size: 20,
              ),
            ),
            SizedBox(width: UIUtils.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Profil sportif & RGPD',
                        style: UIUtils.titleSmall(context),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: consentColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          hasHealthConsent
                              ? 'Consentement santé actif'
                              : 'Consentement requis',
                          style: TextStyle(
                            color: consentColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    basicParts.isNotEmpty
                        ? basicParts.join(' · ')
                        : 'Renseigner votre sport, niveau et consentement santé',
                    style: UIUtils.bodySmall(context),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: LKColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte d'une séance planifiée du jour sur [AthleteHomeScreen].
class AthleteTodayWorkoutCard extends StatelessWidget {
  const AthleteTodayWorkoutCard({
    super.key,
    required this.workout,
    required this.onTap,
  });

  final PlannedWorkout workout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: UIUtils.borderRadiusAllMD,
      child: Container(
        padding: UIUtils.paddingMD,
        decoration: BoxDecoration(
          color: LKColors.surfaceElevated,
          borderRadius: UIUtils.borderRadiusAllMD,
          border: Border.all(color: LKColors.border, width: 0.6),
        ),
        child: Row(
          children: [
            const Icon(Icons.fitness_center_rounded, color: LKColors.primary),
            SizedBox(width: UIUtils.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    workout.title,
                    style: UIUtils.bodyMedium(context).copyWith(
                      fontWeight: FontWeight.w600,
                      color: LKColors.textPrimary,
                    ),
                  ),
                  Text(
                    [
                      if (workout.startTime != null &&
                          workout.startTime!.trim().isNotEmpty)
                        workout.startTime!.trim(),
                      workout.sport,
                      if (workout.estimatedDurationS != null)
                        formatDurationSeconds(workout.estimatedDurationS),
                      if (workout.estimatedTss != null)
                        '${workout.estimatedTss!.round()} pts d\'effort',
                    ].join(' · '),
                    style: UIUtils.bodySmall(context),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: LKColors.textHint),
          ],
        ),
      ),
    );
  }
}

/// Carte d'un objectif sportif à venir sur [AthleteHomeScreen].
class AthleteGoalCard extends StatelessWidget {
  const AthleteGoalCard({
    super.key,
    required this.goal,
    required this.today,
  });

  final CalendarGoal goal;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final priorityColor = switch (goal.priority) {
      'A' => LKColors.danger,
      'B' => LKColors.warning,
      _ => LKColors.primary,
    };
    final date = goal.date;
    String? countdown;
    if (date != null) {
      final todayMidnight = DateTime(today.year, today.month, today.day);
      final targetMidnight = DateTime(date.year, date.month, date.day);
      final diffDays = targetMidnight.difference(todayMidnight).inDays;
      countdown = diffDays >= 0 ? 'J-$diffDays' : 'J+${diffDays.abs()}';
    }

    return Container(
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: LKColors.surfaceElevated,
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(color: LKColors.border, width: 0.6),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: priorityColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: priorityColor.withValues(alpha: 0.45)),
            ),
            child: Text(
              goal.priority,
              style: TextStyle(
                color: priorityColor,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          SizedBox(width: UIUtils.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goal.title,
                  style: UIUtils.bodyMedium(context).copyWith(
                    color: LKColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  [
                    if (date != null) DateFormat('dd/MM/yyyy').format(date),
                    if (goal.sport != null && goal.sport!.isNotEmpty)
                      goal.sport!,
                  ].join(' · '),
                  style: UIUtils.bodySmall(context),
                ),
              ],
            ),
          ),
          if (countdown != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: LKColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                countdown,
                style: TextStyle(
                  color: priorityColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Carte listant les coachs de l'organisation active sur [AthleteHomeScreen].
class AthleteOrgCoachesCard extends StatelessWidget {
  const AthleteOrgCoachesCard({
    super.key,
    required this.coaches,
    required this.onTapCoach,
  });

  final List<OrgCoachSummary> coaches;
  final void Function(OrgCoachSummary coach) onTapCoach;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: LKColors.surfaceElevated,
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(color: LKColors.border, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.sports_rounded,
                color: LKColors.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                coaches.length > 1 ? 'Vos coachs' : 'Votre coach',
                style: UIUtils.titleSmall(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: coaches.map((coach) {
              return ActionChip(
                avatar: const Icon(
                  Icons.person_outline_rounded,
                  size: 16,
                  color: LKColors.primary,
                ),
                label: Text(
                  coach.name,
                  style: UIUtils.bodySmall(context).copyWith(
                    color: LKColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                backgroundColor: LKColors.surface,
                side: const BorderSide(color: LKColors.border, width: 0.6),
                onPressed: () => onTapCoach(coach),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
