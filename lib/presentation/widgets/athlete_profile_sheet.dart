import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/account_controller.dart';
import '../../core/api_service.dart';
import '../../core/auth_service.dart';
import '../../data/account_models.dart';
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
  late String _sport;
  late String _level;
  late DateTime _birthDate;
  late bool _hasHeight;
  late int _heightCm;
  late bool _isMale;
  late double _weightKg;
  late bool _useCustomMaxHr;
  late int _customMaxHr;
  late bool _hasHrRest;
  late int _hrRest;
  late bool _healthConsent;
  bool _saving = false;
  bool _revoking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile;
    _sport = kSupportedSports.contains(p.sport)
        ? p.sport
        : AthleteProfile.defaultSport;
    _level = kSupportedLevels.contains(p.level)
        ? p.level
        : AthleteProfile.defaultLevel;
    _birthDate = p.birthDate ??
        DateTime(DateTime.now().year - p.ageYears.clamp(kMinAgeYears, 95), 1, 1);
    _hasHeight = p.heightCm != null;
    _heightCm = (p.heightCm ?? 175).clamp(100, 230);
    _isMale = p.isMale;
    _weightKg = p.weightKg.clamp(25.0, 250.0);
    _useCustomMaxHr = p.customMaxHeartRate != null;
    _customMaxHr = p.customMaxHeartRate ?? p.theoreticalMaxHeartRate;
    _hasHrRest = p.hrRest != null;
    _hrRest = (p.hrRest ?? 55).clamp(25, 120);
    _healthConsent = p.healthConsentGranted;
  }

  int get _computedAge => computeAgeYears(_birthDate);

  int get _effectiveMaxHr => _useCustomMaxHr
      ? _customMaxHr
      : (220 - _computedAge.clamp(10, 95)).clamp(120, 220);

  String _formatDateFr(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  String _formatDateIso(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final maxAllowed = DateTime(now.year - kMinAgeYears, now.month, now.day);
    final initial = _birthDate.isAfter(maxAllowed) ? maxAllowed : _birthDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 105, 1, 1),
      lastDate: maxAllowed,
      helpText: 'Date de naissance (15 ans minimum)',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _birthDate = picked;
      _error = null;
      if (!_useCustomMaxHr) {
        _customMaxHr = (220 - _computedAge.clamp(10, 95)).clamp(120, 220);
      }
    });
  }

  AthleteProfile _buildProfile({required bool includeHealthData}) {
    return AthleteProfile(
      weightKg: includeHealthData
          ? double.parse(_weightKg.toStringAsFixed(1))
          : AthleteProfile.defaultWeightKg,
      ageYears: _computedAge.clamp(kMinAgeYears, 95),
      isMale: _isMale,
      customMaxHeartRate:
          includeHealthData && _useCustomMaxHr ? _customMaxHr : null,
      sport: _sport,
      level: _level,
      birthDate: _birthDate,
      heightCm: _hasHeight ? _heightCm : null,
      hrRest: includeHealthData && _hasHrRest ? _hrRest : null,
      healthConsentGranted: includeHealthData,
      healthConsentAt: includeHealthData
          ? (widget.initialProfile.healthConsentAt ?? DateTime.now())
          : null,
    );
  }

  Future<void> _save() async {
    if (_saving || _revoking) return;

    final weightToSend =
        _healthConsent ? double.parse(_weightKg.toStringAsFixed(1)) : null;
    final hrMaxToSend = _healthConsent ? _effectiveMaxHr : null;
    final hrRestToSend = _healthConsent && _hasHrRest ? _hrRest : null;

    final validationError = AthleteProfile.validateForServer(
      sport: _sport,
      level: _level,
      birthDate: _birthDate,
      heightCm: _hasHeight ? _heightCm : null,
      weightKg: weightToSend,
      hrMax: hrMaxToSend,
      hrRest: hrRestToSend,
      healthConsentGranted: _healthConsent,
    );

    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (AuthService.instance.isSignedIn) {
        await ApiService.instance.updateAthleteProfile(
          sport: _sport,
          level: _level,
          birthDateIso: _formatDateIso(_birthDate),
          heightCm: _hasHeight ? _heightCm : null,
          weightKg: weightToSend,
          hrMax: hrMaxToSend,
          hrRest: hrRestToSend,
          healthConsent: _healthConsent,
        );
        await AccountController.instance.refresh(syncAthleteProfile: false);
      }

      final profile = _buildProfile(includeHealthData: _healthConsent);
      await profile.save();
      await HapticFeedback.lightImpact();
      if (!mounted) return;
      Navigator.of(context).pop(profile);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isForbidden && !AccountController.instance.isEmailVerified) {
        setState(() {
          _saving = false;
          _error =
              'Veuillez vérifier votre adresse e-mail avant d\'enregistrer votre profil sur le serveur.';
        });
        return;
      }
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Impossible d\'enregistrer votre profil sportif.';
      });
    }
  }

  Future<void> _revokeConsent() async {
    if (_saving || _revoking) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Révoquer le consentement santé ?'),
        content: const Text(
          'Vos données de poids et de fréquence cardiaque (FC max / FC repos) seront supprimées du serveur et les alertes reviendront aux seuils par défaut.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: LKColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Révoquer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _revoking = true;
      _error = null;
    });

    try {
      if (AuthService.instance.isSignedIn) {
        await ApiService.instance.revokeHealthConsent();
        await AccountController.instance.refresh(syncAthleteProfile: false);
      }
      final purged = _buildProfile(includeHealthData: false);
      await purged.save();
      await HapticFeedback.lightImpact();
      if (!mounted) return;
      Navigator.of(context).pop(purged);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _revoking = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _revoking = false;
        _error = 'Impossible de révoquer le consentement santé.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHr = _effectiveMaxHr;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final emailVerified = AccountController.instance.isEmailVerified;

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
                          'Profil sportif & santé',
                          style: UIUtils.titleMedium(context),
                        ),
                        Text(
                          AccountController.instance.displayName.isNotEmpty
                              ? '${AccountController.instance.displayName} • Sync serveur & Engo'
                              : 'Calories Engo & seuils cardiaques',
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
              SizedBox(height: UIUtils.lg),

              if (AuthService.instance.isSignedIn && !emailVerified) ...[
                Container(
                  padding: UIUtils.paddingMD,
                  margin: EdgeInsets.only(bottom: UIUtils.md),
                  decoration: BoxDecoration(
                    color: LKColors.warning.withValues(alpha: 0.12),
                    borderRadius: UIUtils.borderRadiusAllMD,
                    border: Border.all(
                      color: LKColors.warning.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.mark_email_unread_rounded,
                        color: LKColors.warning,
                        size: 18,
                      ),
                      SizedBox(width: UIUtils.sm),
                      Expanded(
                        child: Text(
                          'Vérifiez votre e-mail pour synchroniser le profil.',
                          style: UIUtils.bodySmall(context),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          context.push('/verify-email');
                        },
                        child: const Text('Vérifier'),
                      ),
                    ],
                  ),
                ),
              ],

              // Discipline & Niveau
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _sport,
                      decoration: UIUtils.inputDecoration(labelText: 'Sport'),
                      dropdownColor: LKColors.surfaceElevated,
                      items: kSupportedSports
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _sport = v);
                      },
                    ),
                  ),
                  SizedBox(width: UIUtils.md),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _level,
                      decoration: UIUtils.inputDecoration(labelText: 'Niveau'),
                      dropdownColor: LKColors.surfaceElevated,
                      items: kSupportedLevels
                          .map(
                            (l) => DropdownMenuItem(value: l, child: Text(l)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _level = v);
                      },
                    ),
                  ),
                ],
              ),
              SizedBox(height: UIUtils.md),

              // Date de naissance (>= 15 ans)
              InkWell(
                onTap: _pickBirthDate,
                borderRadius: UIUtils.borderRadiusAllMD,
                child: Container(
                  padding: UIUtils.paddingMD,
                  decoration: BoxDecoration(
                    color: LKColors.surface,
                    borderRadius: UIUtils.borderRadiusAllMD,
                    border: Border.all(color: LKColors.border, width: 0.6),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.cake_outlined,
                        color: LKColors.primary,
                        size: 20,
                      ),
                      SizedBox(width: UIUtils.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Date de naissance (15 ans minimum)',
                              style: UIUtils.bodySmall(context),
                            ),
                            Text(
                              '${_formatDateFr(_birthDate)} ($_computedAge ans)',
                              style: UIUtils.bodyMedium(context).copyWith(
                                color: LKColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.edit_calendar_rounded,
                        color: LKColors.textSecondary,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: UIUtils.md),

              // Sexe physiologique (calcul calorique local)
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
              SizedBox(height: UIUtils.md),

              // Taille optionnelle
              Container(
                padding: EdgeInsets.fromLTRB(
                  UIUtils.md,
                  UIUtils.xs,
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
                          'Taille (cm)',
                          style: UIUtils.bodyMedium(
                            context,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                        Row(
                          children: [
                            if (_hasHeight)
                              Text(
                                '$_heightCm cm',
                                style: UIUtils.titleSmall(context).copyWith(
                                  color: LKColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            SizedBox(width: UIUtils.sm),
                            Switch.adaptive(
                              value: _hasHeight,
                              onChanged: (v) => setState(() => _hasHeight = v),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (_hasHeight)
                      Slider(
                        min: 100,
                        max: 230,
                        divisions: 130,
                        value: _heightCm.clamp(100, 230).toDouble(),
                        onChanged: (v) =>
                            setState(() => _heightCm = v.round()),
                      ),
                  ],
                ),
              ),
              SizedBox(height: UIUtils.lg),

              // Consentement santé RGPD
              Container(
                padding: UIUtils.paddingMD,
                decoration: BoxDecoration(
                  color: (_healthConsent ? LKColors.success : LKColors.primary)
                      .withValues(alpha: 0.08),
                  borderRadius: UIUtils.borderRadiusAllMD,
                  border: Border.all(
                    color: (_healthConsent
                            ? LKColors.success
                            : LKColors.primary)
                        .withValues(alpha: 0.35),
                  ),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: CheckboxListTile(
                    value: _healthConsent,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      'Consentement données de santé (RGPD)',
                      style: UIUtils.bodyMedium(context).copyWith(
                        color: LKColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'J\'accepte l\'enregistrement de mon poids et de mes seuils cardiaques pour personnaliser les alertes en temps réel.',
                      style: UIUtils.bodySmall(context),
                    ),
                    onChanged: (v) => setState(() {
                      _healthConsent = v ?? false;
                      _error = null;
                    }),
                  ),
                ),
              ),

              if (_healthConsent) ...[
                SizedBox(height: UIUtils.md),
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

                // Fréquence cardiaque max
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
                                  _customMaxHr = (220 - _computedAge.clamp(10, 95))
                                      .clamp(120, 220);
                                }
                              });
                            },
                          ),
                        ],
                      ),
                      if (_useCustomMaxHr)
                        Slider(
                          min: 120,
                          max: 230,
                          divisions: 110,
                          value: _customMaxHr.clamp(120, 230).toDouble(),
                          onChanged: (v) =>
                              setState(() => _customMaxHr = v.round()),
                        ),
                      SizedBox(height: UIUtils.xs),
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
                SizedBox(height: UIUtils.md),

                // FC de repos
                Container(
                  padding: EdgeInsets.fromLTRB(
                    UIUtils.md,
                    UIUtils.xs,
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
                            'FC de repos (optionnelle)',
                            style: UIUtils.bodyMedium(
                              context,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),
                          Row(
                            children: [
                              if (_hasHrRest)
                                Text(
                                  '$_hrRest bpm',
                                  style: UIUtils.titleSmall(context).copyWith(
                                    color: LKColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              SizedBox(width: UIUtils.sm),
                              Switch.adaptive(
                                value: _hasHrRest,
                                onChanged: (v) =>
                                    setState(() => _hasHrRest = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (_hasHrRest)
                        Slider(
                          min: 25,
                          max: 120,
                          divisions: 95,
                          value: _hrRest.clamp(25, 120).toDouble(),
                          onChanged: (v) =>
                              setState(() => _hrRest = v.round()),
                        ),
                    ],
                  ),
                ),
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
                    style: UIUtils.bodySmall(
                      context,
                    ).copyWith(color: LKColors.danger),
                  ),
                ),
              ],
              SizedBox(height: UIUtils.xl),

              // Bouton Enregistrer
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (_saving || _revoking) ? null : _save,
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
                    _saving ? 'Enregistrement…' : 'Enregistrer mon profil',
                    style: UIUtils.labelLarge(
                      context,
                    ).copyWith(color: Colors.white),
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

              if (widget.initialProfile.healthConsentGranted) ...[
                SizedBox(height: UIUtils.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: (_saving || _revoking) ? null : _revokeConsent,
                    icon: const Icon(
                      Icons.privacy_tip_outlined,
                      size: 18,
                      color: LKColors.danger,
                    ),
                    label: Text(
                      _revoking
                          ? 'Révocation…'
                          : 'Retirer mon consentement santé',
                      style: UIUtils.labelMedium(
                        context,
                      ).copyWith(color: LKColors.danger),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: LKColors.danger.withValues(alpha: 0.5),
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
