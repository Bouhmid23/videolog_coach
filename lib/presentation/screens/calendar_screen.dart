import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_config.dart';
import '../../core/account_controller.dart';
import '../../core/api_service.dart';
import '../../core/auth_service.dart';
import '../../data/training_models.dart';
import '../../exts.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';
import '../widgets/athlete_profile_sheet.dart';
import '../widgets/planned_workout_sheet.dart';
import '../widgets/shimmer_skeleton.dart';
import '../widgets/wellness_checkin_sheet.dart';

/// Écran centré sur la routine quotidienne : « Séance du jour », étapes,
/// cibles, export `.fit` et saisie rapide « Forme du jour ».
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    this.apiService,
    this.accountController,
    this.now,
    this.embeddedInShell = false,
    super.key,
  });

  final ApiService? apiService;
  final AccountController? accountController;
  final DateTime? now;
  final bool embeddedInShell;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarResponse? _calendar;
  bool _loading = true;
  String? _error;
  String? _loadedOrgId;

  ApiService get _api => widget.apiService ?? ApiService.instance;
  AccountController get _account =>
      widget.accountController ?? AccountController.instance;
  DateTime get _today {
    final raw = widget.now ?? DateTime.now();
    return DateTime(raw.year, raw.month, raw.day);
  }

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
    if (!_loading && (currentOrgId != _loadedOrgId || _calendar == null)) {
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
    _loadedOrgId = orgId;
    if (orgId == null || orgId.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _calendar = null;
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

    final today = _today;
    final tomorrow = today.add(const Duration(days: 1));
    final from = formatIsoDate(today);
    final to = formatIsoDate(tomorrow);

    try {
      final result = await _api.fetchCalendar(
        orgId,
        from: from,
        to: to,
        uid: _account.uid.isNotEmpty ? _account.uid : null,
      );
      if (!mounted) return;
      setState(() {
        _calendar = result;
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
        _error = 'Impossible de charger la séance du jour.';
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
            Text('Séance du jour', style: UIUtils.titleMedium(context)),
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
                    : 'Programme quotidien',
                style: UIUtils.bodySmall(context).copyWith(
                  color: AppConfig.isLocal ? LKColors.warning : LKColors.textHint,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          if (_account.memberships.length > 1)
            PopupMenuButton<String>(
              tooltip: 'Changer d\'organisation',
              icon: const Icon(Icons.apartment_rounded),
              color: LKColors.surfaceElevated,
              onSelected: (orgId) async {
                await _account.selectOrganization(orgId);
                await _load();
              },
              itemBuilder: (ctx) => _account.memberships
                  .map(
                    (m) => PopupMenuItem<String>(
                      value: m.orgId,
                      child: Row(
                        children: [
                          Icon(
                            m.orgId == _account.activeOrgId
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            size: 16,
                            color: m.orgId == _account.activeOrgId
                                ? LKColors.primary
                                : LKColors.textHint,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${m.displayOrgName} (${m.roleLabel})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: _account.activeOrgId == null ? null : _openWellness,
            icon: UIUtils.textPrimaryIcon(Icons.favorite_outline_rounded, size: 22),
            tooltip: 'Forme du jour',
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => showAthleteProfileSheet(context),
            icon: UIUtils.textPrimaryIcon(Icons.monitor_heart_outlined, size: 22),
            tooltip: 'Profil sportif & santé',
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: _loading ? null : () => _load(showSpinner: false),
            icon: UIUtils.textPrimaryIcon(Icons.refresh_rounded, size: 22),
            tooltip: 'Actualiser',
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () async {
              final confirmed = await context.showSignOutDialog();
              if (confirmed == true) {
                await AuthService.instance.signOut();
              }
            },
            icon: UIUtils.textPrimaryIcon(Icons.logout_rounded, size: 22),
            tooltip: 'Se déconnecter',
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
            'Rejoignez un club ou finalisez votre onboarding pour consulter votre séance du jour.',
            textAlign: TextAlign.center,
            style: UIUtils.bodySmall(context),
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
            'Séance indisponible',
            textAlign: TextAlign.center,
            style: UIUtils.titleMedium(context),
          ),
          SizedBox(height: UIUtils.xs),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: UIUtils.bodySmall(context),
          ),
          SizedBox(height: UIUtils.lg),
          Center(
            child: FilledButton(
              onPressed: _load,
              child: const Text('Réessayer'),
            ),
          ),
        ],
      );
    }

    final calendar = _calendar ?? const CalendarResponse();
    final today = _today;
    final tomorrow = today.add(const Duration(days: 1));
    final todayWorkouts = calendar.workoutsForDay(today);
    final todayActivities = calendar.activitiesForDay(today);
    final tomorrowWorkouts = calendar.workoutsForDay(tomorrow);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        UIUtils.lg,
        UIUtils.md,
        UIUtils.lg,
        UIUtils.xxl,
      ),
      children: [
        // Date du jour
        Text(
          _formatFrenchDate(today),
          style: UIUtils.titleMedium(context).copyWith(
            color: LKColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: UIUtils.md),

        // Raccourci Forme du jour
        InkWell(
          borderRadius: UIUtils.borderRadiusAllLG,
          onTap: _openWellness,
          child: Container(
            padding: UIUtils.paddingMD,
            decoration: BoxDecoration(
              color: LKColors.surfaceElevated,
              borderRadius: UIUtils.borderRadiusAllLG,
              border: Border.all(
                color: LKColors.primary.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: LKColors.primary.withValues(alpha: 0.16),
                  child: const Icon(
                    Icons.favorite_rounded,
                    size: 18,
                    color: LKColors.primary,
                  ),
                ),
                SizedBox(width: UIUtils.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Forme du jour',
                        style: UIUtils.titleSmall(context),
                      ),
                      Text(
                        'Renseigner sommeil, fatigue, courbatures et stress (10 s)',
                        style: UIUtils.bodySmall(context),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: LKColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: UIUtils.lg),

        // Séance(s) du jour
        if (todayWorkouts.isEmpty)
          _EmptyTodayCard()
        else
          for (var i = 0; i < todayWorkouts.length; i++) ...[
            _TodayWorkoutHighlight(
              workout: todayWorkouts[i],
              onTap: () => showPlannedWorkoutSheet(
                context,
                orgId: orgId,
                workout: todayWorkouts[i],
                apiService: _api,
              ),
            ),
            if (i < todayWorkouts.length - 1) SizedBox(height: UIUtils.md),
          ],

        // Activités réalisées aujourd'hui
        if (todayActivities.isNotEmpty) ...[
          SizedBox(height: UIUtils.lg),
          Text('Réalisé aujourd\'hui', style: UIUtils.titleSmall(context)),
          SizedBox(height: UIUtils.sm),
          for (final a in todayActivities) ...[
            InkWell(
              borderRadius: UIUtils.borderRadiusAllMD,
              onTap: a.id.isEmpty
                  ? null
                  : () => context.push(
                        '/activities/${Uri.encodeComponent(orgId)}/${Uri.encodeComponent(a.id)}',
                      ),
              child: Container(
                padding: UIUtils.paddingMD,
                decoration: BoxDecoration(
                  color: LKColors.surfaceElevated,
                  borderRadius: UIUtils.borderRadiusAllMD,
                  border: Border.all(
                    color: LKColors.success.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: LKColors.success,
                    ),
                    SizedBox(width: UIUtils.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.title,
                            style: UIUtils.titleSmall(context),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            [
                              a.sport,
                              formatDurationSeconds(a.durationS),
                              if (a.distanceM != null && a.distanceM! > 0)
                                '${(a.distanceM! / 1000).toStringAsFixed(1)} km',
                              if (a.tss != null) '${a.tss!.round()} pts d\'effort',
                            ].join(' · '),
                            style: UIUtils.bodySmall(context),
                          ),
                        ],
                      ),
                    ),
                    if (a.id.isNotEmpty)
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: LKColors.textSecondary,
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(height: UIUtils.sm),
          ],
        ],

        // Aperçu léger de demain
        if (tomorrowWorkouts.isNotEmpty) ...[
          SizedBox(height: UIUtils.lg),
          Text('Demain', style: UIUtils.titleSmall(context)),
          SizedBox(height: UIUtils.sm),
          for (final w in tomorrowWorkouts) ...[
            _TomorrowPreviewCard(
              workout: w,
              onTap: () => showPlannedWorkoutSheet(
                context,
                orgId: orgId,
                workout: w,
                apiService: _api,
              ),
            ),
            SizedBox(height: UIUtils.sm),
          ],
        ],
      ],
    );
  }

  static String _formatFrenchDate(DateTime date) {
    const days = [
      'Lundi',
      'Mardi',
      'Mercredi',
      'Jeudi',
      'Vendredi',
      'Samedi',
      'Dimanche',
    ];
    const months = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ];
    return '${days[date.weekday - 1]} ${date.day} ${months[date.month - 1]}';
  }
}

class _EmptyTodayCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: UIUtils.paddingXL,
      decoration: BoxDecoration(
        color: LKColors.surfaceElevated,
        borderRadius: UIUtils.borderRadiusAllLG,
        border: Border.all(color: LKColors.border),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.self_improvement_rounded,
            size: 38,
            color: LKColors.textHint,
          ),
          SizedBox(height: UIUtils.sm),
          Text(
            'Journée de repos',
            style: UIUtils.titleSmall(context),
          ),
          SizedBox(height: UIUtils.xs),
          Text(
            'Aucune séance planifiée aujourd\'hui.',
            textAlign: TextAlign.center,
            style: UIUtils.bodySmall(context),
          ),
        ],
      ),
    );
  }
}

class _TodayWorkoutHighlight extends StatelessWidget {
  const _TodayWorkoutHighlight({
    required this.workout,
    required this.onTap,
  });

  final PlannedWorkout workout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasStartTime =
        workout.startTime != null && workout.startTime!.trim().isNotEmpty;

    return InkWell(
      borderRadius: UIUtils.borderRadiusAllLG,
      onTap: onTap,
      child: Container(
        padding: UIUtils.paddingLG,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              LKColors.primary.withValues(alpha: 0.22),
              LKColors.surfaceElevated,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: UIUtils.borderRadiusAllLG,
          border: Border.all(color: LKColors.primary.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'SÉANCE DU JOUR',
                  style: UIUtils.bodySmall(context).copyWith(
                    color: LKColors.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                if (hasStartTime) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: LKColors.primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      workout.startTime!.trim(),
                      style: UIUtils.bodySmall(context).copyWith(
                        color: LKColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  [
                    formatDurationSeconds(workout.estimatedDurationS),
                    if (workout.estimatedTss != null)
                      '${workout.estimatedTss!.round()} pts d\'effort',
                  ].join(' · '),
                  style: UIUtils.bodySmall(context).copyWith(
                    color: LKColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SizedBox(height: UIUtils.xs),
            Text(workout.title, style: UIUtils.titleLarge(context)),
            SizedBox(height: 2),
            Text(
              '${workout.sport.toUpperCase()} • ${workout.statusLabel}',
              style: UIUtils.bodySmall(context),
            ),
            if (workout.coachNote != null &&
                workout.coachNote!.trim().isNotEmpty) ...[
              SizedBox(height: UIUtils.sm),
              Text(
                workout.coachNote!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: UIUtils.bodySmall(context).copyWith(
                  color: LKColors.textPrimary,
                ),
              ),
            ],
            if (workout.blocks.isNotEmpty) ...[
              SizedBox(height: UIUtils.md),
              WorkoutIntensityBar(blocks: workout.blocks, height: 38),
            ],
            if (workout.steps.isNotEmpty) ...[
              SizedBox(height: UIUtils.md),
              for (var i = 0; i < workout.steps.length && i < 3; i++) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Text(
                        '${i + 1}.',
                        style: UIUtils.bodySmall(context).copyWith(
                          color: LKColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          workout.steps[i].name.isNotEmpty
                              ? workout.steps[i].name
                              : 'Étape ${i + 1}',
                          style: UIUtils.bodySmall(context).copyWith(
                            color: LKColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (workout.steps[i].displayTarget.isNotEmpty)
                        Text(
                          workout.steps[i].displayTarget,
                          style: UIUtils.bodySmall(context).copyWith(
                            color: LKColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (workout.steps.length > 3)
                Text(
                  '+ ${workout.steps.length - 3} étape(s) supplémentaire(s)',
                  style: UIUtils.bodySmall(context).copyWith(
                    color: LKColors.textHint,
                    fontSize: 11,
                  ),
                ),
            ],
            SizedBox(height: UIUtils.md),
            Row(
              children: [
                Text(
                  'Détails, étapes & export .FIT',
                  style: UIUtils.bodySmall(context).copyWith(
                    color: LKColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.open_in_new_rounded,
                  size: 16,
                  color: LKColors.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TomorrowPreviewCard extends StatelessWidget {
  const _TomorrowPreviewCard({
    required this.workout,
    required this.onTap,
  });

  final PlannedWorkout workout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: UIUtils.borderRadiusAllMD,
      onTap: onTap,
      child: Container(
        padding: UIUtils.paddingMD,
        decoration: BoxDecoration(
          color: LKColors.surfaceElevated,
          borderRadius: UIUtils.borderRadiusAllMD,
          border: Border.all(color: LKColors.border),
        ),
        child: Row(
          children: [
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
                  SizedBox(height: 2),
                  Text(
                    [
                      if (workout.startTime != null &&
                          workout.startTime!.trim().isNotEmpty)
                        workout.startTime!.trim(),
                      workout.sport,
                      formatDurationSeconds(workout.estimatedDurationS),
                      if (workout.estimatedTss != null)
                        '${workout.estimatedTss!.round()} pts d\'effort',
                    ].join(' · '),
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
