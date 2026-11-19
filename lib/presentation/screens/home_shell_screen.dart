import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_config.dart';
import '../../core/account_controller.dart';
import '../../core/api_service.dart';
import '../../core/auth_service.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';
import '../widgets/account_settings_sheet.dart';
import '../widgets/notifications_sheet.dart';
import '../widgets/organization_hub_sheet.dart';
import 'activities_screen.dart';
import 'athlete_home_screen.dart';
import 'calendar_screen.dart';
import 'rooms_screen.dart';

/// Conteneur principal post-authentification avec barre de navigation
/// adaptative (`NavigationBar` sur mobile, `NavigationRail` dès 600dp),
/// en-tête global unifié et montage paresseux des onglets.
class HomeShellScreen extends StatefulWidget {
  const HomeShellScreen({
    this.initialIndex = 0,
    this.apiService,
    this.accountController,
    this.authService,
    this.now,
    this.tabsOverride,
    super.key,
  });

  final int initialIndex;
  final ApiService? apiService;
  final AccountController? accountController;
  final AuthService? authService;
  final DateTime? now;

  /// Permet d'injecter des vues légères dans les tests de shell.
  final List<Widget>? tabsOverride;

  @override
  State<HomeShellScreen> createState() => _HomeShellScreenState();
}

class _HomeShellScreenState extends State<HomeShellScreen>
    with WidgetsBindingObserver {
  static const List<String> _tabTitles = [
    'Accueil',
    'Aujourd\'hui',
    'Activités',
    'Vidéo',
  ];

  late int _currentIndex = widget.initialIndex.clamp(0, 3);
  late final Set<int> _visitedTabs = <int>{_currentIndex};
  int _unreadNotifications = 0;
  int _pendingInvitationsCount = 0;

  ApiService get _api => widget.apiService ?? ApiService.instance;
  AccountController get _account =>
      widget.accountController ?? AccountController.instance;
  AuthService get _auth => widget.authService ?? AuthService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _account.addListener(_onAccountChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_refreshHeaderBadges());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _account.removeListener(_onAccountChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_refreshHeaderBadges());
    }
  }

  void _onAccountChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _refreshHeaderBadges() async {
    if (!_account.hasLoaded) {
      try {
        await _account.refresh();
      } catch (_) {}
    }
    try {
      final resp = await _api.fetchNotifications();
      if (mounted) {
        setState(() => _unreadNotifications = resp.unreadCount);
      }
      // Si une demande d'adhésion vient d'être approuvée pour une org absente
      // des memberships locaux, on rafraîchit immédiatement /v1/me.
      final hadNoOrgs = _account.memberships.isEmpty;
      final approvedNotifs = resp.items.where(
        (n) =>
            !n.read &&
            n.type == 'join_request_approved' &&
            n.orgId != null &&
            n.orgId!.trim().isNotEmpty &&
            !_account.memberships.any((m) => m.orgId == n.orgId!.trim()),
      );
      if (approvedNotifs.isNotEmpty) {
        final targetOrgId = approvedNotifs.first.orgId!.trim();
        await _account.refresh(syncAthleteProfile: false);
        if (hadNoOrgs && _account.memberships.any((m) => m.orgId == targetOrgId)) {
          await _account.selectOrganization(targetOrgId);
        }
        if (mounted) {
          UIUtils.showSnackBar(
            context,
            approvedNotifs.first.body.trim().isNotEmpty
                ? approvedNotifs.first.body.trim()
                : 'Votre demande d\'adhésion a été acceptée !',
            tone: AppSnackBarTone.success,
          );
        }
      }
    } catch (_) {}
    try {
      final invs = await _api.fetchMyInvitations();
      if (mounted) {
        setState(() => _pendingInvitationsCount = invs.length);
      }
    } catch (_) {}
  }

  void _selectTab(int index) {
    final clamped = index.clamp(0, 3);
    if (_currentIndex == clamped && _visitedTabs.contains(clamped)) return;
    setState(() {
      _currentIndex = clamped;
      _visitedTabs.add(clamped);
    });
  }

  Future<void> _openOrgHub() async {
    await showOrganizationHubSheet(
      context,
      apiService: _api,
      accountController: _account,
      onChanged: () {
        if (mounted) {
          unawaited(_refreshHeaderBadges());
        }
      },
    );
    if (mounted) {
      unawaited(_refreshHeaderBadges());
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
      onOpenCalendarTab: () => _selectTab(1),
    );
  }

  Future<void> _openAccountSheet() async {
    await showAccountSettingsSheet(
      context,
      apiService: _api,
      accountController: _account,
      authService: _auth,
      pendingInvitationsCount: _pendingInvitationsCount,
      onChanged: () {
        if (mounted) {
          unawaited(_refreshHeaderBadges());
        }
      },
    );
  }

  Widget _buildTabAt(int index) {
    if (!_visitedTabs.contains(index)) {
      return const SizedBox.shrink();
    }
    final override = widget.tabsOverride;
    if (override != null && index < override.length) {
      return override[index];
    }
    switch (index) {
      case 0:
        return AthleteHomeScreen(
          apiService: widget.apiService,
          accountController: widget.accountController,
          now: widget.now,
          embeddedInShell: true,
          onSelectTab: _selectTab,
        );
      case 1:
        return CalendarScreen(
          apiService: widget.apiService,
          accountController: widget.accountController,
          now: widget.now,
          embeddedInShell: true,
        );
      case 2:
        return ActivitiesScreen(
          apiService: widget.apiService,
          accountController: widget.accountController,
          embeddedInShell: true,
        );
      case 3:
      default:
        return const RoomsScreen(embeddedInShell: true);
    }
  }

  String _accountInitials() {
    final meUser = _account.me?.user;
    final name = meUser?.fullName.trim().isNotEmpty == true
        ? meUser!.fullName.trim()
        : _auth.displayName.trim();
    final source = name.isNotEmpty ? name : (_auth.email ?? '').trim();
    if (source.isEmpty) return 'VL';
    final parts = source
        .split(RegExp(r'[\s@._-]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return source.substring(0, source.length >= 2 ? 2 : 1).toUpperCase();
  }

  PreferredSizeWidget _buildUnifiedAppBar(BuildContext context) {
    final activeMembership = _account.activeMembership;
    final orgLabel = activeMembership?.displayOrgName ?? 'Mes clubs';

    return AppBar(
      backgroundColor: LKColors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      foregroundColor: LKColors.textPrimary,
      toolbarHeight: 64,
      titleSpacing: 16,
      title: Row(
        children: [
          Flexible(
            child: Text(
              _tabTitles[_currentIndex],
              style: UIUtils.titleMedium(context),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (AppConfig.isLocal) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: LKColors.warning.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: LKColors.warning.withValues(alpha: 0.45),
                ),
              ),
              child: const Text(
                'LOCAL',
                style: TextStyle(
                  color: LKColors.warning,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        // 1. Pillule Organisation cliquable (>= 48dp de hauteur tactile)
        Semantics(
          button: true,
          label: 'Organisation active : $orgLabel. Changer ou gérer les clubs.',
          child: InkWell(
            onTap: _openOrgHub,
            borderRadius: BorderRadius.circular(999),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: 48,
                maxWidth: 168,
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: LKColors.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: LKColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.apartment_rounded,
                        size: 14,
                        color: LKColors.primary,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          orgLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: UIUtils.bodySmall(context).copyWith(
                            color: LKColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_pendingInvitationsCount > 0) ...[
                        const SizedBox(width: 5),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: LKColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ] else ...[
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 15,
                          color: LKColors.textSecondary,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // 2. Cloche de notifications avec badge
        IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: _unreadNotifications > 0
              ? 'Notifications ($_unreadNotifications non lues)'
              : 'Notifications',
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
        // 3. Avatar / Menu Compte & Réglages
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Semantics(
            button: true,
            label: 'Compte, seuils et réglages',
            child: Tooltip(
              message: 'Compte & Réglages',
              child: InkWell(
                onTap: _openAccountSheet,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: LKColors.primary.withValues(alpha: 0.18),
                      child: Text(
                        _accountInitials(),
                        style: const TextStyle(
                          color: LKColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(0.8),
        child: Divider(height: 0.8, thickness: 0.8, color: LKColors.border),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabContent = IndexedStack(
      index: _currentIndex,
      children: List<Widget>.generate(4, (index) {
        return AnimatedOpacity(
          opacity: _currentIndex == index ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: _buildTabAt(index),
        );
      }),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final useRail = screenWidth >= 600;
        final extendedRail = screenWidth >= 840;

        return Scaffold(
          backgroundColor: LKColors.background,
          appBar: _buildUnifiedAppBar(context),
          body: useRail
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _currentIndex,
                      extended: extendedRail,
                      backgroundColor: LKColors.surfaceElevated,
                      indicatorColor: LKColors.primary.withValues(alpha: 0.18),
                      labelType: extendedRail
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      selectedLabelTextStyle: const TextStyle(
                        color: LKColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      unselectedLabelTextStyle: const TextStyle(
                        color: LKColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      onDestinationSelected: _selectTab,
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(
                            Icons.home_rounded,
                            color: LKColors.primary,
                          ),
                          label: Text('Accueil'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.today_outlined),
                          selectedIcon: Icon(
                            Icons.today_rounded,
                            color: LKColors.primary,
                          ),
                          label: Text('Aujourd\'hui'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.directions_bike_outlined),
                          selectedIcon: Icon(
                            Icons.directions_bike_rounded,
                            color: LKColors.primary,
                          ),
                          label: Text('Activités'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.videocam_outlined),
                          selectedIcon: Icon(
                            Icons.videocam_rounded,
                            color: LKColors.primary,
                          ),
                          label: Text('Vidéo'),
                        ),
                      ],
                    ),
                    const VerticalDivider(
                      width: 1,
                      thickness: 0.8,
                      color: LKColors.border,
                    ),
                    Expanded(child: tabContent),
                  ],
                )
              : tabContent,
          bottomNavigationBar: useRail
              ? null
              : Container(
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: LKColors.border, width: 0.8),
                    ),
                  ),
                  child: NavigationBar(
                    selectedIndex: _currentIndex,
                    backgroundColor: LKColors.surfaceElevated,
                    indicatorColor: LKColors.primary.withValues(alpha: 0.18),
                    onDestinationSelected: _selectTab,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(
                          Icons.home_rounded,
                          color: LKColors.primary,
                        ),
                        label: 'Accueil',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.today_outlined),
                        selectedIcon: Icon(
                          Icons.today_rounded,
                          color: LKColors.primary,
                        ),
                        label: 'Aujourd\'hui',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.directions_bike_outlined),
                        selectedIcon: Icon(
                          Icons.directions_bike_rounded,
                          color: LKColors.primary,
                        ),
                        label: 'Activités',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.videocam_outlined),
                        selectedIcon: Icon(
                          Icons.videocam_rounded,
                          color: LKColors.primary,
                        ),
                        label: 'Vidéo',
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
