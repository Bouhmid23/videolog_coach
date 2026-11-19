import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_service.dart';
import '../../data/activity_models.dart';
import '../../data/training_models.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

typedef WorkoutFileShareHandler = Future<void> Function(
  String filePath,
  String title,
);

Future<void> showPlannedWorkoutSheet(
  BuildContext context, {
  required String orgId,
  required PlannedWorkout workout,
  ApiService? apiService,
  WorkoutFileShareHandler? onShareFile,
  DateTime? now,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => PlannedWorkoutSheet(
      orgId: orgId,
      workout: workout,
      apiService: apiService,
      onShareFile: onShareFile,
      now: now,
    ),
  );
}

class PlannedWorkoutSheet extends StatefulWidget {
  const PlannedWorkoutSheet({
    required this.orgId,
    required this.workout,
    this.apiService,
    this.onShareFile,
    this.now,
    super.key,
  });

  final String orgId;
  final PlannedWorkout workout;
  final ApiService? apiService;
  final WorkoutFileShareHandler? onShareFile;
  final DateTime? now;

  @override
  State<PlannedWorkoutSheet> createState() => _PlannedWorkoutSheetState();
}

class _PlannedWorkoutSheetState extends State<PlannedWorkoutSheet> {
  String? _exportingFormat;
  String? _exportError;

  List<ActivityComment> _comments = const [];
  bool _loadingComments = true;
  bool _sendingComment = false;
  bool _readOnlyRejected = false;
  String? _commentError;
  final _commentCtrl = TextEditingController();

  ApiService get _api => widget.apiService ?? ApiService.instance;

  bool get _isReadOnly =>
      _readOnlyRejected ||
      widget.workout.isExpiredAt(widget.now ?? DateTime.now());

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final list = await _api.fetchPlannedWorkoutComments(
        widget.orgId,
        widget.workout.id,
      );
      if (!mounted) return;
      setState(() {
        _comments = list;
        _loadingComments = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingComments = false);
    }
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sendingComment || _isReadOnly) return;
    setState(() {
      _sendingComment = true;
      _commentError = null;
    });
    try {
      final created = await _api.postPlannedWorkoutComment(
        widget.orgId,
        widget.workout.id,
        text,
      );
      if (!mounted) return;
      _commentCtrl.clear();
      setState(() {
        _comments = [..._comments, created];
        _sendingComment = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.statusCode == 400) {
          _readOnlyRejected = true;
        }
        _commentError = e.message;
        _sendingComment = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _commentError = 'Impossible d\'envoyer le message.';
        _sendingComment = false;
      });
    }
  }

  Future<void> _export(String format) async {
    if (_exportingFormat != null) return;
    setState(() {
      _exportingFormat = format;
      _exportError = null;
    });
    try {
      final bytes = await _api.exportPlannedWorkout(
        widget.orgId,
        widget.workout.id,
        format: format,
      );
      if (widget.onShareFile != null) {
        final safeName = _sanitizeFileName(widget.workout.title);
        await widget.onShareFile!('$safeName.$format', widget.workout.title);
      } else {
        final dir = await getTemporaryDirectory();
        final safeName = _sanitizeFileName(widget.workout.title);
        final file = File('${dir.path}/$safeName.$format');
        await file.writeAsBytes(bytes, flush: true);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            subject: widget.workout.title,
          ),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export .${format.toUpperCase()} prêt.'),
          backgroundColor: LKColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _exportError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _exportError = 'Impossible d\'exporter la séance en .$format.',
      );
    } finally {
      if (mounted) setState(() => _exportingFormat = null);
    }
  }

  static String _sanitizeFileName(String raw) {
    final cleaned = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return cleaned.isEmpty ? 'seance' : cleaned;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.workout;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: LKColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: LKColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(
        UIUtils.lg,
        UIUtils.md,
        UIUtils.lg,
        UIUtils.lg + bottomInset,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: LKColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: UIUtils.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: UIUtils.xs,
                        runSpacing: UIUtils.xs,
                        children: [
                          _TagPill(
                            label: w.sport.toUpperCase(),
                            color: LKColors.primary,
                          ),
                          _TagPill(
                            label: w.statusLabel,
                            color: _statusColor(w.status),
                          ),
                          if (w.compliance?.score != null)
                            _TagPill(
                              label:
                                  'Compliance ${w.compliance!.score!.round()}%',
                              color: _complianceColor(w.compliance!.color),
                            ),
                        ],
                      ),
                      SizedBox(height: UIUtils.sm),
                      Text(w.title, style: UIUtils.titleLarge(context)),
                      if (w.date != null ||
                          (w.startTime != null && w.startTime!.trim().isNotEmpty)) ...[
                        SizedBox(height: 2),
                        Text(
                          [
                            if (w.date != null) formatIsoDate(w.date!),
                            if (w.startTime != null &&
                                w.startTime!.trim().isNotEmpty)
                              'à ${w.startTime!.trim()}',
                          ].join(' '),
                          style: UIUtils.bodySmall(context),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            SizedBox(height: UIUtils.md),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    icon: Icons.timer_outlined,
                    label: 'Durée estimée',
                    value: formatDurationSeconds(w.estimatedDurationS),
                  ),
                ),
                SizedBox(width: UIUtils.sm),
                Expanded(
                  child: _MetricTile(
                    icon: Icons.bolt_rounded,
                    label: 'Effort estimé',
                    value: w.estimatedTss != null
                        ? '${w.estimatedTss!.round()} pts'
                        : '—',
                  ),
                ),
              ],
            ),
            if (w.coachNote != null && w.coachNote!.trim().isNotEmpty) ...[
              SizedBox(height: UIUtils.md),
              Container(
                padding: UIUtils.paddingMD,
                decoration: BoxDecoration(
                  color: LKColors.primary.withValues(alpha: 0.1),
                  borderRadius: UIUtils.borderRadiusAllMD,
                  border: Border.all(
                    color: LKColors.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 16,
                      color: LKColors.primary,
                    ),
                    SizedBox(width: UIUtils.sm),
                    Expanded(
                      child: Text(
                        w.coachNote!.trim(),
                        style: UIUtils.bodySmall(context).copyWith(
                          color: LKColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (w.description != null && w.description!.trim().isNotEmpty) ...[
              SizedBox(height: UIUtils.md),
              Text(
                w.description!.trim(),
                style: UIUtils.bodyMedium(context).copyWith(
                  color: LKColors.textSecondary,
                ),
              ),
            ],
            if (w.blocks.isNotEmpty) ...[
              SizedBox(height: UIUtils.lg),
              Text(
                'Profil d\'intensité',
                style: UIUtils.titleSmall(context),
              ),
              SizedBox(height: UIUtils.sm),
              WorkoutIntensityBar(blocks: w.blocks),
            ],
            if (w.steps.isNotEmpty) ...[
              SizedBox(height: UIUtils.lg),
              Text(
                'Étapes de la séance (${w.steps.length})',
                style: UIUtils.titleSmall(context),
              ),
              SizedBox(height: UIUtils.sm),
              for (var i = 0; i < w.steps.length; i++) ...[
                _StepTile(index: i + 1, step: w.steps[i]),
                if (i < w.steps.length - 1) SizedBox(height: UIUtils.xs),
              ],
            ],
            SizedBox(height: UIUtils.lg),
            Text(
              'Exporter vers montre / home trainer',
              style: UIUtils.titleSmall(context),
            ),
            SizedBox(height: UIUtils.sm),
            Row(
              children: [
                for (final fmt in const ['fit', 'zwo', 'erg']) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _exportingFormat != null ? null : () => _export(fmt),
                      icon: _exportingFormat == fmt
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded, size: 16),
                      label: Text('.${fmt.toUpperCase()}'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: LKColors.primary,
                        side: const BorderSide(color: LKColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: UIUtils.borderRadiusAllMD,
                        ),
                      ),
                    ),
                  ),
                  if (fmt != 'erg') SizedBox(width: UIUtils.sm),
                ],
              ],
            ),
            if (_exportError != null) ...[
              SizedBox(height: UIUtils.sm),
              Text(
                _exportError!,
                style: UIUtils.bodySmall(context).copyWith(
                  color: LKColors.danger,
                ),
              ),
            ],
            SizedBox(height: UIUtils.lg),
            _buildDiscussionSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscussionSection(BuildContext context) {
    final fmt = DateFormat('dd/MM HH:mm');
    final isReadOnly = _isReadOnly;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Discussion (${_comments.length})',
          style: UIUtils.titleSmall(context),
        ),
        SizedBox(height: UIUtils.sm),
        if (_loadingComments)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_comments.isEmpty)
          Text(
            'Aucun message pour le moment.',
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
                  const SizedBox(height: 4),
                  Text(c.body, style: UIUtils.bodyMedium(context)),
                ],
              ),
            ),
        SizedBox(height: UIUtils.sm),
        if (isReadOnly)
          Container(
            padding: UIUtils.paddingMD,
            decoration: BoxDecoration(
              color: LKColors.surface,
              borderRadius: UIUtils.borderRadiusAllMD,
              border: Border.all(color: LKColors.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: LKColors.textHint,
                ),
                SizedBox(width: UIUtils.sm),
                Expanded(
                  child: Text(
                    'Séance passée : discussion en lecture seule',
                    style: UIUtils.bodySmall(context),
                  ),
                ),
              ],
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  decoration: UIUtils.inputDecoration(
                    labelText: 'Message au coach',
                    hintText: 'Question, adaptation...',
                  ),
                  onSubmitted: (_) => _sendComment(),
                ),
              ),
              SizedBox(width: UIUtils.sm),
              IconButton.filled(
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
        if (_commentError != null) ...[
          SizedBox(height: UIUtils.xs),
          Text(
            _commentError!,
            style: UIUtils.bodySmall(context).copyWith(
              color: LKColors.danger,
            ),
          ),
        ],
      ],
    );
  }

  static Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'done':
      case 'completed':
        return LKColors.success;
      case 'partial':
        return LKColors.warning;
      case 'missed':
      case 'skipped':
        return LKColors.danger;
      default:
        return LKColors.secondary;
    }
  }

  static Color _complianceColor(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'green':
      case 'success':
        return LKColors.success;
      case 'yellow':
      case 'amber':
      case 'warning':
        return LKColors.warning;
      case 'red':
      case 'danger':
        return LKColors.danger;
      default:
        return LKColors.primary;
    }
  }
}

/// Barre d'intensité colorée construite depuis les `blocks[]` de la séance.
class WorkoutIntensityBar extends StatelessWidget {
  const WorkoutIntensityBar({
    required this.blocks,
    this.height = 52,
    super.key,
  });

  final List<WorkoutBlock> blocks;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (blocks.isEmpty) return const SizedBox.shrink();

    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(color: LKColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            Expanded(
              flex: blocks[i].durationS > 0 ? blocks[i].durationS : 60,
              child: Tooltip(
                message: _tooltipFor(blocks[i]),
                child: FractionallySizedBox(
                  alignment: Alignment.bottomCenter,
                  heightFactor: _heightFactor(blocks[i]),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _colorFor(blocks[i]),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
            if (i < blocks.length - 1) const SizedBox(width: 2),
          ],
        ],
      ),
    );
  }

  double _heightFactor(WorkoutBlock b) {
    final pct = b.intensityPct;
    if (pct != null && pct > 0) {
      return (pct / 120.0).clamp(0.25, 1.0);
    }
    switch (b.zone?.toUpperCase()) {
      case 'Z1':
        return 0.30;
      case 'Z2':
        return 0.48;
      case 'Z3':
        return 0.65;
      case 'Z4':
        return 0.82;
      case 'Z5':
      case 'Z6':
        return 0.96;
      default:
        return 0.55;
    }
  }

  Color _colorFor(WorkoutBlock b) {
    final hex = b.colorHex;
    if (hex != null && hex.startsWith('#') && hex.length == 7) {
      final parsed = int.tryParse(hex.substring(1), radix: 16);
      if (parsed != null) return Color(0xFF000000 | parsed);
    }
    final pct = b.intensityPct ?? 0;
    if (pct >= 105 || b.zone?.toUpperCase() == 'Z5') return LKColors.danger;
    if (pct >= 90 || b.zone?.toUpperCase() == 'Z4') return LKColors.warning;
    if (pct >= 75 || b.zone?.toUpperCase() == 'Z3') return LKColors.primary;
    if (pct >= 55 || b.zone?.toUpperCase() == 'Z2') return LKColors.success;
    return LKColors.textSecondary;
  }

  String _tooltipFor(WorkoutBlock b) {
    final parts = <String>[
      if (b.label.isNotEmpty) b.label,
      if (b.durationS > 0) formatDurationSeconds(b.durationS),
      if (b.intensityPct != null) '${b.intensityPct!.round()}%',
    ];
    return parts.join(' · ');
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.index, required this.step});

  final int index;
  final WorkoutStep step;

  @override
  Widget build(BuildContext context) {
    final target = step.displayTarget;
    final dur = step.durationS != null
        ? formatDurationSeconds(step.durationS)
        : (step.distanceM != null
            ? '${(step.distanceM! / 1000).toStringAsFixed(1)} km'
            : '');

    return Container(
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(color: LKColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: LKColors.primary.withValues(alpha: 0.16),
            child: Text(
              '$index',
              style: UIUtils.bodySmall(context).copyWith(
                color: LKColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(width: UIUtils.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.name.isNotEmpty
                      ? step.name
                      : (step.repeatCount != null
                          ? 'Répéter ×${step.repeatCount}'
                          : step.type),
                  style: UIUtils.bodyMedium(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (dur.isNotEmpty || target.isNotEmpty) ...[
                  SizedBox(height: 2),
                  Text(
                    [if (dur.isNotEmpty) dur, if (target.isNotEmpty) target]
                        .join(' · '),
                    style: UIUtils.bodySmall(context).copyWith(
                      color: LKColors.primary,
                    ),
                  ),
                ],
                if (step.notes != null && step.notes!.trim().isNotEmpty) ...[
                  SizedBox(height: 2),
                  Text(
                    step.notes!.trim(),
                    style: UIUtils.bodySmall(context),
                  ),
                ],
                if (step.steps.isNotEmpty) ...[
                  SizedBox(height: UIUtils.xs),
                  for (final sub in step.steps)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '• ${sub.name.isNotEmpty ? sub.name : sub.type}'
                        '${sub.durationS != null ? ' (${formatDurationSeconds(sub.durationS)})' : ''}'
                        '${sub.displayTarget.isNotEmpty ? ' · ${sub.displayTarget}' : ''}',
                        style: UIUtils.bodySmall(context),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(color: LKColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: LKColors.primary),
          SizedBox(width: UIUtils.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: UIUtils.bodySmall(context)),
                Text(
                  value,
                  style: UIUtils.titleSmall(context).copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: UIUtils.bodySmall(context).copyWith(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
