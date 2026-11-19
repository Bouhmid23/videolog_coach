import 'package:flutter/material.dart';

import '../../data/room_lobby.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

/// Carte de prévisualisation des participants invités et connectés dans le lobby
/// avant d'entrer dans une session LiveKit (`GET /rooms/{room_name}/lobby`).
class RoomLobbyCard extends StatelessWidget {
  const RoomLobbyCard({
    super.key,
    required this.lobby,
    required this.loading,
    this.error,
    this.currentUid,
    this.onRefresh,
  });

  final RoomLobby? lobby;
  final bool loading;
  final String? error;
  final String? currentUid;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final participants = lobby?.invitedParticipants ?? const <LobbyParticipant>[];
    final connectedCount = lobby?.connectedCount ?? 0;
    final totalInvited = participants.length;

    return Container(
      padding: UIUtils.paddingLG,
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllLG,
        border: Border.all(color: LKColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.groups_2_rounded,
                size: 18,
                color: LKColors.primary,
              ),
              SizedBox(width: UIUtils.sm),
              Expanded(
                child: Text(
                  'Participants de la séance',
                  style: UIUtils.labelLarge(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (lobby != null)
                _StatusChip(
                  label: totalInvited > 0
                      ? '$connectedCount/$totalInvited en ligne'
                      : '$connectedCount en ligne',
                  color: connectedCount > 0
                      ? LKColors.success
                      : LKColors.textHint,
                ),
              if (onRefresh != null)
                IconButton(
                  onPressed: loading ? null : onRefresh,
                  icon: loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              LKColors.primary,
                            ),
                          ),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  color: LKColors.textSecondary,
                  tooltip: 'Actualiser les participants',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                ),
            ],
          ),
          if (lobby != null && !lobby!.accessible) ...[
            SizedBox(height: UIUtils.sm),
            Container(
              padding: UIUtils.paddingMD,
              decoration: BoxDecoration(
                color: LKColors.danger.withValues(alpha: 0.12),
                borderRadius: UIUtils.borderRadiusAllMD,
                border: Border.all(
                  color: LKColors.danger.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.block_rounded,
                    size: 18,
                    color: LKColors.danger,
                  ),
                  SizedBox(width: UIUtils.sm),
                  Expanded(
                    child: Text(
                      lobby!.reason ?? 'Cette session n\'est plus accessible.',
                      style: UIUtils.bodySmall(
                        context,
                      ).copyWith(color: LKColors.danger),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: UIUtils.sm),
          if (loading && lobby == null)
            Padding(
              padding: EdgeInsets.symmetric(vertical: UIUtils.md),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        LKColors.primary,
                      ),
                    ),
                  ),
                  SizedBox(width: UIUtils.md),
                  Expanded(
                    child: Text(
                      'Chargement des participants…',
                      style: UIUtils.bodySmall(
                        context,
                      ).copyWith(color: LKColors.textSecondary),
                    ),
                  ),
                ],
              ),
            )
          else if (error != null && lobby == null)
            Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: LKColors.textHint,
                ),
                SizedBox(width: UIUtils.sm),
                Expanded(
                  child: Text(
                    error!,
                    style: UIUtils.bodySmall(
                      context,
                    ).copyWith(color: LKColors.textHint),
                  ),
                ),
              ],
            )
          else if (participants.isEmpty)
            Text(
              connectedCount > 0
                  ? '$connectedCount participant${connectedCount > 1 ? 's' : ''} déjà connecté${connectedCount > 1 ? 's' : ''}.'
                  : 'Aucun participant connecté pour le moment.',
              style: UIUtils.bodySmall(
                context,
              ).copyWith(color: LKColors.textSecondary),
            )
          else
            Column(
              children: [
                for (var i = 0; i < participants.length; i++) ...[
                  if (i > 0)
                    Container(
                      height: 0.5,
                      margin: EdgeInsets.symmetric(vertical: UIUtils.xs),
                      color: LKColors.border.withValues(alpha: 0.6),
                    ),
                  _ParticipantRow(
                    participant: participants[i],
                    isMe:
                        currentUid != null &&
                        currentUid!.isNotEmpty &&
                        participants[i].uid == currentUid,
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.participant,
    required this.isMe,
  });

  final LobbyParticipant participant;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final isConnected = participant.connected;
    final statusColor = isConnected ? LKColors.success : LKColors.textHint;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (isConnected ? LKColors.primary : LKColors.border)
                      .withValues(alpha: isConnected ? 0.16 : 0.35),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  participant.initials,
                  style: UIUtils.labelMedium(context).copyWith(
                    color: isConnected
                        ? LKColors.primary
                        : LKColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: LKColors.surface, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(width: UIUtils.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isMe
                            ? '${participant.displayName} (Vous)'
                            : participant.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: UIUtils.bodyMedium(
                          context,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (participant.isOwner) ...[
                      SizedBox(width: UIUtils.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: LKColors.secondary.withValues(alpha: 0.14),
                          borderRadius: UIUtils.borderRadiusAllFull,
                        ),
                        child: Text(
                          'Coach',
                          style: UIUtils.bodySmall(context).copyWith(
                            color: LKColors.secondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: UIUtils.sm),
          _StatusChip(
            label: isConnected ? 'En ligne' : 'Invité',
            color: statusColor,
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: UIUtils.sm, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: UIUtils.borderRadiusAllFull,
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 7, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: UIUtils.bodySmall(context).copyWith(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
