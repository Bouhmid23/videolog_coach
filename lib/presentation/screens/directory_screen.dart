import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/account_controller.dart';
import '../../core/api_service.dart';
import '../../core/auth_service.dart';
import '../../data/directory_models.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';
import '../widgets/directory/directory_widgets.dart';
import 'directory_organization_detail_screen.dart';

/// Annuaire public des clubs/coachs (`/directory`) et suivi des demandes
/// d'adhésion (`/directory?tab=requests`).
class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({
    this.initialTabIndex = 0,
    this.apiService,
    this.accountController,
    this.authService,
    this.emailVerifiedOverride,
    super.key,
  });

  final int initialTabIndex;
  final ApiService? apiService;
  final AccountController? accountController;
  final AuthService? authService;
  final bool? emailVerifiedOverride;

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen>
    with SingleTickerProviderStateMixin {
  static const int _pageSize = 20;

  late final TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  // Référentiel des sports (/v1/sports)
  List<SportMeta> _sportsCatalog = const [];

  // Filtres Explorer
  String? _selectedType; // null | 'club' | 'solo_coach'
  String? _selectedSportCode;
  bool _indoorOnly = false;
  bool _acceptingOnly = false;
  String _cityFilter = '';
  String _searchQuery = '';

  // État liste Explorer
  List<DirectoryOrganization> _organizations = const [];
  int _total = 0;
  bool _loadingOrgs = true;
  bool _loadingMore = false;
  String? _orgsError;
  int _orgsRequestSeq = 0;

  // État onglet Mes demandes
  String? _requestsStatusFilter; // null | pending | approved | rejected | cancelled
  List<MyJoinRequest> _joinRequests = const [];
  bool _loadingRequests = true;
  String? _requestsError;
  String? _cancellingRequestId;

  ApiService get _api => widget.apiService ?? ApiService.instance;
  AccountController get _account =>
      widget.accountController ?? AccountController.instance;
  AuthService get _auth => widget.authService ?? AuthService.instance;

  bool get _hasActiveFilters =>
      _selectedType != null ||
      _selectedSportCode != null ||
      _indoorOnly ||
      _acceptingOnly ||
      _cityFilter.trim().isNotEmpty ||
      _searchQuery.trim().isNotEmpty;

  int get _pendingRequestsCount =>
      _joinRequests.where((r) => r.isPending).length;

  bool get _hasMore => _organizations.length < _total;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    _scrollController.addListener(_onScroll);
    unawaited(_loadSportsCatalog());
    unawaited(_loadOrganizations(reset: true));
    unawaited(_loadMyJoinRequests());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingOrgs || _loadingMore || !_hasMore) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      unawaited(_loadOrganizations(reset: false));
    }
  }

  Future<void> _loadSportsCatalog() async {
    try {
      final list = await _api.fetchSports();
      if (!mounted) return;
      setState(() => _sportsCatalog = list);
    } catch (_) {
      // Silencieux : l'annuaire reste utilisable même si /v1/sports échoue.
    }
  }

  Future<void> _loadOrganizations({required bool reset}) async {
    final seq = ++_orgsRequestSeq;
    final nextOffset = reset ? 0 : _organizations.length;

    setState(() {
      if (reset) {
        _loadingOrgs = true;
        _orgsError = null;
      } else {
        _loadingMore = true;
      }
    });

    try {
      final page = await _api.searchDirectoryOrganizations(
        type: _selectedType,
        sport: _selectedSportCode,
        indoorOnly: _indoorOnly,
        city: _cityFilter.trim().isEmpty ? null : _cityFilter.trim(),
        q: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
        acceptingOnly: _acceptingOnly,
        limit: _pageSize,
        offset: nextOffset,
      );
      if (!mounted || seq != _orgsRequestSeq) return;
      setState(() {
        if (reset) {
          _organizations = page.organizations;
        } else {
          final existingIds = _organizations.map((o) => o.id).toSet();
          _organizations = [
            ..._organizations,
            ...page.organizations.where((o) => !existingIds.contains(o.id)),
          ];
        }
        _total = page.total;
        _loadingOrgs = false;
        _loadingMore = false;
        _orgsError = null;
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _orgsRequestSeq) return;
      setState(() {
        _loadingOrgs = false;
        _loadingMore = false;
        if (reset) _orgsError = e.message;
      });
      if (!reset) {
        UIUtils.showSnackBar(context, e.message, tone: AppSnackBarTone.error);
      }
    } catch (_) {
      if (!mounted || seq != _orgsRequestSeq) return;
      setState(() {
        _loadingOrgs = false;
        _loadingMore = false;
        if (reset) {
          _orgsError = 'Impossible de charger l\'annuaire des clubs et coachs.';
        }
      });
    }
  }

  Future<void> _loadMyJoinRequests() async {
    setState(() {
      _loadingRequests = true;
      _requestsError = null;
    });
    try {
      final list = await _api.fetchMyJoinRequests(
        status: _requestsStatusFilter,
      );
      if (!mounted) return;
      setState(() {
        _joinRequests = list;
        _loadingRequests = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _requestsError = e.message;
        _loadingRequests = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _requestsError = 'Impossible de charger vos demandes d\'adhésion.';
        _loadingRequests = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (_searchQuery == value) return;
      setState(() => _searchQuery = value);
      unawaited(_loadOrganizations(reset: true));
    });
  }

  void _clearFilters() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    setState(() {
      _selectedType = null;
      _selectedSportCode = null;
      _indoorOnly = false;
      _acceptingOnly = false;
      _cityFilter = '';
      _searchQuery = '';
    });
    unawaited(_loadOrganizations(reset: true));
  }

  String _sportLabelFor(String code) {
    for (final s in _sportsCatalog) {
      if (s.code == code) return s.label;
    }
    return code;
  }

  Future<void> _openSportPicker() async {
    final picked = await showDirectorySportPickerSheet(
      context,
      sportsCatalog: _sportsCatalog,
      selectedSportCode: _selectedSportCode,
    );

    if (picked == null || !mounted) return;
    final nextCode = picked.isEmpty ? null : picked;
    if (nextCode == _selectedSportCode) return;
    setState(() => _selectedSportCode = nextCode);
    unawaited(_loadOrganizations(reset: true));
  }

  Future<void> _openCityDialog() async {
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => DirectoryCityFilterDialog(initialCity: _cityFilter),
    );
    if (result == null || !mounted) return;
    if (result == _cityFilter) return;
    setState(() => _cityFilter = result);
    unawaited(_loadOrganizations(reset: true));
  }

  Future<void> _openOrganizationDetail(
    String orgId, {
    DirectoryOrganization? initialOrg,
  }) async {
    final updated = await Navigator.of(context).push<DirectoryOrganization?>(
      MaterialPageRoute(
        builder: (_) => DirectoryOrganizationDetailScreen(
          orgId: orgId,
          initialOrganization: initialOrg,
          apiService: _api,
          accountController: _account,
          authService: _auth,
          emailVerifiedOverride: widget.emailVerifiedOverride,
        ),
      ),
    );
    if (!mounted) return;
    if (updated != null) {
      setState(() {
        _organizations = _organizations
            .map((o) => o.id == updated.id ? updated : o)
            .toList();
      });
    }
    unawaited(_loadMyJoinRequests());
  }

  Future<void> _cancelJoinRequest(MyJoinRequest req) async {
    if (_cancellingRequestId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LKColors.surfaceElevated,
        title: const Text('Annuler cette demande ?'),
        content: Text(
          'Votre demande d\'adhésion auprès de ${req.orgName} sera annulée.',
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

    setState(() => _cancellingRequestId = req.id);
    try {
      await _api.cancelJoinRequest(req.id);
      if (!mounted) return;
      setState(() {
        _joinRequests = _joinRequests
            .map((r) => r.id == req.id ? r.copyWith(status: 'cancelled') : r)
            .toList();
        _organizations = _organizations
            .map(
              (o) => o.id == req.orgId
                  ? o.copyWith(clearPendingRequestId: true)
                  : o,
            )
            .toList();
        _cancellingRequestId = null;
      });
      UIUtils.showSnackBar(
        context,
        'Demande d\'adhésion annulée.',
        tone: AppSnackBarTone.info,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _cancellingRequestId = null);
      UIUtils.showSnackBar(context, e.message, tone: AppSnackBarTone.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _cancellingRequestId = null);
      UIUtils.showSnackBar(
        context,
        'Impossible d\'annuler la demande pour le moment.',
        tone: AppSnackBarTone.error,
      );
    }
  }

  Future<void> _openApprovedOrganization(MyJoinRequest req) async {
    if (!_account.memberships.any((m) => m.orgId == req.orgId)) {
      await _account.refresh(syncAthleteProfile: false);
    }
    await _account.selectOrganization(req.orgId);
    if (!mounted) return;
    context.go('/rooms');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LKColors.background,
      appBar: AppBar(
        backgroundColor: LKColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Clubs & Coachs',
          style: UIUtils.titleMedium(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: LKColors.primary,
          labelColor: LKColors.primary,
          unselectedLabelColor: LKColors.textSecondary,
          dividerColor: LKColors.border,
          tabs: [
            const Tab(text: 'Explorer'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Mes demandes'),
                  if (_pendingRequestsCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: LKColors.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$_pendingRequestsCount',
                        style: const TextStyle(
                          color: LKColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildExplorerTab(context),
          _buildMyRequestsTab(context),
        ],
      ),
    );
  }

  Widget _buildExplorerTab(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => _loadOrganizations(reset: true),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  color: LKColors.surface,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _searchCtrl,
                        onChanged: _onSearchChanged,
                        textInputAction: TextInputAction.search,
                        decoration: UIUtils.inputDecoration(
                          hintText:
                              'Rechercher un club, un coach, un sport, une ville…',
                          prefixIcon: Icons.search_rounded,
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? Icons.close_rounded
                              : null,
                          suffixTooltip: 'Effacer la recherche',
                          onSuffixIconTap: () {
                            _searchCtrl.clear();
                            _searchDebounce?.cancel();
                            setState(() => _searchQuery = '');
                            unawaited(_loadOrganizations(reset: true));
                          },
                        ),
                      ),
                      SizedBox(height: UIUtils.sm),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 'all', label: Text('Tous')),
                          ButtonSegment(value: 'club', label: Text('Clubs')),
                          ButtonSegment(
                            value: 'solo_coach',
                            label: Text('Coachs'),
                          ),
                        ],
                        selected: {_selectedType ?? 'all'},
                        onSelectionChanged: (selection) {
                          final val = selection.first;
                          final next = val == 'all' ? null : val;
                          if (next == _selectedType) return;
                          setState(() => _selectedType = next);
                          unawaited(_loadOrganizations(reset: true));
                        },
                      ),
                      SizedBox(height: UIUtils.sm),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            FilterChip(
                              avatar: Icon(
                                Icons.home_outlined,
                                size: 16,
                                color: _indoorOnly
                                    ? LKColors.primary
                                    : LKColors.textSecondary,
                              ),
                              label: const Text('Indoor uniquement'),
                              selected: _indoorOnly,
                              selectedColor:
                                  LKColors.primary.withValues(alpha: 0.22),
                              checkmarkColor: LKColors.primary,
                              onSelected: (on) {
                                setState(() => _indoorOnly = on);
                                unawaited(_loadOrganizations(reset: true));
                              },
                            ),
                            const SizedBox(width: 8),
                            ActionChip(
                              avatar: Icon(
                                Icons.sports_rounded,
                                size: 16,
                                color: _selectedSportCode != null
                                    ? LKColors.primary
                                    : LKColors.textSecondary,
                              ),
                              label: Text(
                                _selectedSportCode != null
                                    ? _sportLabelFor(_selectedSportCode!)
                                    : 'Discipline',
                              ),
                              backgroundColor: _selectedSportCode != null
                                  ? LKColors.primary.withValues(alpha: 0.16)
                                  : LKColors.surfaceElevated,
                              side: BorderSide(
                                color: _selectedSportCode != null
                                    ? LKColors.primary.withValues(alpha: 0.5)
                                    : LKColors.border,
                              ),
                              onPressed: _openSportPicker,
                            ),
                            const SizedBox(width: 8),
                            ActionChip(
                              avatar: Icon(
                                Icons.location_city_rounded,
                                size: 16,
                                color: _cityFilter.isNotEmpty
                                    ? LKColors.primary
                                    : LKColors.textSecondary,
                              ),
                              label: Text(
                                _cityFilter.isNotEmpty ? _cityFilter : 'Ville',
                              ),
                              backgroundColor: _cityFilter.isNotEmpty
                                  ? LKColors.primary.withValues(alpha: 0.16)
                                  : LKColors.surfaceElevated,
                              side: BorderSide(
                                color: _cityFilter.isNotEmpty
                                    ? LKColors.primary.withValues(alpha: 0.5)
                                    : LKColors.border,
                              ),
                              onPressed: _openCityDialog,
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              label: const Text('Ouverts'),
                              selected: _acceptingOnly,
                              selectedColor:
                                  LKColors.primary.withValues(alpha: 0.22),
                              checkmarkColor: LKColors.primary,
                              onSelected: (on) {
                                setState(() => _acceptingOnly = on);
                                unawaited(_loadOrganizations(reset: true));
                              },
                            ),
                            if (_hasActiveFilters) ...[
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: _clearFilters,
                                icon: const Icon(
                                  Icons.filter_alt_off_rounded,
                                  size: 16,
                                ),
                                label: const Text('Réinitialiser'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: LKColors.border),
              ],
            ),
          ),
          _buildOrganizationsSliver(context),
        ],
      ),
    );
  }

  Widget _buildOrganizationsSliver(BuildContext context) {
    if (_loadingOrgs) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: UIUtils.paddingXL,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_orgsError != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: UIUtils.paddingXL,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 42,
                  color: LKColors.textHint,
                ),
                SizedBox(height: UIUtils.md),
                Text(
                  _orgsError!,
                  textAlign: TextAlign.center,
                  style: UIUtils.bodyMedium(context),
                ),
                SizedBox(height: UIUtils.md),
                FilledButton.icon(
                  onPressed: () => _loadOrganizations(reset: true),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_organizations.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: UIUtils.paddingXL,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.search_off_rounded,
                size: 46,
                color: LKColors.textHint,
              ),
              SizedBox(height: UIUtils.md),
              Text(
                'Aucun club ou coach trouvé',
                textAlign: TextAlign.center,
                style: UIUtils.titleMedium(context),
              ),
              SizedBox(height: UIUtils.xs),
              Text(
                _hasActiveFilters
                    ? 'Essayez d\'élargir vos filtres de recherche.'
                    : 'Aucun club ou coach public n\'est encore référencé.',
                textAlign: TextAlign.center,
                style: UIUtils.bodySmall(context),
              ),
              if (_hasActiveFilters) ...[
                SizedBox(height: UIUtils.lg),
                OutlinedButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                  label: const Text('Réinitialiser les filtres'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: UIUtils.paddingLG,
      sliver: SliverList.separated(
        itemCount: _organizations.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, _) => SizedBox(height: UIUtils.md),
        itemBuilder: (context, index) {
          if (index >= _organizations.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : OutlinedButton(
                        onPressed: () => _loadOrganizations(reset: false),
                        child: const Text('Charger plus'),
                      ),
              ),
            );
          }
          final org = _organizations[index];
          return DirectoryOrganizationCard(
            organization: org,
            onTap: () => _openOrganizationDetail(org.id, initialOrg: org),
          );
        },
      ),
    );
  }

  Widget _buildMyRequestsTab(BuildContext context) {
    final statusOptions = <(String?, String)>[
      (null, 'Toutes'),
      ('pending', 'En attente'),
      ('approved', 'Acceptées'),
      ('rejected', 'Refusées'),
      ('cancelled', 'Annulées'),
    ];

    return Column(
      children: [
        Container(
          color: LKColors.surface,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (code, label) in statusOptions) ...[
                  ChoiceChip(
                    label: Text(label),
                    selected: _requestsStatusFilter == code,
                    selectedColor: LKColors.primary.withValues(alpha: 0.22),
                    onSelected: (_) {
                      if (_requestsStatusFilter == code) return;
                      setState(() => _requestsStatusFilter = code);
                      unawaited(_loadMyJoinRequests());
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: LKColors.border),
        Expanded(child: _buildJoinRequestsBody(context)),
      ],
    );
  }

  Widget _buildJoinRequestsBody(BuildContext context) {
    if (_loadingRequests) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_requestsError != null) {
      return Center(
        child: Padding(
          padding: UIUtils.paddingXL,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _requestsError!,
                textAlign: TextAlign.center,
                style: UIUtils.bodyMedium(context),
              ),
              SizedBox(height: UIUtils.md),
              FilledButton.icon(
                onPressed: _loadMyJoinRequests,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }
    if (_joinRequests.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadMyJoinRequests,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: UIUtils.paddingXL,
          children: [
            SizedBox(height: UIUtils.xxxl),
            const Icon(
              Icons.inbox_outlined,
              size: 46,
              color: LKColors.textHint,
            ),
            SizedBox(height: UIUtils.md),
            Text(
              'Aucune demande d\'adhésion',
              textAlign: TextAlign.center,
              style: UIUtils.titleMedium(context),
            ),
            SizedBox(height: UIUtils.xs),
            Text(
              'Explorez l\'annuaire pour trouver un club ou un coach adapté à vos disciplines.',
              textAlign: TextAlign.center,
              style: UIUtils.bodySmall(context),
            ),
            SizedBox(height: UIUtils.lg),
            Center(
              child: FilledButton.icon(
                onPressed: () => _tabController.animateTo(0),
                icon: const Icon(Icons.explore_outlined, size: 18),
                label: const Text('Explorer les clubs & coachs'),
              ),
            ),
          ],
        ),
      );
    }

    final dateFmt = DateFormat('dd/MM/yyyy');
    return RefreshIndicator(
      onRefresh: _loadMyJoinRequests,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: UIUtils.paddingLG,
        itemCount: _joinRequests.length,
        separatorBuilder: (_, _) => SizedBox(height: UIUtils.md),
        itemBuilder: (context, index) {
          final req = _joinRequests[index];
          return DirectoryJoinRequestCard(
            request: req,
            dateFmt: dateFmt,
            cancelling: _cancellingRequestId == req.id,
            sportLabelFor: _sportLabelFor,
            onOpenOrganizationDetail: () => _openOrganizationDetail(req.orgId),
            onCancelRequest: () => _cancelJoinRequest(req),
            onOpenApprovedOrganization: () => _openApprovedOrganization(req),
          );
        },
      ),
    );
  }
}
