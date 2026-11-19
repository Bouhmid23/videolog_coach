import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/account_controller.dart';
import '../../core/api_service.dart';
import '../../data/account_models.dart';
import '../../theme.dart';
import '../screens/directory_screen.dart';
import '../utils/ui_utils.dart';
import 'pending_invitations_card.dart';

/// Affiche la fiche d'un coach (`coaches[].coach_profile` issu de `/v1/me`).
Future<void> showCoachProfileDialog(
  BuildContext context,
  OrgCoachSummary coach,
) {
  final profile = coach.coachProfile;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: LKColors.surfaceElevated,
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: LKColors.primary.withValues(alpha: 0.16),
            child: const Icon(
              Icons.sports_rounded,
              color: LKColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  coach.name,
                  style: UIUtils.titleMedium(ctx),
                ),
                Text(
                  coach.roleLabel,
                  style: UIUtils.bodySmall(ctx).copyWith(
                    color: LKColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: profile == null || profile.isEmpty
            ? Text(
                'Ce coach n\'a pas encore renseigné sa fiche publique.',
                style: UIUtils.bodySmall(ctx),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (profile.sports.isNotEmpty) ...[
                    Text(
                      'Disciplines & niveaux',
                      style: UIUtils.labelLarge(ctx),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: profile.sports.map((s) {
                        final exp = s.yearsExperience != null
                            ? ' · ${s.yearsExperience} ans'
                            : '';
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: LKColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: LKColors.border,
                              width: 0.6,
                            ),
                          ),
                          child: Text(
                            '${s.sport} (${s.level}$exp)',
                            style: UIUtils.bodySmall(ctx).copyWith(
                              color: LKColors.textPrimary,
                              fontSize: 11,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (profile.certifications != null &&
                      profile.certifications!.isNotEmpty) ...[
                    Text(
                      'Diplômes & certifications',
                      style: UIUtils.labelLarge(ctx),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.certifications!,
                      style: UIUtils.bodySmall(ctx).copyWith(
                        color: LKColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                    Text(
                      'Présentation',
                      style: UIUtils.labelLarge(ctx),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.bio!,
                      style: UIUtils.bodySmall(ctx).copyWith(
                        color: LKColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Fermer'),
        ),
      ],
    ),
  );
}

/// Feuille modale de gestion des clubs / coachs :
/// - invitations in-app reçues (Accepter / Refuser)
/// - changement d'organisation active
/// - consultation des fiches coach
/// - quitter un club ou un coach (`DELETE /v1/orgs/{org_id}/members/me`)
Future<void> showOrganizationHubSheet(
  BuildContext context, {
  ApiService? apiService,
  AccountController? accountController,
  List<InAppInvitation>? initialInvitations,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _OrganizationHubSheet(
      apiService: apiService,
      accountController: accountController,
      initialInvitations: initialInvitations,
      onChanged: onChanged,
    ),
  );
}

class _OrganizationHubSheet extends StatefulWidget {
  const _OrganizationHubSheet({
    this.apiService,
    this.accountController,
    this.initialInvitations,
    this.onChanged,
  });

  final ApiService? apiService;
  final AccountController? accountController;
  final List<InAppInvitation>? initialInvitations;
  final VoidCallback? onChanged;

  @override
  State<_OrganizationHubSheet> createState() => _OrganizationHubSheetState();
}

class _OrganizationHubSheetState extends State<_OrganizationHubSheet> {
  List<InAppInvitation> _invitations = const [];
  bool _loadingInvitations = false;
  int _pendingJoinRequestsCount = 0;
  String? _leavingOrgId;

  ApiService get _api => widget.apiService ?? ApiService.instance;
  AccountController get _account =>
      widget.accountController ?? AccountController.instance;

  @override
  void initState() {
    super.initState();
    _invitations = widget.initialInvitations ?? const [];
    _loadInvitations();
  }

  Future<void> _loadInvitations() async {
    if (mounted) setState(() => _loadingInvitations = true);
    try {
      final list = await _api.fetchMyInvitations();
      if (!mounted) return;
      setState(() {
        _invitations = list;
        _loadingInvitations = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingInvitations = false);
    }
    try {
      final pending = await _api.fetchMyJoinRequests(status: 'pending');
      if (!mounted) return;
      setState(() => _pendingJoinRequestsCount = pending.length);
    } catch (_) {
      // Silencieux.
    }
  }

  void _openDirectory({int initialTabIndex = 0}) {
    final router = GoRouter.maybeOf(context);
    final navigator = Navigator.of(context);
    navigator.pop();
    if (router != null) {
      router.push(
        initialTabIndex == 1 ? '/directory?tab=requests' : '/directory',
      );
    } else {
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => DirectoryScreen(
            initialTabIndex: initialTabIndex,
            apiService: _api,
            accountController: _account,
          ),
        ),
      );
    }
  }

  Future<void> _leaveOrg(OrgMembership membership) async {
    if (_leavingOrgId != null) return;
    final orgName = membership.displayOrgName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LKColors.surfaceElevated,
        title: Text('Quitter $orgName ?'),
        content: const Text(
          'Vous n\'aurez plus accès aux séances et aux échanges de cette organisation, sauf si vous êtes réinvité.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: LKColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _leavingOrgId = membership.orgId);
    try {
      await _api.leaveOrganization(membership.orgId);
      await _account.refresh(syncAthleteProfile: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Vous avez quitté $orgName.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      widget.onChanged?.call();
      if (_account.memberships.isEmpty && mounted) {
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: LKColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de quitter cette organisation.'),
          backgroundColor: LKColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _leavingOrgId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _account,
      builder: (context, _) {
        final memberships = _account.memberships;
        final activeOrgId = _account.activeOrgId;

        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          expand: false,
          builder: (ctx, scrollController) => Container(
            decoration: const BoxDecoration(
              color: LKColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: LKColors.border, width: 0.8)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: LKColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.apartment_rounded,
                        color: LKColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Mes clubs & coachs',
                          style: UIUtils.titleMedium(ctx),
                        ),
                      ),
                      if (_loadingInvitations)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        IconButton(
                          tooltip: 'Actualiser les invitations',
                          onPressed: _loadInvitations,
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                        ),
                      IconButton(
                        tooltip: 'Fermer',
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: LKColors.border),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: UIUtils.paddingLG,
                    children: [
                      if (_invitations.isNotEmpty) ...[
                        PendingInvitationsCard(
                          invitations: _invitations,
                          apiService: _api,
                          accountController: _account,
                          onInvitationHandled: ({
                            required bool accepted,
                            required InAppInvitation invitation,
                          }) async {
                            setState(() {
                              _invitations = _invitations
                                  .where((i) => i.id != invitation.id)
                                  .toList();
                            });
                            widget.onChanged?.call();
                          },
                        ),
                        SizedBox(height: UIUtils.lg),
                      ],
                      if (memberships.isEmpty)
                        Container(
                          padding: UIUtils.paddingLG,
                          decoration: BoxDecoration(
                            color: LKColors.surfaceElevated,
                            borderRadius: UIUtils.borderRadiusAllMD,
                            border: Border.all(
                              color: LKColors.border,
                              width: 0.6,
                            ),
                          ),
                          child: Text(
                            'Vous n\'êtes rattaché à aucun club ou coach actuellement.',
                            style: UIUtils.bodySmall(ctx),
                          ),
                        )
                      else
                        for (final m in memberships) ...[
                          _buildMembershipCard(ctx, m, m.orgId == activeOrgId),
                          SizedBox(height: UIUtils.md),
                        ],
                      SizedBox(height: UIUtils.sm),
                      Container(
                        padding: UIUtils.paddingMD,
                        decoration: BoxDecoration(
                          color: LKColors.surfaceElevated,
                          borderRadius: UIUtils.borderRadiusAllLG,
                          border: Border.all(
                            color: LKColors.primary.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton.icon(
                              onPressed: () => _openDirectory(),
                              icon: const Icon(Icons.explore_rounded, size: 18),
                              label: const Text('Trouver un club ou un coach'),
                            ),
                            SizedBox(height: UIUtils.xs),
                            TextButton.icon(
                              onPressed: () =>
                                  _openDirectory(initialTabIndex: 1),
                              icon: const Icon(
                                Icons.hourglass_top_rounded,
                                size: 16,
                              ),
                              label: Text(
                                _pendingJoinRequestsCount > 0
                                    ? 'Mes demandes d\'adhésion ($_pendingJoinRequestsCount)'
                                    : 'Mes demandes d\'adhésion',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMembershipCard(
    BuildContext context,
    OrgMembership m,
    bool isActive,
  ) {
    final org = m.organization;
    final leaving = _leavingOrgId == m.orgId;
    final subtitleParts = <String>[
      org?.isSoloCoach == true ? 'Coach privé' : 'Club',
      m.roleLabel,
      if (org?.city != null && org!.city!.trim().isNotEmpty) org.city!.trim(),
    ];

    return Container(
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: LKColors.surfaceElevated,
        borderRadius: UIUtils.borderRadiusAllLG,
        border: Border.all(
          color: isActive ? LKColors.primary.withValues(alpha: 0.5) : LKColors.border,
          width: isActive ? 1.1 : 0.7,
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            m.displayOrgName,
                            style: UIUtils.titleSmall(context),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: LKColors.primary.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Actif',
                              style: TextStyle(
                                color: LKColors.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleParts.join(' · '),
                      style: UIUtils.bodySmall(context),
                    ),
                  ],
                ),
              ),
              if (!isActive)
                TextButton(
                  onPressed: _leavingOrgId != null
                      ? null
                      : () async {
                          await _account.selectOrganization(m.orgId);
                          widget.onChanged?.call();
                        },
                  child: const Text('Activer'),
                ),
            ],
          ),
          if (m.coaches.isNotEmpty) ...[
            SizedBox(height: UIUtils.sm),
            Text(
              m.coaches.length > 1 ? 'Coachs' : 'Coach',
              style: UIUtils.bodySmall(context).copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: m.coaches.map((coach) {
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
                  onPressed: () => showCoachProfileDialog(context, coach),
                );
              }).toList(),
            ),
          ],
          if (!m.isOwner) ...[
            SizedBox(height: UIUtils.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: LKColors.danger),
                onPressed: _leavingOrgId != null ? null : () => _leaveOrg(m),
                icon: leaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.exit_to_app_rounded, size: 16),
                label: Text(
                  org?.isSoloCoach == true
                      ? 'Quitter ce coach'
                      : 'Quitter ce club',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
