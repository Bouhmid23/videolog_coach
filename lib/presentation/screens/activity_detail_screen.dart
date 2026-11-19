import 'package:firebase_core/firebase_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/account_controller.dart';
import '../../core/api_service.dart';
import '../../data/account_models.dart';
import '../../data/activity_models.dart';
import '../../data/training_models.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

enum _StreamMetric { hr, power, speed, altitude }

class ActivityDetailScreen extends StatefulWidget {
  const ActivityDetailScreen({
    required this.orgId,
    required this.activityId,
    this.apiService,
    this.accountController,
    super.key,
  });

  final String orgId;
  final String activityId;
  final ApiService? apiService;
  final AccountController? accountController;

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  ActivityDetail? _detail;
  ActivityStreams _streams = const ActivityStreams();
  List<ActivityComment> _comments = const [];

  bool _loading = true;
  String? _error;

  _StreamMetric _selectedMetric = _StreamMetric.hr;

  int _rpe = 6;
  int _feeling = 4;
  bool _savingFeedback = false;

  Set<String> _sharedOrgIds = {};
  bool _savingSharing = false;

  final _commentCtrl = TextEditingController();
  bool _sendingComment = false;

  ApiService get _api => widget.apiService ?? ApiService.instance;
  AccountController? get _account {
    if (widget.accountController != null) return widget.accountController;
    if (Firebase.apps.isNotEmpty) return AccountController.instance;
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.fetchActivityDetail(widget.orgId, widget.activityId),
        _api
            .fetchActivityStreams(widget.orgId, widget.activityId, downsample: 5)
            .catchError((_) => const ActivityStreams()),
        _api
            .fetchActivityComments(widget.orgId, widget.activityId)
            .catchError((_) => const <ActivityComment>[]),
      ]);
      if (!mounted) return;
      final detail = results[0] as ActivityDetail;
      final streams = results[1] as ActivityStreams;
      final comments = results[2] as List<ActivityComment>;

      setState(() {
        _detail = detail;
        _streams = streams;
        _comments = comments;
        _rpe = (detail.summary.rpe ?? 6).clamp(1, 10);
        _feeling = (detail.summary.feeling ?? 4).clamp(1, 5);
        _sharedOrgIds = Set<String>.from(detail.summary.sharedOrgIds);
        _selectedMetric = _firstAvailableMetric(streams);
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
        _error = 'Impossible de charger cette activité.';
        _loading = false;
      });
    }
  }

  static _StreamMetric _firstAvailableMetric(ActivityStreams streams) {
    if (streams.hasHr) return _StreamMetric.hr;
    if (streams.hasPower) return _StreamMetric.power;
    if (streams.hasSpeed) return _StreamMetric.speed;
    if (streams.hasAltitude) return _StreamMetric.altitude;
    return _StreamMetric.hr;
  }

  Future<void> _saveFeedback() async {
    if (_savingFeedback) return;
    setState(() => _savingFeedback = true);
    try {
      final updated = await _api.updateActivityFeedback(
        widget.orgId,
        widget.activityId,
        rpe: _rpe,
        feeling: _feeling,
      );
      if (!mounted) return;
      setState(() {
        if (_detail != null) {
          _detail = _detail!.copyWith(summary: updated);
        }
      });
      _showSnack('RPE et ressenti enregistrés.');
    } on ApiException catch (e) {
      if (!mounted) return;
      _showSnack(e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Impossible d\'enregistrer le ressenti.', isError: true);
    } finally {
      if (mounted) setState(() => _savingFeedback = false);
    }
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sendingComment) return;
    setState(() => _sendingComment = true);
    try {
      final created = await _api.postActivityComment(
        widget.orgId,
        widget.activityId,
        text,
      );
      if (!mounted) return;
      _commentCtrl.clear();
      setState(() {
        _comments = [..._comments, created];
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      _showSnack(e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Impossible d\'envoyer le commentaire.', isError: true);
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  Future<void> _saveSharing() async {
    if (_savingSharing) return;
    setState(() => _savingSharing = true);
    try {
      final updated = await _api.updateActivitySharing(
        widget.orgId,
        widget.activityId,
        _sharedOrgIds.toList(),
      );
      if (!mounted) return;
      setState(() {
        if (_detail != null) {
          _detail = _detail!.copyWith(summary: updated);
        }
        _sharedOrgIds = Set<String>.from(updated.sharedOrgIds);
      });
      _showSnack('Partage multi-clubs mis à jour.');
    } on ApiException catch (e) {
      if (!mounted) return;
      _showSnack(e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Impossible de mettre à jour le partage.', isError: true);
    } finally {
      if (mounted) setState(() => _savingSharing = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? LKColors.danger : LKColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _detail?.summary.title ?? 'Détail activité';

    return Scaffold(
      backgroundColor: LKColors.background,
      appBar: AppBar(
        backgroundColor: LKColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        foregroundColor: LKColors.textPrimary,
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadAll,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: UIUtils.paddingXL,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          SizedBox(height: UIUtils.md),
                          FilledButton(
                            onPressed: _loadAll,
                            child: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final detail = _detail!;
    final s = detail.summary;
    final account = _account;
    final otherMemberships = account == null
        ? const <OrgMembership>[]
        : account.memberships.where((m) => m.orgId != widget.orgId).toList();
    final isSharedFromOtherOrg =
        s.orgId != null && s.orgId!.isNotEmpty && s.orgId != widget.orgId;
    final isOwnerAthlete = account != null &&
        (s.uid == null || s.uid!.isEmpty || s.uid == account.uid);
    final canEditSharing =
        !isSharedFromOtherOrg && isOwnerAthlete && otherMemberships.isNotEmpty;

    return ListView(
      padding: UIUtils.paddingLG,
      children: [
        if (s.startedAt != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${s.sport.toUpperCase()} · ${DateFormat('dd/MM/yyyy HH:mm').format(s.startedAt!.toLocal())}',
              style: UIUtils.bodySmall(context).copyWith(
                color: LKColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

        if (isSharedFromOtherOrg)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: UIUtils.paddingMD,
            decoration: BoxDecoration(
              color: LKColors.primary.withValues(alpha: 0.1),
              borderRadius: UIUtils.borderRadiusAllMD,
              border: Border.all(
                color: LKColors.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.share_rounded,
                  size: 16,
                  color: LKColors.primary,
                ),
                SizedBox(width: UIUtils.sm),
                Expanded(
                  child: Text(
                    'Activité partagée depuis un autre club (consultation).',
                    style: UIUtils.bodySmall(context).copyWith(
                      color: LKColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // KPIs (grille fluide résistante aux grands facteurs d'échelle texte)
        LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = (constraints.maxWidth - UIUtils.sm) / 2;
            final kpis = [
              (label: 'Durée', value: formatDurationSeconds(s.durationS)),
              (
                label: 'Distance',
                value: s.distanceM != null
                    ? '${(s.distanceM! / 1000).toStringAsFixed(2)} km'
                    : '—',
              ),
              (
                label: 'Pts d\'effort',
                value: s.tss != null ? '${s.tss!.round()}' : '—',
              ),
              (
                label: 'NP / IF',
                value: s.normalizedPower != null || s.intensityFactor != null
                    ? '${s.normalizedPower?.round() ?? '—'} W · ${s.intensityFactor?.toStringAsFixed(2) ?? '—'}'
                    : '—',
              ),
              (
                label: 'FC moy.',
                value: s.avgHr != null ? '${s.avgHr} bpm' : '—',
              ),
              (
                label: 'Dénivelé +',
                value: s.elevationGainM != null
                    ? '${s.elevationGainM!.round()} m'
                    : '—',
              ),
            ];
            return Wrap(
              spacing: UIUtils.sm,
              runSpacing: UIUtils.sm,
              children: [
                for (final kpi in kpis)
                  SizedBox(
                    width: itemWidth,
                    child: _KpiCard(label: kpi.label, value: kpi.value),
                  ),
              ],
            );
          },
        ),

        // Courbes (streams downsample=5)
        if (_streams.points.isNotEmpty) ...[
          SizedBox(height: UIUtils.lg),
          _buildChartCard(context),
        ],

        // Vidéos associées
        if (detail.videoAssets.isNotEmpty) ...[
          SizedBox(height: UIUtils.lg),
          Text('Vidéos associées', style: UIUtils.titleSmall(context)),
          SizedBox(height: UIUtils.sm),
          for (final asset in detail.videoAssets)
            ListTile(
              tileColor: LKColors.surfaceElevated,
              shape: RoundedRectangleBorder(
                borderRadius: UIUtils.borderRadiusAllMD,
                side: const BorderSide(color: LKColors.border),
              ),
              leading: const Icon(
                Icons.play_circle_outline_rounded,
                color: LKColors.primary,
              ),
              title: Text(asset.title ?? asset.roomName ?? 'Replay vidéo'),
              trailing: asset.roomName != null
                  ? const Icon(Icons.chevron_right_rounded)
                  : null,
              onTap: asset.roomName == null
                  ? null
                  : () => context.push(
                        '/sessions/${Uri.encodeComponent(widget.orgId)}/${Uri.encodeComponent(asset.roomName!)}',
                      ),
            ),
        ],

        // Laps
        if (detail.laps.isNotEmpty) ...[
          SizedBox(height: UIUtils.lg),
          Text(
            'Tours (${detail.laps.length})',
            style: UIUtils.titleSmall(context),
          ),
          SizedBox(height: UIUtils.sm),
          for (final lap in detail.laps)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: UIUtils.paddingMD,
              decoration: BoxDecoration(
                color: LKColors.surfaceElevated,
                borderRadius: UIUtils.borderRadiusAllMD,
                border: Border.all(color: LKColors.border),
              ),
              child: Row(
                children: [
                  Text(
                    lap.name ?? 'Tour ${lap.index}',
                    style: UIUtils.bodyMedium(context).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    [
                      if (lap.durationS != null)
                        formatDurationSeconds(lap.durationS),
                      if (lap.avgPower != null) '${lap.avgPower!.round()} W',
                      if (lap.avgHr != null) '${lap.avgHr} bpm',
                    ].join(' · '),
                    style: UIUtils.bodySmall(context),
                  ),
                ],
              ),
            ),
        ],

        // Partage multi-clubs
        if (canEditSharing) ...[
          SizedBox(height: UIUtils.lg),
          _buildSharingCard(context, otherMemberships),
        ],

        // RPE & Ressenti post-séance
        SizedBox(height: UIUtils.lg),
        _buildFeedbackCard(context),

        // Commentaires
        SizedBox(height: UIUtils.lg),
        _buildCommentsCard(context),
        SizedBox(height: UIUtils.xxl),
      ],
    );
  }

  Widget _buildSharingCard(
    BuildContext context,
    List<OrgMembership> otherMemberships,
  ) {
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
            children: [
              const Icon(
                Icons.share_rounded,
                size: 18,
                color: LKColors.primary,
              ),
              SizedBox(width: UIUtils.sm),
              Text('Partage multi-clubs', style: UIUtils.titleSmall(context)),
            ],
          ),
          SizedBox(height: UIUtils.xs),
          Text(
            'Rendez cette activité visible auprès de vos autres clubs ou coachs.',
            style: UIUtils.bodySmall(context),
          ),
          SizedBox(height: UIUtils.sm),
          Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (final m in otherMemberships)
                  CheckboxListTile(
                    value: _sharedOrgIds.contains(m.orgId),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: LKColors.primary,
                    title: Text(
                      m.displayOrgName,
                      style: UIUtils.bodyMedium(context).copyWith(
                        color: LKColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      m.roleLabel,
                      style: UIUtils.bodySmall(context),
                    ),
                    onChanged: _savingSharing
                        ? null
                        : (checked) {
                            setState(() {
                              if (checked == true) {
                                _sharedOrgIds.add(m.orgId);
                              } else {
                                _sharedOrgIds.remove(m.orgId);
                              }
                            });
                          },
                  ),
              ],
            ),
          ),
          SizedBox(height: UIUtils.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _savingSharing ? null : _saveSharing,
              style: OutlinedButton.styleFrom(
                foregroundColor: LKColors.primary,
                side: const BorderSide(color: LKColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: UIUtils.borderRadiusAllMD,
                ),
              ),
              child: Text(
                _savingSharing
                    ? 'Enregistrement...'
                    : 'Enregistrer le partage',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(BuildContext context) {
    final available = <_StreamMetric, ({String label, Color color})>{
      if (_streams.hasHr)
        _StreamMetric.hr: (label: 'FC (bpm)', color: LKColors.danger),
      if (_streams.hasPower)
        _StreamMetric.power: (label: 'Puissance (W)', color: LKColors.primary),
      if (_streams.hasSpeed)
        _StreamMetric.speed: (label: 'Vitesse', color: LKColors.success),
      if (_streams.hasAltitude)
        _StreamMetric.altitude: (label: 'Altitude', color: LKColors.warning),
    };
    if (available.isEmpty) return const SizedBox.shrink();

    final activeMetric =
        available.containsKey(_selectedMetric) ? _selectedMetric : available.keys.first;
    final meta = available[activeMetric]!;

    final spots = <FlSpot>[];
    for (final pt in _streams.points) {
      final y = switch (activeMetric) {
        _StreamMetric.hr => pt.hr,
        _StreamMetric.power => pt.power,
        _StreamMetric.speed => pt.speedKmh,
        _StreamMetric.altitude => pt.altitudeM,
      };
      if (y != null && !y.isNaN && !y.isInfinite) {
        spots.add(FlSpot(pt.timeS / 60.0, y));
      }
    }

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
          Text('Courbes de séance', style: UIUtils.titleSmall(context)),
          SizedBox(height: UIUtils.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in available.entries)
                ChoiceChip(
                  label: Text(entry.value.label),
                  selected: activeMetric == entry.key,
                  selectedColor: entry.value.color.withValues(alpha: 0.25),
                  onSelected: (_) =>
                      setState(() => _selectedMetric = entry.key),
                ),
            ],
          ),
          SizedBox(height: UIUtils.md),
          if (spots.length < 2)
            Text(
              'Données insuffisantes pour tracer la courbe.',
              style: UIUtils.bodySmall(context),
            )
          else
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => const FlLine(
                      color: LKColors.border,
                      strokeWidth: 0.6,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (v, _) => Text(
                          '${v.round()}m',
                          style: const TextStyle(
                            fontSize: 10,
                            color: LKColors.textHint,
                          ),
                        ),
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 38,
                        getTitlesWidget: (v, _) => Text(
                          '${v.round()}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: LKColors.textHint,
                          ),
                        ),
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: meta.color,
                      barWidth: 2.2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: meta.color.withValues(alpha: 0.14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFeedbackCard(BuildContext context) {
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
          Text('Débriefing post-séance', style: UIUtils.titleSmall(context)),
          SizedBox(height: UIUtils.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('RPE (effort perçu)', style: UIUtils.bodyMedium(context)),
              Text(
                '$_rpe / 10',
                style: UIUtils.titleSmall(context).copyWith(
                  color: LKColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Slider(
            value: _rpe.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            activeColor: LKColors.primary,
            onChanged: _savingFeedback
                ? null
                : (v) => setState(() => _rpe = v.round()),
          ),
          SizedBox(height: UIUtils.xs),
          Text('Ressenti (1–5)', style: UIUtils.bodyMedium(context)),
          SizedBox(height: UIUtils.xs),
          Row(
            children: [
              for (var i = 1; i <= 5; i++) ...[
                Expanded(
                  child: Semantics(
                    container: true,
                    button: true,
                    selected: _feeling == i,
                    label: 'Ressenti $i sur 5',
                    child: InkWell(
                      borderRadius: UIUtils.borderRadiusAllSM,
                      onTap: _savingFeedback
                          ? null
                          : () => setState(() => _feeling = i),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _feeling == i
                              ? LKColors.primary
                              : LKColors.surface,
                          borderRadius: UIUtils.borderRadiusAllSM,
                          border: Border.all(
                            color: _feeling == i
                                ? LKColors.primary
                                : LKColors.border,
                          ),
                        ),
                        child: ExcludeSemantics(
                          child: Text(
                            '$i',
                            style: UIUtils.labelLarge(context).copyWith(
                              color: _feeling == i
                                  ? Colors.white
                                  : LKColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (i < 5) const SizedBox(width: 6),
              ],
            ],
          ),
          SizedBox(height: UIUtils.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _savingFeedback ? null : _saveFeedback,
              style: FilledButton.styleFrom(
                backgroundColor: LKColors.primary,
                foregroundColor: Colors.white,
              ),
              child: Text(
                _savingFeedback
                    ? 'Enregistrement...'
                    : 'Enregistrer RPE & ressenti',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsCard(BuildContext context) {
    final fmt = DateFormat('dd/MM HH:mm');
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
          Text(
            'Commentaires (${_comments.length})',
            style: UIUtils.titleSmall(context),
          ),
          SizedBox(height: UIUtils.sm),
          if (_comments.isEmpty)
            Text(
              'Aucun commentaire pour le moment.',
              style: UIUtils.bodySmall(context),
            )
          else
            for (final c in _comments)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: UIUtils.paddingMD,
                decoration: BoxDecoration(
                  color: LKColors.surface,
                  borderRadius: UIUtils.borderRadiusAllMD,
                  border: Border.all(color: LKColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          c.displayAuthor,
                          style: UIUtils.bodySmall(context).copyWith(
                            color: LKColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        if (c.createdAt != null)
                          Text(
                            fmt.format(c.createdAt!.toLocal()),
                            style: UIUtils.bodySmall(context).copyWith(
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(c.body, style: UIUtils.bodyMedium(context)),
                  ],
                ),
              ),
          SizedBox(height: UIUtils.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  decoration: UIUtils.inputDecoration(
                    labelText: 'Ajouter un commentaire',
                    hintText: 'Sensations, consignes...',
                  ),
                  onSubmitted: (_) => _sendComment(),
                ),
              ),
              SizedBox(width: UIUtils.sm),
              IconButton.filled(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: 'Envoyer le commentaire',
                onPressed: _sendingComment ? null : _sendComment,
                style: IconButton.styleFrom(
                  backgroundColor: LKColors.primary,
                  foregroundColor: Colors.white,
                ),
                icon: _sendingComment
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: LKColors.surfaceElevated,
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(color: LKColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: UIUtils.bodySmall(context)),
          const SizedBox(height: 2),
          Text(
            value,
            style: UIUtils.titleSmall(context).copyWith(
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
