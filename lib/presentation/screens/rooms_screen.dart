import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_config.dart';
import '../../core/account_controller.dart';
import '../../core/api_service.dart';
import '../../core/auth_service.dart';
import '../../data/athlete_profile.dart';
import '../../data/mobile_room.dart';
import '../../data/session_models.dart';
import '../../exts.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';
import '../widgets/athlete_profile_sheet.dart';
import '../widgets/create_session_sheet.dart';
import '../widgets/organization_hub_sheet.dart';
import '../widgets/shimmer_skeleton.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({
    this.embeddedInShell = false,
    super.key,
  });

  final bool embeddedInShell;

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  List<MobileRoom> _rooms = const [];
  List<OrgSession> _orgSessions = const [];
  AthleteProfile _athleteProfile = const AthleteProfile();
  bool _loading = true;
  String? _error;
  String? _loadedOrgId;

  int get _liveCount => _rooms.where((r) => r.participantCount > 0).length;
  int get _recordingCount => _rooms.where((r) => r.isRecording).length;

  @override
  void initState() {
    super.initState();
    AccountController.instance.addListener(_onAccountChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initLoad();
      }
    });
  }

  @override
  void dispose() {
    AccountController.instance.removeListener(_onAccountChanged);
    super.dispose();
  }

  void _onAccountChanged() {
    if (!mounted) return;
    _loadAthleteProfile();
    final currentOrgId = AccountController.instance.activeOrgId;
    setState(() {});
    if (!_loading && currentOrgId != _loadedOrgId) {
      _load(showSpinner: true);
    }
  }

  Future<void> _initLoad() async {
    if (!AccountController.instance.hasLoaded) {
      await AccountController.instance.refresh();
    }
    await _loadAthleteProfile();
    await _load();
  }

  Future<void> _loadAthleteProfile() async {
    final profile = await AthleteProfile.load();
    if (!mounted) return;
    setState(() => _athleteProfile = profile);
  }

  Future<void> _editAthleteProfile() async {
    final updated = await showAthleteProfileSheet(
      context,
      initialProfile: _athleteProfile,
    );
    if (updated != null && mounted) {
      setState(() => _athleteProfile = updated);
    }
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final orgId = AccountController.instance.activeOrgId;
      _loadedOrgId = orgId;
      final futures = <Future<dynamic>>[
        ApiService.getRooms(),
        if (orgId != null && orgId.isNotEmpty)
          ApiService.instance.fetchOrgSessions(orgId),
      ];
      final results = await Future.wait(futures);
      if (!mounted) return;
      setState(() {
        _rooms = results[0] as List<MobileRoom>;
        _orgSessions = results.length > 1
            ? results[1] as List<OrgSession>
            : const [];
        _error = null;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await AuthService.instance.signOut();
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de charger les sessions.';
        _loading = false;
      });
    }
  }

  Future<void> _openRoom(MobileRoom room) async {
    await context.push(
      '/connect/${Uri.encodeComponent(room.name)}',
      extra: room,
    );
    if (mounted) {
      unawaited(_load(showSpinner: false));
    }
  }

  Future<void> _openReplay(String orgId, String roomName) async {
    await context.push(
      '/sessions/${Uri.encodeComponent(orgId)}/${Uri.encodeComponent(roomName)}',
    );
  }

  Future<void> _createSession() async {
    final orgId = AccountController.instance.activeOrgId;
    if (orgId == null || orgId.isEmpty) return;

    final created = await showCreateSessionSheet(context, orgId: orgId);
    if (created == null || !mounted) return;

    await _load(showSpinner: false);
    if (!mounted) return;

    final joinNow = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Séance créée'),
        content: Text(
          '« ${created.displayTitle} » est prête. Voulez-vous rejoindre le flux en direct maintenant ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Rejoindre'),
          ),
        ],
      ),
    );

    if (joinNow == true && mounted) {
      await _openRoom(
        MobileRoom(
          name: created.roomName,
          title: created.title,
          orgId: created.orgId,
          participantCount: 0,
          recording: false,
          recordingStatus: 'not_started',
          canControlRecording: AccountController.instance.canManageSessions,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = AccountController.instance;
    final activeMembership = account.activeMembership;
    final canCreate = account.canManageSessions && account.activeOrgId != null;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
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
                    Text(
                      'Sessions sportives',
                      style: UIUtils.titleMedium(context),
                    ),
                    if (activeMembership != null)
                      Text(
                        '${activeMembership.displayOrgName} • ${activeMembership.roleLabel}'
                        '${AppConfig.isLocal ? ' • LOCAL' : ''}',
                        style: UIUtils.bodySmall(context).copyWith(
                          color: AppConfig.isLocal
                              ? LKColors.warning
                              : LKColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      Text(
                        AppConfig.isLocal
                            ? 'LOCAL · ${AppConfig.apiBaseUrl}'
                            : 'Coaching en direct',
                        style: UIUtils.bodySmall(context).copyWith(
                          color: AppConfig.isLocal
                              ? LKColors.warning
                              : LKColors.textHint,
                          fontSize: 11,
                          fontWeight: AppConfig.isLocal
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
                elevation: 0,
                shadowColor: Colors.transparent,
                actions: [
                  IconButton(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    tooltip: 'Mes clubs, coachs & invitations',
                    icon: UIUtils.textPrimaryIcon(
                      Icons.apartment_rounded,
                      size: 22,
                    ),
                    onPressed: () => showOrganizationHubSheet(
                      context,
                      onChanged: () {
                        if (mounted) {
                          _load(showSpinner: false);
                        }
                      },
                    ),
                  ),
                  IconButton(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: _editAthleteProfile,
                    icon: UIUtils.textPrimaryIcon(
                      Icons.monitor_heart_outlined,
                      size: 24,
                    ),
                    tooltip: 'Profil sportif & santé',
                  ),
                  IconButton(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: _loading ? null : () => _load(showSpinner: false),
                    icon: UIUtils.textPrimaryIcon(Icons.refresh_rounded, size: 24),
                    tooltip: 'Actualiser',
                  ),
                  IconButton(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: () async {
                      final confirmed = await context.showSignOutDialog();
                      if (confirmed == true) {
                        await AuthService.instance.signOut();
                      }
                    },
                    icon: UIUtils.textPrimaryIcon(Icons.logout_rounded, size: 24),
                    tooltip: 'Se déconnecter',
                  ),
                  SizedBox(width: UIUtils.xs),
                ],
                bottom: const TabBar(
                  indicatorColor: LKColors.primary,
                  labelColor: LKColors.primary,
                  unselectedLabelColor: LKColors.textSecondary,
                  tabs: [
                    Tab(text: 'En direct'),
                    Tab(text: 'Séances & Relecture'),
                  ],
                ),
              ),
        floatingActionButton: canCreate
            ? FloatingActionButton.extended(
                onPressed: _createSession,
                backgroundColor: LKColors.primary,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Nouvelle séance'),
              )
            : null,
        body: SafeArea(
          child: Column(
            children: [
              if (widget.embeddedInShell)
                Container(
                  decoration: const BoxDecoration(
                    color: LKColors.surfaceElevated,
                    border: Border(
                      bottom: BorderSide(color: LKColors.border, width: 0.8),
                    ),
                  ),
                  child: const TabBar(
                    indicatorColor: LKColors.primary,
                    labelColor: LKColors.primary,
                    unselectedLabelColor: LKColors.textSecondary,
                    tabs: [
                      Tab(text: 'En direct'),
                      Tab(text: 'Séances & Relecture'),
                    ],
                  ),
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    RefreshIndicator(
                      color: LKColors.primary,
                      onRefresh: () => _load(showSpinner: false),
                      child: _buildLiveTab(context),
                    ),
                    RefreshIndicator(
                      color: LKColors.primary,
                      onRefresh: () => _load(showSpinner: false),
                      child: _buildOrgSessionsTab(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveTab(BuildContext context) {
    if (_loading) {
      return const RoomsListSkeleton();
    }

    if (_error != null) {
      return _buildMessageState(
        context,
        icon: Icons.cloud_off_rounded,
        title: 'Sessions indisponibles',
        message: _error!,
        actionLabel: 'Réessayer',
        onAction: _load,
      );
    }

    if (_rooms.isEmpty) {
      return _buildMessageState(
        context,
        icon: Icons.videocam_off_rounded,
        title: 'Aucune session en cours',
        message:
            'Aucune room active n\'est ouverte pour votre compte actuellement. '
            'Consultez l\'onglet Relecture ou créez une séance.',
        actionLabel: 'Actualiser',
        onAction: _load,
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        UIUtils.lg,
        UIUtils.md,
        UIUtils.lg,
        UIUtils.xxl + 64,
      ),
      itemCount: _rooms.length + 1,
      separatorBuilder: (_, _) => SizedBox(height: UIUtils.md),
      itemBuilder: (context, index) {
        if (index == 0) return _buildHeader(context);
        return _buildRoomCard(context, _rooms[index - 1]);
      },
    );
  }

  Widget _buildOrgSessionsTab(BuildContext context) {
    if (_loading) {
      return const RoomsListSkeleton();
    }

    final orgId = AccountController.instance.activeOrgId;
    if (orgId == null || orgId.isEmpty) {
      return _buildMessageState(
        context,
        icon: Icons.apartment_rounded,
        title: 'Aucune organisation active',
        message: 'Finalisez votre onboarding ou acceptez une invitation.',
        actionLabel: 'Actualiser',
        onAction: _load,
      );
    }

    if (_orgSessions.isEmpty) {
      return _buildMessageState(
        context,
        icon: Icons.video_library_outlined,
        title: 'Aucune séance enregistrée',
        message:
            'Les séances créées dans votre organisation apparaîtront ici avec leur vidéo, télémétrie et marqueurs.',
        actionLabel: 'Actualiser',
        onAction: _load,
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        UIUtils.lg,
        UIUtils.md,
        UIUtils.lg,
        UIUtils.xxl + 64,
      ),
      itemCount: _orgSessions.length,
      separatorBuilder: (_, _) => SizedBox(height: UIUtils.md),
      itemBuilder: (context, index) =>
          _buildOrgSessionCard(context, orgId, _orgSessions[index]),
    );
  }

  Widget _buildOrgSessionCard(
    BuildContext context,
    String orgId,
    OrgSession session,
  ) {
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
          onTap: () => _openReplay(orgId, session.roomName),
        ),
      ),
    );
  }

  Widget _buildMessageState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
    required String actionLabel,
    required Future<void> Function() onAction,
  }) {
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

  Widget _buildHeader(BuildContext context) {
    final account = AccountController.instance;
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
                      'Bonjour ${account.displayName}',
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
                      onTap: _editAthleteProfile,
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
                                _athleteProfile.healthConsentGranted
                                    ? '${_athleteProfile.sport} • ${_athleteProfile.weightKg.toStringAsFixed(0)} kg • FCmax ${_athleteProfile.maxHeartRate} bpm'
                                    : '${_athleteProfile.sport} • ${_athleteProfile.effectiveAgeYears} ans • Seuils défaut',
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
                  value: '${_rooms.length}',
                  label: 'session${_rooms.length > 1 ? 's' : ''}',
                  color: LKColors.textPrimary,
                ),
                _buildStatDivider(),
                _buildStat(
                  context,
                  value: '$_liveCount',
                  label: 'en direct',
                  color: LKColors.success,
                ),
                if (_recordingCount > 0) ...[
                  _buildStatDivider(),
                  _buildStat(
                    context,
                    value: '$_recordingCount',
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

  Widget _buildRoomCard(BuildContext context, MobileRoom room) {
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
          onTap: () => _openRoom(room),
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
                          onPressed: () => _openRoom(room),
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
                    if ((room.orgId ?? AccountController.instance.activeOrgId) !=
                        null) ...[
                      SizedBox(width: UIUtils.sm),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => _openReplay(
                            room.orgId ??
                                AccountController.instance.activeOrgId!,
                            room.name,
                          ),
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
      padding: EdgeInsets.symmetric(horizontal: emphasize ? 9 : 8, vertical: 4),
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
