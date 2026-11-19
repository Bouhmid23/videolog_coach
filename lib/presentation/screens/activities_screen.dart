import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app_config.dart';
import '../../core/account_controller.dart';
import '../../core/api_service.dart';
import '../../core/auth_service.dart';
import '../../data/activity_models.dart';
import '../../data/training_models.dart';
import '../../exts.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';
import '../widgets/athlete_profile_sheet.dart';
import '../widgets/shimmer_skeleton.dart';

typedef ActivityFilePickHandler = Future<({String? path, Uint8List? bytes, String name})?> Function();

class ActivitiesScreen extends StatefulWidget {
  const ActivitiesScreen({
    this.apiService,
    this.accountController,
    this.onPickFile,
    this.embeddedInShell = false,
    super.key,
  });

  final ApiService? apiService;
  final AccountController? accountController;
  final ActivityFilePickHandler? onPickFile;
  final bool embeddedInShell;

  @override
  State<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends State<ActivitiesScreen> {
  List<ActivitySummary> _activities = const [];
  bool _loading = true;
  bool _uploading = false;
  String? _error;
  String? _loadedOrgId;

  ApiService get _api => widget.apiService ?? ApiService.instance;
  AccountController get _account =>
      widget.accountController ?? AccountController.instance;

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
    if (!_loading && (currentOrgId != _loadedOrgId || _activities.isEmpty)) {
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
          _activities = const [];
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

    try {
      final list = await _api.fetchActivities(
        orgId,
        uid: _account.uid.isNotEmpty ? _account.uid : null,
      );
      if (!mounted) return;
      setState(() {
        _activities = list;
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
        _error = 'Impossible de charger vos activités.';
        _loading = false;
      });
    }
  }

  Future<void> _importActivity() async {
    final orgId = _account.activeOrgId;
    if (orgId == null || orgId.isEmpty || _uploading) return;

    ({String? path, Uint8List? bytes, String name})? picked;
    if (widget.onPickFile != null) {
      picked = await widget.onPickFile!();
    } else {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Importer une activité (.fit, .gpx, .tcx)',
        type: FileType.custom,
        allowedExtensions: const ['fit', 'gpx', 'tcx'],
      );
      if (file != null) {
        final path = file.path;
        final bytes = path == null ? await file.readAsBytes() : null;
        picked = (path: path, bytes: bytes, name: file.name);
      }
    }

    if (picked == null) return;
    if (picked.path == null && picked.bytes == null) {
      _showSnack('Fichier illisible.', isError: true);
      return;
    }

    setState(() => _uploading = true);
    try {
      final created = await _api.uploadActivityFile(
        orgId,
        filePath: picked.path,
        fileBytes: picked.path == null ? picked.bytes : null,
        filename: picked.name,
      );
      if (!mounted) return;
      await _load(showSpinner: false);
      if (!mounted) return;
      _showSnack('Activité importée avec succès.');
      final newId = (created['id'] ?? created['activity_id'])?.toString();
      if (newId != null && newId.isNotEmpty) {
        context.push(
          '/activities/${Uri.encodeComponent(orgId)}/${Uri.encodeComponent(newId)}',
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      _showSnack(
        e.isConflict ? 'Doublon détecté : ${e.message}' : e.message,
        isError: true,
      );
    } catch (_) {
      if (!mounted) return;
      _showSnack('Échec de l\'importation du fichier.', isError: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? LKColors.danger : LKColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeMembership = _account.activeMembership;
    final orgId = _account.activeOrgId;

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
            Text('Activités', style: UIUtils.titleMedium(context)),
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
                    : 'Journal & Imports (.fit / .gpx / .tcx)',
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
              onSelected: (id) async {
                await _account.selectOrganization(id);
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
      floatingActionButton: (orgId != null && orgId.isNotEmpty)
          ? FloatingActionButton.extended(
              onPressed: _uploading ? null : _importActivity,
              backgroundColor: LKColors.primary,
              foregroundColor: Colors.white,
              icon: _uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.upload_file_rounded),
              label: Text(_uploading ? 'Import...' : 'Importer FIT / GPX'),
            )
          : null,
      body: SafeArea(
        child: RefreshIndicator(
          color: LKColors.primary,
          onRefresh: () => _load(showSpinner: false),
          child: _buildBody(context, orgId),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, String? orgId) {
    if (orgId == null || orgId.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: UIUtils.paddingXL,
        children: [
          SizedBox(height: UIUtils.xxxl),
          const Icon(Icons.apartment_rounded, size: 48, color: LKColors.textHint),
          SizedBox(height: UIUtils.md),
          Text(
            'Aucune organisation active',
            textAlign: TextAlign.center,
            style: UIUtils.titleMedium(context),
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
          const Icon(Icons.cloud_off_rounded, size: 48, color: LKColors.danger),
          SizedBox(height: UIUtils.md),
          Text(
            'Activités indisponibles',
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

    if (_activities.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: UIUtils.paddingXL,
        children: [
          SizedBox(height: UIUtils.xxxl),
          const Icon(
            Icons.directions_bike_rounded,
            size: 48,
            color: LKColors.textHint,
          ),
          SizedBox(height: UIUtils.md),
          Text(
            'Aucune activité enregistrée',
            textAlign: TextAlign.center,
            style: UIUtils.titleMedium(context),
          ),
          SizedBox(height: UIUtils.xs),
          Text(
            'Importez un fichier .fit, .gpx ou .tcx depuis votre téléphone pour analyser vos métriques.',
            textAlign: TextAlign.center,
            style: UIUtils.bodySmall(context),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        UIUtils.lg,
        UIUtils.md,
        UIUtils.lg,
        UIUtils.xxl + 72,
      ),
      itemCount: _activities.length,
      separatorBuilder: (_, _) => SizedBox(height: UIUtils.md),
      itemBuilder: (context, index) {
        final activity = _activities[index];
        return _ActivityCard(
          activity: activity,
          onTap: () => context.push(
            '/activities/${Uri.encodeComponent(orgId)}/${Uri.encodeComponent(activity.id)}',
          ),
        );
      },
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.activity,
    required this.onTap,
  });

  final ActivitySummary activity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy · HH:mm');
    final metrics = <String>[
      if (activity.durationS != null) formatDurationSeconds(activity.durationS),
      if (activity.distanceM != null && activity.distanceM! > 0)
        '${(activity.distanceM! / 1000).toStringAsFixed(1)} km',
      if (activity.tss != null) '${activity.tss!.round()} pts d\'effort',
      if (activity.avgHr != null) '${activity.avgHr} bpm',
      if (activity.elevationGainM != null && activity.elevationGainM! > 0)
        '${activity.elevationGainM!.round()} m D+',
    ];

    return InkWell(
      borderRadius: UIUtils.borderRadiusAllLG,
      onTap: onTap,
      child: Container(
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
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: LKColors.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    activity.sport.toUpperCase(),
                    style: UIUtils.bodySmall(context).copyWith(
                      color: LKColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (activity.isMatched) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: LKColors.success.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Appariée',
                      style: UIUtils.bodySmall(context).copyWith(
                        color: LKColors.success,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (activity.startedAt != null)
                  Text(
                    dateFmt.format(activity.startedAt!.toLocal()),
                    style: UIUtils.bodySmall(context).copyWith(fontSize: 11),
                  ),
              ],
            ),
            SizedBox(height: UIUtils.sm),
            Text(activity.title, style: UIUtils.titleMedium(context)),
            if (metrics.isNotEmpty) ...[
              SizedBox(height: UIUtils.xs),
              Text(
                metrics.join(' · '),
                style: UIUtils.bodySmall(context).copyWith(
                  color: LKColors.textSecondary,
                ),
              ),
            ],
            if (activity.rpe != null) ...[
              SizedBox(height: UIUtils.xs),
              Text(
                'RPE ${activity.rpe}/10'
                '${activity.feeling != null ? ' · Ressenti ${activity.feeling}/5' : ''}',
                style: UIUtils.bodySmall(context).copyWith(
                  color: LKColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
