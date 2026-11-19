import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app_config.dart';
import 'directory_screen.dart';
import '../../core/account_controller.dart';
import '../../core/api_service.dart';
import '../../core/auth_service.dart';
import '../../data/account_models.dart';
import '../../data/training_models.dart';
import '../../exts.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';
import '../widgets/athlete_profile_sheet.dart';
import '../widgets/notifications_sheet.dart';
import '../widgets/organization_hub_sheet.dart';
import '../widgets/pending_invitations_card.dart';
import '../widgets/planned_workout_sheet.dart';
import '../widgets/shimmer_skeleton.dart';
import '../widgets/wellness_checkin_sheet.dart';

/// Accueil simplifié de l'athlète : forme du jour, séance du jour,
/// profil sportif basique et statut du consentement santé RGPD.
class AthleteHomeScreen extends StatefulWidget {
  const AthleteHomeScreen({
    this.apiService,
    this.accountController,
    this.now,
    this.onSelectTab,
    this.embeddedInShell = false,
    super.key,
  });

  final ApiService? apiService;
  final AccountController? accountController;
  final DateTime? now;
  final ValueChanged<int>? onSelectTab;
  final bool embeddedInShell;

  @override
  State<AthleteHomeScreen> createState() => _AthleteHomeScreenState();
}

class _AthleteHomeScreenState extends State<AthleteHomeScreen> {
  List<PlannedWorkout> _todayWorkouts = const [];
  List<CalendarGoal> _goals = const [];
  List<InAppInvitation> _pendingInvitations = const [];
  int _unreadNotifications = 0;
  bool _loading = true;
  String? _error;
  String? _loadedOrgId;

  ApiService get _api => widget.apiService ?? ApiService.instance;
  AccountController get _account =>
      widget.accountController ?? AccountController.instance;
  DateTime get _today => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _account.addListener(_onAccountChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initLoad();
      }
    });
  }

  @override
  void dispose() {
    _account.removeListener(_onAccountChanged);
    super.dispose();
  }

  void _onAccountChanged() {
    if (!mounted) return;
    final currentOrgId = _account.activeOrgId;
    setState(() {});
    if (!_loading &&
        (currentOrgId != _loadedOrgId ||
            (_todayWorkouts.isEmpty && _goals.isEmpty && _error == null))) {
      _load(showSpinner: currentOrgId != _loadedOrgId);
    }
  }

  Future<void> _initLoad() async {
    if (!_account.hasLoaded) {
      await _account.refresh();
    }
    await _load();
  }

  Future<void> _load({bool showSpinner = true}) async {
    final orgId = _account.activeOrgId;
    final uid = _account.uid;
    _loadedOrgId = orgId;
    if (orgId == null || orgId.isEmpty || uid.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _todayWorkouts = const [];
          _goals = const [];
          _error = null;
        });
      }
      return;
    }

    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final today = DateTime(_today.year, _today.month, _today.day);
    final todayIso = formatIsoDate(today);

    try {
      final calendarFuture = _api.fetchCalendar(
        orgId,
        from: todayIso,
        to: todayIso,
        uid: uid,
      );
      final invitationsFuture = _fetchInvitationsSafe();
      final notificationsFuture = _fetchUnreadNotificationsSafe();
      final calendar = await calendarFuture;
      final invitations = await invitationsFuture;
      final unread = await notificationsFuture;
      if (!mounted) return;
      setState(() {
        _todayWorkouts = calendar.workoutsForDay(today);
        _goals = calendar.goals;
        _pendingInvitations = invitations;
        _unreadNotifications = unread;
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de charger votre tableau de bord.';
        _loading = false;
      });
    }
  }

  Future<void> _openWellness() async {
    final orgId = _account.activeOrgId;
    final uid = _account.uid;
    if (orgId == null || orgId.isEmpty || uid.isEmpty) return;

    final saved = await showWellnessCheckinSheet(
      context,
      orgId: orgId,
      uid: uid,
      hasHealthConsent: _account.hasHealthConsent,
      apiService: _api,
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Forme du jour enregistrée.'),
          backgroundColor: LKColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<List<InAppInvitation>> _fetchInvitationsSafe() async {
    try {
      return await _api.fetchMyInvitations();
    } catch (_) {
      return const [];
    }
  }

  Future<int> _fetchUnreadNotificationsSafe() async {
    try {
      final resp = await _api.fetchNotifications();
      return resp.unreadCount;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _openNotifications() async {
    await showNotificationsSheet(
      context,
      apiService: _api,
      accountController: _account,
      onUnreadCountChanged: (count) {
        if (mounted) {
          setState(() => _unreadNotifications = count);
        }
      },
      onOpenCalendarTab: () => widget.onSelectTab?.call(1),
    );
  }

  Future<void> _openProfile() async {
    final updated = await showAthleteProfileSheet(context);
    if (updated != null && mounted) {
      await _load(showSpinner: false);
    }
  }

  Future<void> _openOrgHub() async {
    await showOrganizationHubSheet(
      context,
      apiService: _api,
      accountController: _account,
      initialInvitations: _pendingInvitations,
      onChanged: () {
        if (mounted) {
          _load(showSpinner: false);
        }
      },
    );
    if (mounted) {
      final freshInvs = await _fetchInvitationsSafe();
      if (mounted) {
        setState(() => _pendingInvitations = freshInvs);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeMembership = _account.activeMembership;

    return Scaffold(
      backgroundColor: LKColors.background,
      appBar: widget.embeddedInShell
          ? null
          : AppBar(
        backgroundColor: LKColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        foregroundColor: LKColors.textPrimary,
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Accueil Athlète', style: UIUtils.titleMedium(context)),
            if (activeMembership != null)
              Text(
                '${activeMembership.displayOrgName} • ${activeMembership.roleLabel}'
                '${AppConfig.isLocal ? ' • LOCAL' : ''}',
                style: UIUtils.bodySmall(context).copyWith(
                  color: AppConfig.isLocal ? LKColors.warning : LKColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              )
            else
              Text(
                AppConfig.isLocal
                    ? 'LOCAL · ${AppConfig.apiBaseUrl}'
                    : 'Forme, séance & profil santé',
                style: UIUtils.bodySmall(context).copyWith(
                  color: AppConfig.isLocal ? LKColors.warning : LKColors.textHint,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            tooltip: 'Notifications',
            onPressed: _openNotifications,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                UIUtils.textPrimaryIcon(Icons.notifications_outlined, size: 22),
                if (_unreadNotifications > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: LKColors.danger,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _unreadNotifications > 99
                            ? '99+'
                            : '$_unreadNotifications',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            tooltip: 'Mes clubs, coachs & invitations',
            onPressed: _openOrgHub,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                UIUtils.textPrimaryIcon(Icons.apartment_rounded, size: 22),
                if (_pendingInvitations.isNotEmpty)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: LKColors.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${_pendingInvitations.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: _openProfile,
            icon: UIUtils.textPrimaryIcon(Icons.monitor_heart_outlined, size: 22),
            tooltip: 'Profil sportif & consentement RGPD',
          ),
          PopupMenuButton<String>(
            tooltip: 'Plus d’options',
            color: LKColors.surfaceElevated,
            icon: UIUtils.textPrimaryIcon(Icons.more_vert_rounded, size: 22),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onSelected: (value) async {
              if (value == 'refresh') {
                if (!_loading) await _load(showSpinner: false);
              } else if (value == 'sign_out') {
                final confirmed = await context.showSignOutDialog();
                if (confirmed == true) {
                  await AuthService.instance.signOut();
                }
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem<String>(
                value: 'refresh',
                enabled: !_loading,
                child: const Row(
                  children: [
                    Icon(Icons.refresh_rounded, size: 18, color: LKColors.textPrimary),
                    SizedBox(width: 10),
                    Text('Actualiser'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'sign_out',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 18, color: LKColors.danger),
                    SizedBox(width: 10),
                    Text(
                      'Se déconnecter',
                      style: TextStyle(color: LKColors.danger),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: LKColors.primary,
          onRefresh: () => _load(showSpinner: false),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final orgId = _account.activeOrgId;
    if (orgId == null || orgId.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: UIUtils.paddingXL,
        children: [
          SizedBox(height: UIUtils.xxxl),
          const Icon(
            Icons.apartment_rounded,
            size: 48,
            color: LKColors.textHint,
          ),
          SizedBox(height: UIUtils.md),
          Text(
            'Aucune organisation active',
            textAlign: TextAlign.center,
            style: UIUtils.titleMedium(context),
          ),
          SizedBox(height: UIUtils.xs),
          Text(
            'Rejoignez un club ou un coach depuis l\'annuaire pour accéder à votre espace athlète.',
            textAlign: TextAlign.center,
            style: UIUtils.bodySmall(context),
          ),
          SizedBox(height: UIUtils.lg),
          Center(
            child: FilledButton.icon(
              onPressed: () {
                final router = GoRouter.maybeOf(context);
                if (router != null) {
                  context.push('/directory');
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DirectoryScreen(
                        apiService: _api,
                        accountController: _account,
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.explore_rounded, size: 18),
              label: const Text('Explorer les clubs & coachs'),
            ),
          ),
          SizedBox(height: UIUtils.sm),
          Center(
            child: TextButton.icon(
              onPressed: () {
                final router = GoRouter.maybeOf(context);
                if (router != null) {
                  context.push('/directory?tab=requests');
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DirectoryScreen(
                        initialTabIndex: 1,
                        apiService: _api,
                        accountController: _account,
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.hourglass_top_rounded, size: 16),
              label: const Text('Mes demandes d\'adhésion'),
            ),
          ),
        ],
      );
    }

    if (_loading) {
      return const RoomsListSkeleton();
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: UIUtils.paddingXL,
        children: [
          SizedBox(height: UIUtils.xxxl),
          const Icon(
            Icons.cloud_off_rounded,
            size: 48,
            color: LKColors.danger,
          ),
          SizedBox(height: UIUtils.md),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: UIUtils.bodyMedium(context),
          ),
          SizedBox(height: UIUtils.lg),
          Center(
            child: FilledButton.icon(
              onPressed: () => _load(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Réessayer'),
            ),
          ),
        ],
      );
    }

    final user = _account.me?.user;
    final profile = user?.athleteProfile;
    final hasConsent = _account.hasHealthConsent;
    final activeCoaches = _account.activeMembership?.coaches ?? const [];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: UIUtils.paddingLG,
      children: [
        if (_pendingInvitations.isNotEmpty) ...[
          PendingInvitationsCard(
            invitations: _pendingInvitations,
            apiService: _api,
            accountController: _account,
            onInvitationHandled: ({
              required bool accepted,
              required InAppInvitation invitation,
            }) async {
              if (!mounted) return;
              setState(() {
                _pendingInvitations = _pendingInvitations
                    .where((i) => i.id != invitation.id)
                    .toList();
              });
              if (accepted) {
                await _load(showSpinner: false);
              }
            },
          ),
          SizedBox(height: UIUtils.md),
        ],

        // Carte Check-in Forme du jour
        _WellnessQuickCard(onTap: _openWellness),
        SizedBox(height: UIUtils.md),

        // Carte Profil basique & Consentement santé RGPD
        _ProfileConsentCard(
          profile: profile,
          hasHealthConsent: hasConsent,
          onTap: _openProfile,
        ),
        if (activeCoaches.isNotEmpty) ...[
          SizedBox(height: UIUtils.md),
          _OrgCoachesCard(
            coaches: activeCoaches,
            onTapCoach: (coach) => showCoachProfileDialog(context, coach),
          ),
        ],
        SizedBox(height: UIUtils.lg),

        // Séance du jour
        Text('Séance du jour', style: UIUtils.titleSmall(context)),
        SizedBox(height: UIUtils.sm),
        if (_todayWorkouts.isEmpty)
          Container(
            padding: UIUtils.paddingMD,
            decoration: BoxDecoration(
              color: LKColors.surfaceElevated,
              borderRadius: UIUtils.borderRadiusAllMD,
              border: Border.all(color: LKColors.border, width: 0.6),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.self_improvement_rounded,
                  color: LKColors.textHint,
                  size: 20,
                ),
                SizedBox(width: UIUtils.md),
                Expanded(
                  child: Text(
                    'Aucune séance planifiée aujourd\'hui.',
                    style: UIUtils.bodySmall(context),
                  ),
                ),
              ],
            ),
          )
        else
          for (final workout in _todayWorkouts) ...[
            _TodayWorkoutCard(
              workout: workout,
              onTap: () => showPlannedWorkoutSheet(
                context,
                orgId: orgId,
                workout: workout,
                apiService: _api,
              ),
            ),
            SizedBox(height: UIUtils.sm),
          ],

        if (_goals.isNotEmpty) ...[
          SizedBox(height: UIUtils.lg),
          Text('Objectifs à venir', style: UIUtils.titleSmall(context)),
          SizedBox(height: UIUtils.sm),
          for (final goal in _goals) ...[
            _GoalCard(goal: goal, today: _today),
            SizedBox(height: UIUtils.sm),
          ],
        ],
        SizedBox(height: UIUtils.xl),
      ],
    );
  }
}

class _WellnessQuickCard extends StatelessWidget {
  const _WellnessQuickCard({required this.onTap});

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

class _ProfileConsentCard extends StatelessWidget {
  const _ProfileConsentCard({
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
                  SizedBox(height: 2),
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

class _TodayWorkoutCard extends StatelessWidget {
  const _TodayWorkoutCard({
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

class _GoalCard extends StatelessWidget {
  const _GoalCard({
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
                    if (goal.sport != null && goal.sport!.isNotEmpty) goal.sport!,
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

class _OrgCoachesCard extends StatelessWidget {
  const _OrgCoachesCard({
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
