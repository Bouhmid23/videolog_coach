import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_service.dart';
import '../../data/account_models.dart';
import '../../data/pmc_models.dart';
import '../../data/training_models.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

Future<AthleteThreshold?> showThresholdsSheet(
  BuildContext context, {
  required String orgId,
  required String uid,
  ApiService? apiService,
  String initialSport = 'cyclisme',
}) {
  return showModalBottomSheet<AthleteThreshold>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => ThresholdsSheet(
      orgId: orgId,
      uid: uid,
      apiService: apiService,
      initialSport: initialSport,
    ),
  );
}

class ThresholdsSheet extends StatefulWidget {
  const ThresholdsSheet({
    required this.orgId,
    required this.uid,
    this.apiService,
    this.initialSport = 'cyclisme',
    super.key,
  });

  final String orgId;
  final String uid;
  final ApiService? apiService;
  final String initialSport;

  @override
  State<ThresholdsSheet> createState() => _ThresholdsSheetState();
}

class _ThresholdsSheetState extends State<ThresholdsSheet> {
  final _ftpController = TextEditingController();
  final _lthrController = TextEditingController();

  late String _sport;
  DateTime _effectiveFrom = DateTime.now();
  bool _recalculateActivities = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<AthleteThreshold> _thresholds = const [];

  ApiService get _api => widget.apiService ?? ApiService.instance;

  @override
  void initState() {
    super.initState();
    _sport = kSupportedSports.contains(widget.initialSport)
        ? widget.initialSport
        : 'cyclisme';
    _load();
  }

  @override
  void dispose() {
    _ftpController.dispose();
    _lthrController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.fetchMyThresholds();
      if (!mounted) return;
      setState(() {
        _thresholds = list;
        _loading = false;
      });
      _applyThresholdForSport(_sport);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de récupérer vos seuils actifs.';
      });
    }
  }

  AthleteThreshold? _findForSport(String sport) {
    for (final t in _thresholds) {
      if (t.sport.toLowerCase() == sport.toLowerCase()) return t;
    }
    return null;
  }

  void _applyThresholdForSport(String sport) {
    final match = _findForSport(sport);
    _ftpController.text = match?.ftpW != null ? '${match!.ftpW}' : '';
    _lthrController.text = match?.lthrBpm != null ? '${match!.lthrBpm}' : '';
  }

  int? get _parsedFtp {
    final text = _ftpController.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  int? get _parsedLthr {
    final text = _lthrController.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  Future<void> _pickEffectiveDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveFrom,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Date d\'effet du palier',
    );
    if (picked == null || !mounted) return;
    setState(() => _effectiveFrom = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    final ftp = _parsedFtp;
    final lthr = _parsedLthr;

    if (ftp == null && lthr == null) {
      setState(() => _error = 'Renseignez au moins une FTP (W) ou une FC seuil (bpm).');
      return;
    }
    if (ftp != null && (ftp < 40 || ftp > 1000)) {
      setState(() => _error = 'La FTP doit être comprise entre 40 et 1000 W.');
      return;
    }
    if (lthr != null && (lthr < 80 || lthr > 220)) {
      setState(() => _error = 'La LTHR doit être comprise entre 80 et 220 bpm.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final updated = await _api.updateAthleteThresholds(
        widget.orgId,
        widget.uid,
        sport: _sport,
        effectiveFrom: formatIsoDate(_effectiveFrom),
        ftpW: ftp,
        lthrBpm: lthr,
        recalculateActivities: _recalculateActivities,
      );
      unawaited(HapticFeedback.lightImpact());
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.of(context).pop(updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Impossible d\'enregistrer les seuils.';
      });
    }
  }

  String _formatDateFr(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final ftp = _parsedFtp;
    final lthr = _parsedLthr;
    final activeMatch = _findForSport(_sport);
    final powerZones = (ftp != null && ftp > 0)
        ? AthleteThreshold.buildPowerZones(ftp)
        : (activeMatch?.effectivePowerZones ?? const <ThresholdZone>[]);
    final hrZones = (lthr != null && lthr > 0)
        ? AthleteThreshold.buildLthrZones(lthr)
        : (activeMatch?.effectiveHrZones ?? const <ThresholdZone>[]);

    return Container(
      margin: EdgeInsets.only(top: 48, bottom: bottomInset),
      decoration: BoxDecoration(
        color: LKColors.surfaceElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: LKColors.border, width: 0.6),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            UIUtils.xl,
            UIUtils.md,
            UIUtils.xl,
            UIUtils.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: LKColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              SizedBox(height: UIUtils.lg),

              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: LKColors.primary.withValues(alpha: 0.14),
                      borderRadius: UIUtils.borderRadiusAllMD,
                    ),
                    child: const Icon(
                      Icons.speed_rounded,
                      color: LKColors.primary,
                      size: 22,
                    ),
                  ),
                  SizedBox(width: UIUtils.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Seuils & Zones',
                          style: UIUtils.titleMedium(context),
                        ),
                        Text(
                          'FTP, FC au seuil (LTHR) et zones d\'entraînement',
                          style: UIUtils.bodySmall(context).copyWith(
                            color: LKColors.textHint,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: LKColors.textSecondary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: UIUtils.lg),

              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: LKColors.primary),
                  ),
                )
              else ...[
                // Sport + date d'effet
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _sport,
                        decoration: UIUtils.inputDecoration(labelText: 'Sport'),
                        dropdownColor: LKColors.surfaceElevated,
                        items: kSupportedSports
                            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _sport = v;
                            _error = null;
                            _applyThresholdForSport(v);
                          });
                        },
                      ),
                    ),
                    SizedBox(width: UIUtils.md),
                    Expanded(
                      child: InkWell(
                        onTap: _pickEffectiveDate,
                        borderRadius: UIUtils.borderRadiusAllMD,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: LKColors.surface,
                            borderRadius: UIUtils.borderRadiusAllMD,
                            border: Border.all(color: LKColors.border, width: 0.6),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.event_outlined,
                                size: 18,
                                color: LKColors.primary,
                              ),
                              SizedBox(width: UIUtils.sm),
                              Expanded(
                                child: Text(
                                  _formatDateFr(_effectiveFrom),
                                  style: UIUtils.bodyMedium(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: UIUtils.md),

                // Inputs FTP & LTHR
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ftpController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: UIUtils.inputDecoration(
                          labelText: 'FTP (Watts)',
                          hintText: 'ex: 265',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    SizedBox(width: UIUtils.md),
                    Expanded(
                      child: TextField(
                        controller: _lthrController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: UIUtils.inputDecoration(
                          labelText: 'LTHR (bpm)',
                          hintText: 'ex: 172',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: UIUtils.md),

                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: UIUtils.md,
                    vertical: UIUtils.xs,
                  ),
                  decoration: BoxDecoration(
                    color: LKColors.surface,
                    borderRadius: UIUtils.borderRadiusAllMD,
                    border: Border.all(color: LKColors.border, width: 0.5),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile.adaptive(
                      value: _recalculateActivities,
                      contentPadding: EdgeInsets.zero,
                      activeTrackColor: LKColors.primary,
                      title: Text(
                        'Recalculer les activités passées',
                        style: UIUtils.bodyMedium(context).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Met à jour le TSS et les zones depuis la date d\'effet',
                        style: UIUtils.bodySmall(context).copyWith(fontSize: 11),
                      ),
                      onChanged: (v) =>
                          setState(() => _recalculateActivities = v),
                    ),
                  ),
                ),

                if (powerZones.isNotEmpty) ...[
                  SizedBox(height: UIUtils.lg),
                  Text(
                    'Zones de puissance (FTP)',
                    style: UIUtils.titleSmall(context),
                  ),
                  SizedBox(height: UIUtils.sm),
                  _ZonesGrid(zones: powerZones, accent: LKColors.primary),
                ],

                if (hrZones.isNotEmpty) ...[
                  SizedBox(height: UIUtils.lg),
                  Text(
                    'Zones cardiaques (LTHR)',
                    style: UIUtils.titleSmall(context),
                  ),
                  SizedBox(height: UIUtils.sm),
                  _ZonesGrid(zones: hrZones, accent: LKColors.danger),
                ],

                if (_error != null) ...[
                  SizedBox(height: UIUtils.md),
                  Container(
                    padding: UIUtils.paddingMD,
                    decoration: BoxDecoration(
                      color: LKColors.danger.withValues(alpha: 0.12),
                      borderRadius: UIUtils.borderRadiusAllMD,
                      border: Border.all(
                        color: LKColors.danger.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      _error!,
                      style: UIUtils.bodySmall(context).copyWith(
                        color: LKColors.danger,
                      ),
                    ),
                  ),
                ],
                SizedBox(height: UIUtils.xl),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: Text(
                      _saving ? 'Enregistrement…' : 'Enregistrer les seuils',
                      style: UIUtils.labelLarge(context).copyWith(
                        color: Colors.white,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: LKColors.primary,
                      foregroundColor: Colors.white,
                      padding: UIUtils.paddingVerticalMD,
                      shape: RoundedRectangleBorder(
                        borderRadius: UIUtils.borderRadiusAllMD,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ZonesGrid extends StatelessWidget {
  const _ZonesGrid({
    required this.zones,
    required this.accent,
  });

  final List<ThresholdZone> zones;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(color: LKColors.border, width: 0.5),
      ),
      child: Column(
        children: [
          for (var i = 0; i < zones.length; i++) ...[
            if (i > 0)
              const Divider(height: 12, thickness: 0.5, color: LKColors.border),
            Row(
              children: [
                Container(
                  width: 34,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    zones[i].code,
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(width: UIUtils.sm),
                Expanded(
                  child: Text(
                    zones[i].name,
                    style: UIUtils.bodySmall(context).copyWith(
                      color: LKColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  zones[i].rangeLabel,
                  style: UIUtils.bodySmall(context).copyWith(
                    fontWeight: FontWeight.w600,
                    color: LKColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
