import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth_service.dart';
import '../../data/athlete_profile.dart';
import '../../data/heart_rate_zones.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

/// Ouvre la feuille modale d'édition du [AthleteProfile] de l'utilisateur courant
/// et retourne le profil mis à jour s'il a été sauvegardé.
Future<AthleteProfile?> showAthleteProfileSheet(
  BuildContext context, {
  AthleteProfile? initialProfile,
}) async {
  final current = initialProfile ?? await AthleteProfile.load();
  if (!context.mounted) return null;

  return showModalBottomSheet<AthleteProfile>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => AthleteProfileSheet(initialProfile: current),
  );
}

class AthleteProfileSheet extends StatefulWidget {
  final AthleteProfile initialProfile;

  const AthleteProfileSheet({
    required this.initialProfile,
    super.key,
  });

  @override
  State<AthleteProfileSheet> createState() => _AthleteProfileSheetState();
}

class _AthleteProfileSheetState extends State<AthleteProfileSheet> {
  late double _weightKg;
  late int _ageYears;
  late bool _isMale;
  late bool _useCustomMaxHr;
  late int _customMaxHr;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _weightKg = widget.initialProfile.weightKg;
    _ageYears = widget.initialProfile.ageYears;
    _isMale = widget.initialProfile.isMale;
    _useCustomMaxHr = widget.initialProfile.customMaxHeartRate != null;
    _customMaxHr =
        widget.initialProfile.customMaxHeartRate ??
        widget.initialProfile.theoreticalMaxHeartRate;
  }

  AthleteProfile get _draftProfile => AthleteProfile(
    weightKg: double.parse(_weightKg.toStringAsFixed(1)),
    ageYears: _ageYears,
    isMale: _isMale,
    customMaxHeartRate: _useCustomMaxHr ? _customMaxHr : null,
  );

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final profile = _draftProfile;
    await profile.save();
    await HapticFeedback.lightImpact();
    if (!mounted) return;
    Navigator.of(context).pop(profile);
  }

  @override
  Widget build(BuildContext context) {
    final profile = _draftProfile;
    final maxHr = profile.maxHeartRate;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

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
              // Poignée
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

              // En-tête
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
                      Icons.monitor_heart_rounded,
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
                          'Profil physiologique',
                          style: UIUtils.titleMedium(context),
                        ),
                        Text(
                          AuthService.instance.displayName.isNotEmpty
                              ? 'Lié au compte ${AuthService.instance.displayName}'
                              : 'Calories Engo & zones cardiaques Z1–Z5',
                          style: UIUtils.bodySmall(
                            context,
                          ).copyWith(color: LKColors.textHint, fontSize: 11),
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
              SizedBox(height: UIUtils.xl),

              // Sexe physiologique
              Text(
                'SEXE PHYSIOLOGIQUE (FORMULE CALORIQUE KEYTEL)',
                style: UIUtils.bodySmall(context).copyWith(
                  color: LKColors.textHint,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              SizedBox(height: UIUtils.sm),
              Row(
                children: [
                  Expanded(
                    child: _GenderChoiceCard(
                      label: 'Homme',
                      icon: Icons.male_rounded,
                      selected: _isMale,
                      onTap: () => setState(() => _isMale = true),
                    ),
                  ),
                  SizedBox(width: UIUtils.md),
                  Expanded(
                    child: _GenderChoiceCard(
                      label: 'Femme',
                      icon: Icons.female_rounded,
                      selected: !_isMale,
                      onTap: () => setState(() => _isMale = false),
                    ),
                  ),
                ],
              ),
              SizedBox(height: UIUtils.xl),

              // Poids (kg)
              _SliderMetricCard(
                title: 'Poids corporel',
                valueLabel: '${_weightKg.toStringAsFixed(1)} kg',
                min: 35.0,
                max: 140.0,
                divisions: 210,
                value: _weightKg.clamp(35.0, 140.0),
                onChanged: (v) => setState(() => _weightKg = v),
              ),
              SizedBox(height: UIUtils.md),

              // Âge (ans)
              _SliderMetricCard(
                title: 'Âge',
                valueLabel: '$_ageYears ans',
                min: 12.0,
                max: 85.0,
                divisions: 73,
                value: _ageYears.clamp(12, 85).toDouble(),
                onChanged: (v) {
                  setState(() {
                    _ageYears = v.round();
                    if (!_useCustomMaxHr) {
                      _customMaxHr = (220 - _ageYears).clamp(120, 220);
                    }
                  });
                },
              ),
              SizedBox(height: UIUtils.md),

              // Fréquence cardiaque maximale
              Container(
                padding: UIUtils.paddingMD,
                decoration: BoxDecoration(
                  color: LKColors.surface,
                  borderRadius: UIUtils.borderRadiusAllMD,
                  border: Border.all(color: LKColors.border, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Fréquence cardiaque max (FC max)',
                                style: UIUtils.bodyMedium(context).copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _useCustomMaxHr
                                    ? 'Valeur personnalisée'
                                    : 'Calcul automatique (220 − âge)',
                                style: UIUtils.bodySmall(context).copyWith(
                                  color: LKColors.textHint,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '$maxHr bpm',
                          style: UIUtils.titleSmall(context).copyWith(
                            color: LKColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(width: UIUtils.sm),
                        Switch.adaptive(
                          value: _useCustomMaxHr,
                          activeTrackColor: LKColors.primary,
                          onChanged: (enabled) {
                            setState(() {
                              _useCustomMaxHr = enabled;
                              if (enabled) {
                                _customMaxHr = profile.theoreticalMaxHeartRate;
                              }
                            });
                          },
                        ),
                      ],
                    ),
                    if (_useCustomMaxHr) ...[
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: LKColors.primary,
                          thumbColor: LKColors.primary,
                          inactiveTrackColor: LKColors.border,
                        ),
                        child: Slider(
                          min: 130,
                          max: 220,
                          divisions: 90,
                          value: _customMaxHr.clamp(130, 220).toDouble(),
                          onChanged: (v) =>
                              setState(() => _customMaxHr = v.round()),
                        ),
                      ),
                    ],
                    SizedBox(height: UIUtils.xs),
                    // Aperçu des zones Z1-Z5
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: HeartRateZone.allZones.map((z) {
                        final minBpm = (z.minPercent * maxHr).round();
                        final maxBpm = (z.maxPercent * maxHr).round();
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: z.color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: z.color.withValues(alpha: 0.45),
                              width: 0.6,
                            ),
                          ),
                          child: Text(
                            '${z.code} $minBpm–$maxBpm',
                            style: TextStyle(
                              color: z.color,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              SizedBox(height: UIUtils.xl),

              // Bouton Enregistrer
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    'Enregistrer mon profil',
                    style: UIUtils.labelLarge(context),
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
          ),
        ),
      ),
    );
  }
}

class _GenderChoiceCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _GenderChoiceCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: UIUtils.borderRadiusAllMD,
      child: Container(
        padding: UIUtils.paddingMD,
        decoration: BoxDecoration(
          color: selected
              ? LKColors.primary.withValues(alpha: 0.15)
              : LKColors.surface,
          borderRadius: UIUtils.borderRadiusAllMD,
          border: Border.all(
            color: selected ? LKColors.primary : LKColors.border,
            width: selected ? 1.2 : 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? LKColors.primary : LKColors.textSecondary,
            ),
            SizedBox(width: UIUtils.xs),
            Text(
              label,
              style: UIUtils.bodyMedium(context).copyWith(
                color: selected ? LKColors.textPrimary : LKColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderMetricCard extends StatelessWidget {
  final String title;
  final String valueLabel;
  final double min;
  final double max;
  final int divisions;
  final double value;
  final ValueChanged<double> onChanged;

  const _SliderMetricCard({
    required this.title,
    required this.valueLabel,
    required this.min,
    required this.max,
    required this.divisions,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        UIUtils.md,
        UIUtils.md,
        UIUtils.md,
        UIUtils.xs,
      ),
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(color: LKColors.border, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: UIUtils.bodyMedium(
                  context,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                valueLabel,
                style: UIUtils.titleSmall(context).copyWith(
                  color: LKColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: LKColors.primary,
              thumbColor: LKColors.primary,
              inactiveTrackColor: LKColors.border,
            ),
            child: Slider(
              min: min,
              max: max,
              divisions: divisions,
              value: value,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
