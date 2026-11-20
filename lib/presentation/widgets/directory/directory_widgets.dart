import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/directory_models.dart';
import '../../../theme.dart';
import '../../utils/ui_utils.dart';

/// Pastille de statut d'une organisation ou d'une demande d'adhésion dans l'annuaire.
class DirectoryStatusPill extends StatelessWidget {
  const DirectoryStatusPill({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.38), width: 0.7),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Carte d'un club ou coach dans la liste Explorer de l'annuaire.
class DirectoryOrganizationCard extends StatelessWidget {
  const DirectoryOrganizationCard({
    super.key,
    required this.organization,
    required this.onTap,
  });

  final DirectoryOrganization organization;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final org = organization;
    final visibleSports = org.sportsDetails.take(3).toList();
    final extraSportsCount = org.sportsDetails.length - visibleSports.length;
    final countsText =
        '${org.athletesCount} athlète${org.athletesCount > 1 ? 's' : ''} · ${org.coachesCount} coach${org.coachesCount > 1 ? 's' : ''}';

    return InkWell(
      borderRadius: UIUtils.borderRadiusAllLG,
      onTap: onTap,
      child: Container(
        padding: UIUtils.paddingMD,
        decoration: BoxDecoration(
          color: LKColors.surfaceElevated,
          borderRadius: UIUtils.borderRadiusAllLG,
          border: Border.all(color: LKColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: LKColors.primary.withValues(alpha: 0.14),
                  child: Icon(
                    org.isSoloCoach
                        ? Icons.person_rounded
                        : Icons.apartment_rounded,
                    color: LKColors.primary,
                    size: 20,
                  ),
                ),
                SizedBox(width: UIUtils.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        org.name,
                        style: UIUtils.titleSmall(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          org.typeLabel,
                          if (org.city != null && org.city!.isNotEmpty)
                            org.city!,
                        ].join(' · '),
                        style: UIUtils.bodySmall(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildOrgStateBadge(org),
              ],
            ),
            if (org.description != null && org.description!.isNotEmpty) ...[
              SizedBox(height: UIUtils.sm),
              Text(
                org.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: UIUtils.bodySmall(context).copyWith(
                  color: LKColors.textPrimary.withValues(alpha: 0.86),
                ),
              ),
            ],
            SizedBox(height: UIUtils.sm),
            Text(
              countsText,
              style: UIUtils.bodySmall(context).copyWith(fontSize: 11),
            ),
            if (visibleSports.isNotEmpty) ...[
              SizedBox(height: UIUtils.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in visibleSports)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: LKColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: LKColors.border, width: 0.7),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (s.isIndoor) ...[
                            const Icon(
                              Icons.home_outlined,
                              size: 12,
                              color: LKColors.primary,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              s.label,
                              overflow: TextOverflow.ellipsis,
                              style: UIUtils.bodySmall(context).copyWith(
                                color: LKColors.textPrimary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (extraSportsCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: LKColors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '+$extraSportsCount',
                        style: const TextStyle(
                          color: LKColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOrgStateBadge(DirectoryOrganization org) {
    if (org.isMember) {
      return const DirectoryStatusPill(
        label: 'Membre',
        color: LKColors.success,
      );
    }
    if (org.hasPendingRequest) {
      return const DirectoryStatusPill(
        label: 'En attente',
        color: LKColors.primary,
      );
    }
    if (!org.acceptingJoinRequests) {
      return const DirectoryStatusPill(
        label: 'Complet / Fermé',
        color: LKColors.textHint,
      );
    }
    return const Icon(
      Icons.chevron_right_rounded,
      color: LKColors.textSecondary,
    );
  }
}

/// Carte d'une demande d'adhésion dans l'onglet « Mes demandes ».
class DirectoryJoinRequestCard extends StatelessWidget {
  const DirectoryJoinRequestCard({
    super.key,
    required this.request,
    required this.dateFmt,
    required this.cancelling,
    required this.sportLabelFor,
    required this.onOpenOrganizationDetail,
    required this.onCancelRequest,
    required this.onOpenApprovedOrganization,
  });

  final MyJoinRequest request;
  final DateFormat dateFmt;
  final bool cancelling;
  final String Function(String code) sportLabelFor;
  final VoidCallback onOpenOrganizationDetail;
  final VoidCallback onCancelRequest;
  final VoidCallback onOpenApprovedOrganization;

  @override
  Widget build(BuildContext context) {
    final req = request;
    final Color statusColor;
    if (req.isApproved) {
      statusColor = LKColors.success;
    } else if (req.isRejected) {
      statusColor = LKColors.danger;
    } else if (req.isPending) {
      statusColor = LKColors.primary;
    } else {
      statusColor = LKColors.textHint;
    }

    final sportLabels = req.requestedSportsDetails.isNotEmpty
        ? req.requestedSportsDetails.map((s) => s.label).toList()
        : req.requestedSports.map(sportLabelFor).toList();

    return Container(
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: LKColors.surfaceElevated,
        borderRadius: UIUtils.borderRadiusAllLG,
        border: Border.all(
          color: req.isPending
              ? LKColors.primary.withValues(alpha: 0.4)
              : LKColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req.orgName,
                      style: UIUtils.titleSmall(context),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        req.isSoloCoach ? 'Coach privé' : 'Club',
                        if (req.orgCity != null && req.orgCity!.isNotEmpty)
                          req.orgCity!,
                        if (req.createdAt != null)
                          dateFmt.format(req.createdAt!.toLocal()),
                      ].join(' · '),
                      style: UIUtils.bodySmall(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              DirectoryStatusPill(label: req.statusLabel, color: statusColor),
            ],
          ),
          if (sportLabels.isNotEmpty) ...[
            SizedBox(height: UIUtils.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: sportLabels
                  .map(
                    (label) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: LKColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: LKColors.border, width: 0.6),
                      ),
                      child: Text(
                        label,
                        style: UIUtils.bodySmall(context).copyWith(
                          color: LKColors.textPrimary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if ((req.requestedGroupName != null &&
                  req.requestedGroupName!.isNotEmpty) ||
              (req.targetCoachName != null &&
                  req.targetCoachName!.isNotEmpty)) ...[
            SizedBox(height: UIUtils.xs),
            Text(
              [
                if (req.requestedGroupName != null &&
                    req.requestedGroupName!.isNotEmpty)
                  'Groupe : ${req.requestedGroupName}',
                if (req.targetCoachName != null &&
                    req.targetCoachName!.isNotEmpty)
                  'Coach : ${req.targetCoachName}',
              ].join(' · '),
              style: UIUtils.bodySmall(context),
            ),
          ],
          if (req.decisionNote != null && req.decisionNote!.isNotEmpty) ...[
            SizedBox(height: UIUtils.sm),
            Container(
              width: double.infinity,
              padding: UIUtils.paddingSM,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.10),
                borderRadius: UIUtils.borderRadiusAllSM,
                border: Border.all(color: statusColor.withValues(alpha: 0.35)),
              ),
              child: Text(
                req.decisionNote!,
                style: UIUtils.bodySmall(context).copyWith(
                  color: LKColors.textPrimary,
                ),
              ),
            ),
          ],
          SizedBox(height: UIUtils.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (req.isPending) ...[
                TextButton(
                  onPressed: onOpenOrganizationDetail,
                  child: const Text('Voir la fiche'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: LKColors.danger,
                    side: const BorderSide(color: LKColors.danger),
                  ),
                  onPressed: cancelling ? null : onCancelRequest,
                  icon: cancelling
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Annuler'),
                ),
              ] else if (req.isApproved) ...[
                FilledButton.icon(
                  onPressed: onOpenApprovedOrganization,
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(
                    req.isSoloCoach ? 'Accéder au coach' : 'Accéder au club',
                  ),
                ),
              ] else ...[
                OutlinedButton(
                  onPressed: onOpenOrganizationDetail,
                  child: const Text('Voir la fiche'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Boîte de dialogue de filtrage par ville dans l'annuaire.
class DirectoryCityFilterDialog extends StatefulWidget {
  const DirectoryCityFilterDialog({
    super.key,
    required this.initialCity,
  });

  final String initialCity;

  @override
  State<DirectoryCityFilterDialog> createState() =>
      _DirectoryCityFilterDialogState();
}

class _DirectoryCityFilterDialogState extends State<DirectoryCityFilterDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialCity);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: LKColors.surfaceElevated,
      title: const Text('Filtrer par ville'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        decoration: UIUtils.inputDecoration(
          labelText: 'Ville',
          hintText: 'Ex : Lyon, Paris, Annecy…',
          prefixIcon: Icons.location_city_rounded,
        ),
      ),
      actions: [
        if (widget.initialCity.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Effacer'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
          child: const Text('Appliquer'),
        ),
      ],
    );
  }
}

/// Affiche la feuille modale de sélection d'une discipline sportive (Indoor / Outdoor).
Future<String?> showDirectorySportPickerSheet(
  BuildContext context, {
  required List<SportMeta> sportsCatalog,
  required String? selectedSportCode,
}) {
  final indoorSports = sportsCatalog.where((s) => s.isIndoor).toList();
  final outdoorSports = sportsCatalog.where((s) => !s.isIndoor).toList();

  return showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height * 0.78,
      ),
      decoration: const BoxDecoration(
        color: LKColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: LKColors.border)),
      ),
      padding: UIUtils.paddingLG,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: LKColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(height: UIUtils.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Filtrer par discipline',
                  style: UIUtils.titleMedium(ctx),
                ),
              ),
              if (selectedSportCode != null)
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(''),
                  child: const Text('Tous'),
                ),
              IconButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          SizedBox(height: UIUtils.sm),
          if (sportsCatalog.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Le référentiel des sports n\'est pas disponible pour le moment.',
                textAlign: TextAlign.center,
                style: UIUtils.bodySmall(ctx),
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (indoorSports.isNotEmpty) ...[
                    Text(
                      'Sports Indoor',
                      style: UIUtils.labelLarge(ctx).copyWith(
                        color: LKColors.primary,
                      ),
                    ),
                    SizedBox(height: UIUtils.xs),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: indoorSports.map((s) {
                        final selected = selectedSportCode == s.code;
                        return ChoiceChip(
                          label: Text(s.label),
                          selected: selected,
                          selectedColor:
                              LKColors.primary.withValues(alpha: 0.22),
                          onSelected: (_) => Navigator.of(ctx).pop(
                            selected ? '' : s.code,
                          ),
                        );
                      }).toList(),
                    ),
                    SizedBox(height: UIUtils.lg),
                  ],
                  if (outdoorSports.isNotEmpty) ...[
                    Text(
                      'Sports Outdoor',
                      style: UIUtils.labelLarge(ctx).copyWith(
                        color: LKColors.success,
                      ),
                    ),
                    SizedBox(height: UIUtils.xs),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: outdoorSports.map((s) {
                        final selected = selectedSportCode == s.code;
                        return ChoiceChip(
                          label: Text(s.label),
                          selected: selected,
                          selectedColor:
                              LKColors.primary.withValues(alpha: 0.22),
                          onSelected: (_) => Navigator.of(ctx).pop(
                            selected ? '' : s.code,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
