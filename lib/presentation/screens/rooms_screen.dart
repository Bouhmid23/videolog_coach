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
import '../widgets/rooms/rooms_cards.dart';
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
                    icon: UIUtils.textPrimaryIcon(
                      Icons.refresh_rounded,
                      size: 24,
                    ),
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
                    icon: UIUtils.textPrimaryIcon(
                      Icons.logout_rounded,
                      size: 24,
                    ),
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
      return RoomsMessageState(
        icon: Icons.cloud_off_rounded,
        title: 'Sessions indisponibles',
        message: _error!,
        actionLabel: 'Réessayer',
        onAction: _load,
      );
    }

    if (_rooms.isEmpty) {
      return RoomsMessageState(
        icon: Icons.videocam_off_rounded,
        title: 'Aucune session en cours',
        message:
            'Aucune room active n\'est ouverte pour votre compte actuellement. '
            'Consultez l\'onglet Relecture ou créez une séance.',
        actionLabel: 'Actualiser',
        onAction: _load,
      );
    }

    final account = AccountController.instance;
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
        if (index == 0) {
          return RoomsHeaderCard(
            displayName: account.displayName,
            athleteProfile: _athleteProfile,
            roomsCount: _rooms.length,
            liveCount: _liveCount,
            recordingCount: _recordingCount,
            onEditAthleteProfile: _editAthleteProfile,
          );
        }
        final room = _rooms[index - 1];
        final effectiveOrgId = room.orgId ?? account.activeOrgId;
        return MobileRoomCard(
          room: room,
          effectiveOrgId: effectiveOrgId,
          onJoin: () => _openRoom(room),
          onOpenReplay: effectiveOrgId != null
              ? () => _openReplay(effectiveOrgId, room.name)
              : null,
        );
      },
    );
  }

  Widget _buildOrgSessionsTab(BuildContext context) {
    if (_loading) {
      return const RoomsListSkeleton();
    }

    final orgId = AccountController.instance.activeOrgId;
    if (orgId == null || orgId.isEmpty) {
      return RoomsMessageState(
        icon: Icons.apartment_rounded,
        title: 'Aucune organisation active',
        message: 'Finalisez votre onboarding ou acceptez une invitation.',
        actionLabel: 'Actualiser',
        onAction: _load,
      );
    }

    if (_orgSessions.isEmpty) {
      return RoomsMessageState(
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
      itemBuilder: (context, index) {
        final session = _orgSessions[index];
        return OrgSessionCard(
          session: session,
          onTap: () => _openReplay(orgId, session.roomName),
        );
      },
    );
  }
}
