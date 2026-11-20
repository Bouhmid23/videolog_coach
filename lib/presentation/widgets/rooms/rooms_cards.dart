import 'package:flutter/material.dart';

import '../../../data/athlete_profile.dart';
import '../../../data/mobile_room.dart';
import '../../../data/session_models.dart';
import '../../../theme.dart';
import '../../utils/ui_utils.dart';

/// En-tête de bienvenue et statistiques des sessions en direct sur [RoomsScreen].
class RoomsHeaderCard extends StatelessWidget {
  const RoomsHeaderCard({
    super.key,
    required this.displayName,
    required this.athleteProfile,
    required this.roomsCount,
    required this.liveCount,
    required this.recordingCount,
    required this.onEditAthleteProfile,
  });

  final String displayName;
  final AthleteProfile athleteProfile;
  final int roomsCount;
  final int liveCount;
  final int recordingCount;
  final VoidCallback onEditAthleteProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: UIUtils.paddingXL,
      decoration: BoxDecoration(
        borderRadius: UIUtils.borderRadiusAllXL,
        border: Border.all(
          color: LKColors.primary.withValues(alpha: 0.25),
          width: 0.5,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            LKColors.primary.withValues(alpha: 0.16),
            LKColors.secondary.withValues(alpha: 0.06),
            LKColors.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BON RETOUR',
                      style: UIUtils.bodySmall(context).copyWith(
                        color: LKColors.secondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: UIUtils.xs),
                    Text(
                      'Bonjour $displayName',
                      style: UIUtils.titleLarge(
                        context,
                      ).copyWith(fontSize: 22, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: UIUtils.xs),
                    Text(
                      'Choisissez la session à rejoindre.',
                      style: UIUtils.bodySmall(
                        context,
                      ).copyWith(color: LKColors.textHint),
                    ),
                    SizedBox(height: UIUtils.sm),
                    InkWell(
                      onTap: onEditAthleteProfile,
                      borderRadius: UIUtils.borderRadiusAllFull,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: LKColors.primary.withValues(alpha: 0.14),
                          borderRadius: UIUtils.borderRadiusAllFull,
                          border: Border.all(
                            color: LKColors.primary.withValues(alpha: 0.35),
                            width: 0.6,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.monitor_heart_rounded,
                              size: 14,
                              color: LKColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                athleteProfile.healthConsentGranted
                                    ? '${athleteProfile.sport} • ${athleteProfile.weightKg.toStringAsFixed(0)} kg • FCmax ${athleteProfile.maxHeartRate} bpm'
                                    : '${athleteProfile.sport} • ${athleteProfile.effectiveAgeYears} ans • Seuils défaut',
                                style: UIUtils.bodySmall(context).copyWith(
                                  color: LKColors.textPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.edit_rounded,
                              size: 12,
                              color: LKColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: UIUtils.md),
            ],
          ),
          SizedBox(height: UIUtils.lg),
          Container(
            padding: UIUtils.paddingMD,
            decoration: BoxDecoration(
              color: LKColors.background.withValues(alpha: 0.35),
              borderRadius: UIUtils.borderRadiusAllMD,
              border: Border.all(
                color: LKColors.border.withValues(alpha: 0.6),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                _buildStat(
                  context,
                  value: '$roomsCount',
                  label: 'session${roomsCount > 1 ? 's' : ''}',
                  color: LKColors.textPrimary,
                ),
                _buildStatDivider(),
                _buildStat(
                  context,
                  value: '$liveCount',
                  label: 'en direct',
                  color: LKColors.success,
                ),
                if (recordingCount > 0) ...[
                  _buildStatDivider(),
                  _buildStat(
                    context,
                    value: '$recordingCount',
                    label: 'enregistrement',
                    color: LKColors.danger,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(
    BuildContext context, {
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: UIUtils.titleSmall(
              context,
            ).copyWith(color: color, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            style: UIUtils.bodySmall(
              context,
            ).copyWith(color: LKColors.textHint, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(
      width: 0.5,
      height: 28,
      margin: EdgeInsets.symmetric(horizontal: UIUtils.md),
      color: LKColors.border,
    );
  }
}

/// Carte d'une salle LiveKit en direct sur [RoomsScreen].
class MobileRoomCard extends StatelessWidget {
  const MobileRoomCard({
    super.key,
    required this.room,
    required this.effectiveOrgId,
    required this.onJoin,
    required this.onOpenReplay,
  });

  final MobileRoom room;
  final String? effectiveOrgId;
  final VoidCallback onJoin;
  final VoidCallback? onOpenReplay;

  @override
  Widget build(BuildContext context) {
    final isLive = room.participantCount > 0;
    final isRecording = room.isRecording;
    final accent = isRecording
        ? LKColors.danger
        : isLive
        ? LKColors.success
        : LKColors.primary;
    final stateLabel = isRecording
        ? 'Enregistrement'
        : room.isBusy
        ? room.recordingLabel
        : isLive
        ? 'En direct'
        : 'Disponible';
    final stateIcon = isRecording
        ? Icons.fiber_manual_record_rounded
        : isLive
        ? Icons.sensors_rounded
        : Icons.videocam_rounded;

    return Container(
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllXL,
        border: Border.all(
          color: accent.withValues(alpha: isLive || isRecording ? 0.34 : 0.16),
          width: 0.5,
        ),
        boxShadow: isLive || isRecording
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: UIUtils.borderRadiusAllXL,
          onTap: onJoin,
          child: Padding(
            padding: UIUtils.paddingLG,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: UIUtils.borderRadiusAllLG,
                      ),
                      child: Icon(
                        isRecording
                            ? Icons.fiber_manual_record_rounded
                            : Icons.videocam_rounded,
                        color: accent,
                        size: 24,
                      ),
                    ),
                    SizedBox(width: UIUtils.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            room.displayTitle,
                            style: UIUtils.titleMedium(context).copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (room.title != null &&
                              room.title!.trim().isNotEmpty &&
                              room.title!.trim() != room.name)
                            Text(
                              room.name,
                              style: UIUtils.bodySmall(context).copyWith(
                                color: LKColors.textHint,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          SizedBox(height: UIUtils.sm),
                          Wrap(
                            spacing: UIUtils.sm,
                            runSpacing: UIUtils.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _buildStatusPill(
                                context,
                                label: stateLabel,
                                icon: stateIcon,
                                color: accent,
                                emphasize: isLive || isRecording,
                              ),
                              _buildInfoPill(
                                context,
                                icon: Icons.people_alt_rounded,
                                label: room.participantCount == 0
                                    ? 'Aucun participant'
                                    : '${room.participantCount} participant${room.participantCount > 1 ? 's' : ''}',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: UIUtils.md),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: onJoin,
                          icon: const Icon(Icons.login_rounded, size: 18),
                          label: Text(
                            'Rejoindre la session',
                            style: UIUtils.labelMedium(context).copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: UIUtils.borderRadiusAllMD,
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ),
                    if (effectiveOrgId != null && onOpenReplay != null) ...[
                      SizedBox(width: UIUtils.sm),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: onOpenReplay,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: LKColors.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: UIUtils.borderRadiusAllMD,
                            ),
                          ),
                          child: const Icon(Icons.analytics_outlined),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    bool emphasize = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: emphasize ? 9 : 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: emphasize ? 0.14 : 0.1),
        borderRadius: UIUtils.borderRadiusAllFull,
        border: Border.all(
          color: color.withValues(alpha: emphasize ? 0.3 : 0.18),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: UIUtils.bodySmall(
              context,
            ).copyWith(color: color, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPill(
    BuildContext context, {
    required IconData icon,
    required String label,
    Color? color,
  }) {
    final tone = color ?? LKColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: tone),
        const SizedBox(width: 4),
        Text(
          label,
          style: UIUtils.bodySmall(context).copyWith(color: tone, fontSize: 11),
        ),
      ],
    );
  }
}

/// Carte d'une séance d'organisation dans l'onglet « Séances & Relecture ».
class OrgSessionCard extends StatelessWidget {
  const OrgSessionCard({
    super.key,
    required this.session,
    required this.onTap,
  });

  final OrgSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = session.finished
        ? LKColors.secondary
        : session.recording
        ? LKColors.danger
        : LKColors.success;

    return Container(
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllXL,
        border: Border.all(color: LKColors.border, width: 0.7),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          contentPadding: UIUtils.paddingLG,
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: UIUtils.borderRadiusAllMD,
            ),
            child: Icon(
              session.finished
                  ? Icons.play_circle_outline_rounded
                  : Icons.sensors_rounded,
              color: accent,
            ),
          ),
          title: Text(
            session.displayTitle,
            style: UIUtils.titleMedium(context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            [
              session.roomName,
              if (session.finished) 'Terminée • Relecture' else 'Active',
              '${session.participantUids.length} membre(s)',
            ].join(' • '),
            style: UIUtils.bodySmall(context),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: LKColors.textSecondary,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Vue d'état vide ou d'erreur avec bouton d'action sur [RoomsScreen].
class RoomsMessageState extends StatelessWidget {
  const RoomsMessageState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: UIUtils.paddingLG,
      children: [
        const SizedBox(height: 48),
        Container(
          padding: UIUtils.paddingXXL,
          decoration: BoxDecoration(
            color: LKColors.surface,
            borderRadius: UIUtils.borderRadiusAllXL,
            border: Border.all(color: LKColors.border, width: 0.5),
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: LKColors.primary.withValues(alpha: 0.1),
                  borderRadius: UIUtils.borderRadiusAllFull,
                ),
                child: Icon(icon, size: 30, color: LKColors.primary),
              ),
              SizedBox(height: UIUtils.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: UIUtils.titleMedium(context),
              ),
              SizedBox(height: UIUtils.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: UIUtils.bodySmall(
                  context,
                ).copyWith(color: LKColors.textHint, height: 1.5),
              ),
              SizedBox(height: UIUtils.xl),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(actionLabel, style: UIUtils.labelLarge(context)),
                style: FilledButton.styleFrom(
                  backgroundColor: LKColors.primary,
                  foregroundColor: Colors.white,
                  padding: UIUtils.paddingHorizontalXL.add(
                    UIUtils.paddingVerticalMD,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: UIUtils.borderRadiusAllMD,
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
