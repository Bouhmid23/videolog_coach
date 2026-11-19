import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/account_controller.dart';
import '../../core/api_service.dart';
import '../../core/auth_service.dart';
import '../../data/directory_models.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';
import '../widgets/join_request_sheet.dart';

/// Fiche détaillée d'un club ou coach privé (`/directory/:orgId`).
class DirectoryOrganizationDetailScreen extends StatefulWidget {
  const DirectoryOrganizationDetailScreen({
    required this.orgId,
    this.initialOrganization,
    this.apiService,
    this.accountController,
    this.authService,
    this.emailVerifiedOverride,
    super.key,
  });

  final String orgId;
  final DirectoryOrganization? initialOrganization;
  final ApiService? apiService;
  final AccountController? accountController;
  final AuthService? authService;
  final bool? emailVerifiedOverride;

  @override
  State<DirectoryOrganizationDetailScreen> createState() =>
      _DirectoryOrganizationDetailScreenState();
}

class _DirectoryOrganizationDetailScreenState
    extends State<DirectoryOrganizationDetailScreen> {
  DirectoryOrganization? _org;
  MyJoinRequest? _myJoinRequest;
  bool _loading = true;
  bool _cancelling = false;
  String? _error;

  ApiService get _api => widget.apiService ?? ApiService.instance;
  AccountController get _account =>
      widget.accountController ?? AccountController.instance;
  AuthService get _auth => widget.authService ?? AuthService.instance;

  @override
  void initState() {
    super.initState();
    _org = widget.initialOrganization;
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _api.fetchDirectoryOrganizationDetail(widget.orgId);
      if (!mounted) return;
      setState(() {
        _org = detail.organization;
        _myJoinRequest = detail.myJoinRequest;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isNotFound) {
        UIUtils.showSnackBar(
          context,
          e.message,
          tone: AppSnackBarTone.warning,
        );
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          context.go('/directory');
        }
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de charger la fiche de cette organisation.';
        _loading = false;
      });
    }
  }

  Future<void> _openJoinRequestSheet() async {
    final org = _org;
    if (org == null) return;
    final result = await showJoinRequestSheet(
      context,
      organization: org,
      apiService: _api,
      accountController: _account,
      authService: _auth,
      emailVerifiedOverride: widget.emailVerifiedOverride,
    );
    if (!mounted || result == null) return;

    if (result.createdRequest != null) {
      final req = result.createdRequest!;
      setState(() {
        _myJoinRequest = req;
        _org = org.copyWith(pendingRequestId: req.id);
      });
      UIUtils.showSnackBar(
        context,
        'Demande d\'adhésion envoyée à ${org.name}.',
        tone: AppSnackBarTone.success,
      );
      return;
    }

    if (result.shouldRefreshOrg) {
      await _load();
      unawaited(_account.refresh(syncAthleteProfile: false));
    }
  }

  Future<void> _cancelPendingRequest() async {
    final org = _org;
    final requestId = org?.pendingRequestId ?? _myJoinRequest?.id;
    if (org == null || requestId == null || requestId.isEmpty || _cancelling) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LKColors.surfaceElevated,
        title: const Text('Annuler votre demande ?'),
        content: Text(
          'Votre demande d\'adhésion auprès de ${org.name} sera annulée. Vous pourrez toujours en soumettre une nouvelle plus tard.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Conserver'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: LKColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Annuler la demande'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await _api.cancelJoinRequest(requestId);
      if (!mounted) return;
      setState(() {
        _org = org.copyWith(clearPendingRequestId: true);
        if (_myJoinRequest != null && _myJoinRequest!.id == requestId) {
          _myJoinRequest = _myJoinRequest!.copyWith(status: 'cancelled');
        }
        _cancelling = false;
      });
      UIUtils.showSnackBar(
        context,
        'Demande d\'adhésion annulée.',
        tone: AppSnackBarTone.info,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      UIUtils.showSnackBar(context, e.message, tone: AppSnackBarTone.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      UIUtils.showSnackBar(
        context,
        'Impossible d\'annuler la demande pour le moment.',
        tone: AppSnackBarTone.error,
      );
    }
  }

  Future<void> _openOrganizationWorkspace() async {
    final org = _org;
    if (org == null) return;
    if (!_account.memberships.any((m) => m.orgId == org.id)) {
      await _account.refresh(syncAthleteProfile: false);
    }
    await _account.selectOrganization(org.id);
    if (!mounted) return;
    context.go('/rooms');
  }

  void _popWithResult() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(_org);
    } else {
      context.go('/directory');
    }
  }

  @override
  Widget build(BuildContext context) {
    final org = _org;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _popWithResult();
      },
      child: Scaffold(
        backgroundColor: LKColors.background,
        appBar: AppBar(
          backgroundColor: LKColors.surfaceElevated,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: 'Retour',
            onPressed: _popWithResult,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(
            org?.name.isNotEmpty == true ? org!.name : 'Fiche organisation',
            style: UIUtils.titleMedium(context),
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Actualiser',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(0.8),
            child: Divider(height: 0.8, thickness: 0.8, color: LKColors.border),
          ),
        ),
        body: _buildBody(context),
        bottomNavigationBar: org == null ? null : _buildStickyBottomBar(context, org),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final org = _org;
    if (_loading && org == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && org == null) {
      return Center(
        child: Padding(
          padding: UIUtils.paddingXL,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 44,
                color: LKColors.danger,
              ),
              SizedBox(height: UIUtils.md),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: UIUtils.bodyMedium(context),
              ),
              SizedBox(height: UIUtils.lg),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }
    if (org == null) {
      return const SizedBox.shrink();
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: UIUtils.paddingLG,
        children: [
          _buildHeaderCard(context, org),
          if (_myJoinRequest != null && !_myJoinRequest!.isCancelled) ...[
            SizedBox(height: UIUtils.md),
            _buildJoinRequestStatusBanner(context, _myJoinRequest!),
          ],
          if (org.sportsDetails.isNotEmpty) ...[
            SizedBox(height: UIUtils.xl),
            _buildSectionTitle(
              context,
              Icons.sports_rounded,
              'Sports pratiqués & encadrés',
              count: org.sportsDetails.length,
            ),
            SizedBox(height: UIUtils.sm),
            for (final sport in org.sportsDetails) ...[
              _buildSportDetailCard(context, sport),
              SizedBox(height: UIUtils.md),
            ],
          ] else if (org.sports.isNotEmpty) ...[
            SizedBox(height: UIUtils.xl),
            _buildSectionTitle(
              context,
              Icons.sports_rounded,
              'Disciplines',
              count: org.sports.length,
            ),
            SizedBox(height: UIUtils.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: org.sports
                  .map(
                    (s) => Chip(
                      label: Text(s),
                      backgroundColor: LKColors.surfaceElevated,
                      side: const BorderSide(color: LKColors.border),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (org.coaches.isNotEmpty) ...[
            SizedBox(height: UIUtils.xl),
            _buildSectionTitle(
              context,
              Icons.people_outline_rounded,
              'Équipe d\'encadrement',
              count: org.coaches.length,
            ),
            SizedBox(height: UIUtils.sm),
            for (final coach in org.coaches) ...[
              _buildCoachCard(context, coach),
              SizedBox(height: UIUtils.md),
            ],
          ],
          SizedBox(height: UIUtils.lg),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context, DirectoryOrganization org) {
    final locationParts = <String>[
      if (org.city != null && org.city!.isNotEmpty) org.city!,
      if (org.country.isNotEmpty) org.country,
    ];
    final countParts = <String>[
      '${org.athletesCount} athlète${org.athletesCount > 1 ? 's' : ''}',
      '${org.coachesCount} coach${org.coachesCount > 1 ? 's' : ''}',
      if (org.groupsCount > 0)
        '${org.groupsCount} groupe${org.groupsCount > 1 ? 's' : ''}',
    ];

    return Container(
      padding: UIUtils.paddingLG,
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
                radius: 24,
                backgroundColor: LKColors.primary.withValues(alpha: 0.16),
                child: Icon(
                  org.isSoloCoach
                      ? Icons.person_rounded
                      : Icons.apartment_rounded,
                  color: LKColors.primary,
                  size: 24,
                ),
              ),
              SizedBox(width: UIUtils.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(org.name, style: UIUtils.titleLarge(context)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _pill(
                          org.typeLabel,
                          color: LKColors.primary,
                        ),
                        if (org.hasIndoorSports)
                          _pill(
                            'Indoor',
                            icon: Icons.home_outlined,
                            color: LKColors.secondary,
                          ),
                        _buildStatusBadge(org),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (locationParts.isNotEmpty) ...[
            SizedBox(height: UIUtils.md),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: LKColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  locationParts.join(', '),
                  style: UIUtils.bodySmall(context).copyWith(
                    color: LKColors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: UIUtils.sm),
          Row(
            children: [
              const Icon(
                Icons.groups_outlined,
                size: 16,
                color: LKColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  countParts.join(' · '),
                  style: UIUtils.bodySmall(context),
                ),
              ),
            ],
          ),
          if (org.description != null && org.description!.isNotEmpty) ...[
            SizedBox(height: UIUtils.md),
            const Divider(height: 1, color: LKColors.border),
            SizedBox(height: UIUtils.md),
            Text(
              org.description!,
              style: UIUtils.bodyMedium(context).copyWith(
                color: LKColors.textPrimary,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge(DirectoryOrganization org) {
    if (org.isMember) {
      return _pill(
        'Membre',
        icon: Icons.check_circle_outline_rounded,
        color: LKColors.success,
      );
    }
    if (org.hasPendingRequest) {
      return _pill(
        'En attente',
        icon: Icons.hourglass_top_rounded,
        color: LKColors.primary,
      );
    }
    if (!org.acceptingJoinRequests) {
      return _pill(
        'Complet / Fermé',
        icon: Icons.lock_outline_rounded,
        color: LKColors.textHint,
      );
    }
    return _pill(
      'Adhésions ouvertes',
      color: LKColors.success,
    );
  }

  Widget _buildJoinRequestStatusBanner(
    BuildContext context,
    MyJoinRequest req,
  ) {
    final Color accent;
    final IconData icon;
    final String headline;
    if (req.isApproved) {
      accent = LKColors.success;
      icon = Icons.check_circle_rounded;
      headline = 'Votre demande d\'adhésion a été acceptée';
    } else if (req.isRejected) {
      accent = LKColors.danger;
      icon = Icons.info_outline_rounded;
      headline = 'Votre dernière demande n\'a pas été retenue';
    } else {
      accent = LKColors.primary;
      icon = Icons.hourglass_top_rounded;
      headline = 'Votre demande d\'adhésion est en attente';
    }

    return Container(
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 20),
          SizedBox(width: UIUtils.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: UIUtils.labelLarge(context).copyWith(color: accent),
                ),
                if (req.decisionNote != null &&
                    req.decisionNote!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    req.decisionNote!,
                    style: UIUtils.bodySmall(context).copyWith(
                      color: LKColors.textPrimary,
                    ),
                  ),
                ] else if (req.message != null && req.message!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '« ${req.message!} »',
                    style: UIUtils.bodySmall(context),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(
    BuildContext context,
    IconData icon,
    String title, {
    int? count,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: LKColors.primary),
        SizedBox(width: UIUtils.sm),
        Expanded(
          child: Text(title, style: UIUtils.titleMedium(context)),
        ),
        if (count != null)
          Text(
            '$count',
            style: UIUtils.bodySmall(context).copyWith(
              color: LKColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }

  Widget _buildSportDetailCard(BuildContext context, OrgSportDetail sport) {
    final metrics = sport.supportedMetricLabels;

    return Container(
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
            children: [
              Expanded(
                child: Text(
                  sport.label,
                  style: UIUtils.titleSmall(context),
                ),
              ),
              const SizedBox(width: 8),
              _pill(
                sport.isIndoor ? 'Indoor' : 'Outdoor',
                icon: sport.isIndoor
                    ? Icons.home_outlined
                    : Icons.wb_sunny_outlined,
                color: sport.isIndoor ? LKColors.primary : LKColors.success,
              ),
              const SizedBox(width: 6),
              _pill(
                sport.categoryLabel,
                color: LKColors.textSecondary,
              ),
            ],
          ),
          if (metrics.isNotEmpty) ...[
            SizedBox(height: UIUtils.sm),
            Text(
              'Métriques & capteurs',
              style: UIUtils.bodySmall(context).copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: metrics
                  .map(
                    (m) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: LKColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: LKColors.border, width: 0.7),
                      ),
                      child: Text(
                        m,
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
          if (sport.levels.isNotEmpty || sport.maxYearsExperience != null) ...[
            SizedBox(height: UIUtils.sm),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final level in sport.levels)
                  _pill(level, color: LKColors.warning),
                if (sport.maxYearsExperience != null)
                  Text(
                    'Jusqu\'à ${sport.maxYearsExperience} ans d\'expérience',
                    style: UIUtils.bodySmall(context).copyWith(
                      color: LKColors.textPrimary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ],
          if (sport.groups.isNotEmpty) ...[
            SizedBox(height: UIUtils.sm),
            Text(
              'Groupes associés',
              style: UIUtils.bodySmall(context).copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: sport.groups
                  .map(
                    (g) => _pill(
                      g.name,
                      icon: Icons.groups_outlined,
                      color: LKColors.secondary,
                    ),
                  )
                  .toList(),
            ),
          ],
          if (sport.coaches.isNotEmpty) ...[
            SizedBox(height: UIUtils.sm),
            Text(
              'Coachs spécialisés',
              style: UIUtils.bodySmall(context).copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: sport.coaches.map((c) {
                final details = <String>[
                  if (c.level != null && c.level!.isNotEmpty) c.level!,
                  if (c.yearsExperience != null) '${c.yearsExperience} ans',
                ];
                final text = details.isEmpty
                    ? c.name
                    : '${c.name} (${details.join(' · ')})';
                return _pill(
                  text,
                  icon: Icons.person_outline_rounded,
                  color: LKColors.textPrimary,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCoachCard(BuildContext context, DirectoryCoach coach) {
    return Container(
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
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: LKColors.primary.withValues(alpha: 0.16),
                child: const Icon(
                  Icons.sports_rounded,
                  color: LKColors.primary,
                  size: 18,
                ),
              ),
              SizedBox(width: UIUtils.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(coach.name, style: UIUtils.titleSmall(context)),
                    Text(
                      coach.roleLabel,
                      style: UIUtils.bodySmall(context).copyWith(
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
          if (coach.certifications != null &&
              coach.certifications!.isNotEmpty) ...[
            SizedBox(height: UIUtils.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.verified_outlined,
                  size: 15,
                  color: LKColors.success,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    coach.certifications!,
                    style: UIUtils.bodySmall(context).copyWith(
                      color: LKColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (coach.bio != null && coach.bio!.isNotEmpty) ...[
            SizedBox(height: UIUtils.xs),
            Text(
              coach.bio!,
              style: UIUtils.bodySmall(context).copyWith(height: 1.4),
            ),
          ],
          if (coach.sports.isNotEmpty) ...[
            SizedBox(height: UIUtils.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: coach.sports.map((s) {
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
                    border: Border.all(color: LKColors.border, width: 0.7),
                  ),
                  child: Text(
                    '${s.label} (${s.level}$exp)',
                    style: UIUtils.bodySmall(context).copyWith(
                      color: LKColors.textPrimary,
                      fontSize: 11,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStickyBottomBar(
    BuildContext context,
    DirectoryOrganization org,
  ) {
    Widget button;
    if (org.isMember) {
      button = FilledButton.tonalIcon(
        onPressed: _openOrganizationWorkspace,
        icon: const Icon(Icons.open_in_new_rounded, size: 18),
        label: const Text('Ouvrir cet espace'),
      );
    } else if (org.hasPendingRequest) {
      button = OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: LKColors.danger,
          side: const BorderSide(color: LKColors.danger),
        ),
        onPressed: _cancelling ? null : _cancelPendingRequest,
        icon: _cancelling
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cancel_outlined, size: 18),
        label: Text(
          _cancelling ? 'Annulation…' : 'Annuler ma demande',
        ),
      );
    } else if (!org.acceptingJoinRequests) {
      button = FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.lock_outline_rounded, size: 18),
        label: const Text('Adhésions fermées'),
      );
    } else {
      button = FilledButton.icon(
        onPressed: _openJoinRequestSheet,
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
        label: const Text('Demander l\'adhésion'),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: LKColors.surfaceElevated,
          border: Border(top: BorderSide(color: LKColors.border, width: 0.8)),
        ),
        child: SizedBox(height: 48, width: double.infinity, child: button),
      ),
    );
  }

  Widget _pill(String text, {IconData? icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
