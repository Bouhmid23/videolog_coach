import 'package:shared_preferences/shared_preferences.dart';

import '../core/auth_service.dart';

/// Profil physiologique de l'athlète lié à l'utilisateur connecté (`uid` Firebase).
///
/// Utilisé pour :
/// - estimer la dépense calorique envoyée aux lunettes ActiveLook / Engo ;
/// - personnaliser la fréquence cardiaque maximale (zones Z1–Z5 et alerte haptique Z5).
class AthleteProfile {
  const AthleteProfile({
    this.weightKg = defaultWeightKg,
    this.ageYears = defaultAgeYears,
    this.isMale = defaultIsMale,
    int? customMaxHeartRate,
    // ignore: prefer_initializing_formals
  }) : _customMaxHeartRate = customMaxHeartRate;

  static const double defaultWeightKg = 70.0;
  static const int defaultAgeYears = 30;
  static const bool defaultIsMale = true;

  static const String kWeightKgSuffix = 'weight_kg';
  static const String kAgeYearsSuffix = 'age_years';
  static const String kIsMaleSuffix = 'is_male';
  static const String kCustomMaxHrSuffix = 'custom_max_hr';

  final double weightKg;
  final int ageYears;
  final bool isMale;
  final int? _customMaxHeartRate;

  /// Fréquence cardiaque maximale personnalisée (ou `null` si calculée via `220 - âge`).
  int? get customMaxHeartRate => _customMaxHeartRate;

  /// Fréquence cardiaque maximale théorique selon `220 - âge` bornée dans `[120, 220]`.
  int get theoreticalMaxHeartRate =>
      (220 - ageYears.clamp(10, 95)).clamp(120, 220);

  /// Fréquence cardiaque maximale effective (personnalisée si définie dans `[120, 230]`,
  /// sinon [theoreticalMaxHeartRate]).
  int get maxHeartRate {
    final custom = _customMaxHeartRate;
    if (custom != null && custom >= 120 && custom <= 230) {
      return custom;
    }
    return theoreticalMaxHeartRate;
  }

  AthleteProfile copyWith({
    double? weightKg,
    int? ageYears,
    bool? isMale,
    int? customMaxHeartRate,
    bool clearCustomMaxHeartRate = false,
  }) {
    return AthleteProfile(
      weightKg: weightKg ?? this.weightKg,
      ageYears: ageYears ?? this.ageYears,
      isMale: isMale ?? this.isMale,
      customMaxHeartRate: clearCustomMaxHeartRate
          ? null
          : (customMaxHeartRate ?? _customMaxHeartRate),
    );
  }

  static String _resolvePrefix(String? uid) {
    var effectiveUid = uid?.trim();
    if (effectiveUid == null || effectiveUid.isEmpty) {
      try {
        effectiveUid = AuthService.instance.uid.trim();
      } catch (_) {
        effectiveUid = '';
      }
    }
    if (effectiveUid.isEmpty) {
      return 'athlete_';
    }
    return 'athlete_${effectiveUid}_';
  }

  /// Charge le profil de l'utilisateur [uid] (ou `AuthService.instance.uid` par défaut)
  /// depuis [SharedPreferences].
  static Future<AthleteProfile> load([
    SharedPreferences? prefs,
    String? uid,
  ]) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    final prefix = _resolvePrefix(uid);
    final weight =
        store.getDouble('$prefix$kWeightKgSuffix') ?? defaultWeightKg;
    final age = store.getInt('$prefix$kAgeYearsSuffix') ?? defaultAgeYears;
    final isMale = store.getBool('$prefix$kIsMaleSuffix') ?? defaultIsMale;
    final customMaxHr = store.getInt('$prefix$kCustomMaxHrSuffix');

    return AthleteProfile(
      weightKg: weight.clamp(30.0, 200.0),
      ageYears: age.clamp(10, 95),
      isMale: isMale,
      customMaxHeartRate: customMaxHr,
    );
  }

  /// Sauvegarde le profil de l'utilisateur [uid] (ou `AuthService.instance.uid` par défaut)
  /// dans [SharedPreferences].
  Future<void> save([
    SharedPreferences? prefs,
    String? uid,
  ]) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    final prefix = _resolvePrefix(uid);
    await store.setDouble(
      '$prefix$kWeightKgSuffix',
      weightKg.clamp(30.0, 200.0),
    );
    await store.setInt('$prefix$kAgeYearsSuffix', ageYears.clamp(10, 95));
    await store.setBool('$prefix$kIsMaleSuffix', isMale);
    if (_customMaxHeartRate != null) {
      await store.setInt('$prefix$kCustomMaxHrSuffix', _customMaxHeartRate);
    } else {
      await store.remove('$prefix$kCustomMaxHrSuffix');
    }
  }
}
