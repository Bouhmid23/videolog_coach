import 'package:flutter/material.dart';

import '../../core/account_controller.dart';
import '../../core/api_service.dart';
import '../../data/training_models.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

Future<bool?> showWellnessCheckinSheet(
  BuildContext context, {
  required String orgId,
  required String uid,
  bool? hasHealthConsent,
  ApiService? apiService,
}) {
  final consent = hasHealthConsent ?? AccountController.instance.hasHealthConsent;
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => WellnessCheckinSheet(
      orgId: orgId,
      uid: uid,
      hasHealthConsent: consent,
      apiService: apiService,
    ),
  );
}

class WellnessCheckinSheet extends StatefulWidget {
  const WellnessCheckinSheet({
    required this.orgId,
    required this.uid,
    required this.hasHealthConsent,
    this.apiService,
    super.key,
  });

  final String orgId;
  final String uid;
  final bool hasHealthConsent;
  final ApiService? apiService;

  @override
  State<WellnessCheckinSheet> createState() => _WellnessCheckinSheetState();
}

class _WellnessCheckinSheetState extends State<WellnessCheckinSheet> {
  double _sleepHours = 7.5;
  int _sleepQuality = 4;
  int _fatigue = 2;
  int _soreness = 2;
  int _stress = 2;
  int _mood = 4;

  final _hrvCtrl = TextEditingController();
  final _rhrCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();

  bool _submitting = false;
  String? _error;

  ApiService get _api => widget.apiService ?? ApiService.instance;

  @override
  void dispose() {
    _hrvCtrl.dispose();
    _rhrCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final entry = WellnessEntry(
      date: formatIsoDate(DateTime.now()),
      sleepH: double.parse(_sleepHours.toStringAsFixed(1)),
      sleepQuality: _sleepQuality,
      fatigue: _fatigue,
      soreness: _soreness,
      stress: _stress,
      mood: _mood,
      hrvMs: widget.hasHealthConsent
          ? double.tryParse(_hrvCtrl.text.trim().replaceAll(',', '.'))
          : null,
      restingHr: widget.hasHealthConsent
          ? int.tryParse(_rhrCtrl.text.trim())
          : null,
      weightKg: widget.hasHealthConsent
          ? double.tryParse(_weightCtrl.text.trim().replaceAll(',', '.'))
          : null,
    );

    try {
      await _api.submitWellness(
        widget.orgId,
        uid: widget.uid,
        entry: entry,
        includeHealthData: widget.hasHealthConsent,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'Impossible d\'enregistrer votre forme du jour.',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
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
              children: [
                const Icon(
                  Icons.favorite_outline_rounded,
                  color: LKColors.primary,
                ),
                SizedBox(width: UIUtils.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Forme du jour', style: UIUtils.titleLarge(context)),
                      Text(
                        'Check-in rapide (10 s) · ${formatIsoDate(DateTime.now())}',
                        style: UIUtils.bodySmall(context),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            SizedBox(height: UIUtils.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Sommeil', style: UIUtils.titleSmall(context)),
                Text(
                  '${_sleepHours.toStringAsFixed(1)} h',
                  style: UIUtils.titleSmall(context).copyWith(
                    color: LKColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Slider(
              value: _sleepHours,
              min: 0,
              max: 12,
              divisions: 24,
              activeColor: LKColors.primary,
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _sleepHours = v),
            ),
            _ScaleRow(
              label: 'Qualité du sommeil',
              value: _sleepQuality,
              lowLabel: 'Mauvaise',
              highLabel: 'Excellente',
              onChanged: (v) => setState(() => _sleepQuality = v),
            ),
            _ScaleRow(
              label: 'Fatigue',
              value: _fatigue,
              lowLabel: 'Frais',
              highLabel: 'Épuisé',
              onChanged: (v) => setState(() => _fatigue = v),
            ),
            _ScaleRow(
              label: 'Courbatures',
              value: _soreness,
              lowLabel: 'Aucune',
              highLabel: 'Fortes',
              onChanged: (v) => setState(() => _soreness = v),
            ),
            _ScaleRow(
              label: 'Stress',
              value: _stress,
              lowLabel: 'Calme',
              highLabel: 'Élevé',
              onChanged: (v) => setState(() => _stress = v),
            ),
            _ScaleRow(
              label: 'Humeur',
              value: _mood,
              lowLabel: 'Basse',
              highLabel: 'Top',
              onChanged: (v) => setState(() => _mood = v),
            ),
            SizedBox(height: UIUtils.md),
            if (widget.hasHealthConsent) ...[
              Text(
                'Métriques physiologiques (optionnel)',
                style: UIUtils.titleSmall(context),
              ),
              SizedBox(height: UIUtils.sm),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _hrvCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: UIUtils.inputDecoration(
                        labelText: 'VFC (ms)',
                        hintText: '68',
                      ),
                    ),
                  ),
                  SizedBox(width: UIUtils.sm),
                  Expanded(
                    child: TextField(
                      controller: _rhrCtrl,
                      keyboardType: TextInputType.number,
                      decoration: UIUtils.inputDecoration(
                        labelText: 'FC repos',
                        hintText: '48',
                      ),
                    ),
                  ),
                  SizedBox(width: UIUtils.sm),
                  Expanded(
                    child: TextField(
                      controller: _weightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: UIUtils.inputDecoration(
                        labelText: 'Poids (kg)',
                        hintText: '71.5',
                      ),
                    ),
                  ),
                ],
              ),
            ] else
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
                      Icons.privacy_tip_outlined,
                      size: 18,
                      color: LKColors.textSecondary,
                    ),
                    SizedBox(width: UIUtils.sm),
                    Expanded(
                      child: Text(
                        'VFC, FC repos et poids masqués (consentement santé RGPD non accordé).',
                        style: UIUtils.bodySmall(context),
                      ),
                    ),
                  ],
                ),
              ),
            if (_error != null) ...[
              SizedBox(height: UIUtils.sm),
              Text(
                _error!,
                style: UIUtils.bodySmall(context).copyWith(
                  color: LKColors.danger,
                ),
              ),
            ],
            SizedBox(height: UIUtils.lg),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: LKColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: UIUtils.borderRadiusAllMD,
                ),
              ),
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                _submitting ? 'Enregistrement...' : 'Valider ma forme du jour',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScaleRow extends StatelessWidget {
  const _ScaleRow({
    required this.label,
    required this.value,
    required this.lowLabel,
    required this.highLabel,
    required this.onChanged,
  });

  final String label;
  final int value;
  final String lowLabel;
  final String highLabel;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: UIUtils.bodyMedium(context)),
              Text(
                '$lowLabel ↔ $highLabel',
                style: UIUtils.bodySmall(context).copyWith(fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 1; i <= 5; i++) ...[
                Expanded(
                  child: Semantics(
                    container: true,
                    button: true,
                    selected: value == i,
                    label: '$label : $i sur 5',
                    child: InkWell(
                      borderRadius: UIUtils.borderRadiusAllSM,
                      onTap: () => onChanged(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        constraints: const BoxConstraints(minHeight: 48),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: value == i
                              ? LKColors.primary
                              : LKColors.surface,
                          borderRadius: UIUtils.borderRadiusAllSM,
                          border: Border.all(
                            color: value == i
                                ? LKColors.primary
                                : LKColors.border,
                          ),
                        ),
                        child: ExcludeSemantics(
                          child: Text(
                            '$i',
                            style: UIUtils.labelLarge(context).copyWith(
                              color: value == i
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
        ],
      ),
    );
  }
}
