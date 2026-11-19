import 'package:shared_preferences/shared_preferences.dart';

import '../core/auth_service.dart';
import 'account_models.dart';

/// Profil physiologique et sportif de l'athlète lié à l'utilisateur connecté (`uid` Firebase).
///
/// Utilisé pour :
/// - synchroniser `PUT /v1/me/athlete-profile` et `DELETE /v1/me/health-consent` ;
/// - estimer la dépense calorique envoyée aux lunettes ActiveLook / Engo ;
/// - personnaliser la fréquence cardiaque maximale (zones Z1–Z5 et alerte haptique Z5).
class AthleteProfile {
  const AthleteProfile({
    this.weightKg = defaultWeightKg,
    this.ageYears = defaultAgeYears,
    this.isMale = defaultIsMale,
    int? customMaxHeartRate,
    this.sport = defaultSport,
    this.level = defaultLevel,
    this.birthDate,
    this.heightCm,
    this.hrRest,
    this.healthConsentGranted = false,
    this.healthConsentAt,
    // ignore: prefer_initializing_formals
  }) : _customMaxHeartRate = customMaxHeartRate;

  static const double defaultWeightKg = 70.0;
  static const int defaultAgeYears = 30;
  static const bool defaultIsMale = true;
  static const String defaultSport = 'autre';
  static const String defaultLevel = 'loisir';

  static const String kWeightKgSuffix = 'weight_kg';
  static const String kAgeYearsSuffix = 'age_years';
  static const String kIsMaleSuffix = 'is_male';
  static const String kCustomMaxHrSuffix = 'custom_max_hr';
  static const String kSportSuffix = 'sport';
  static const String kLevelSuffix = 'level';
  static const String kBirthDateSuffix = 'birth_date';
  static const String kHeightCmSuffix = 'height_cm';
  static const String kHrRestSuffix = 'hr_rest';
  static const String kHealthConsentSuffix = 'health_consent';
  static const String kHealthConsentAtSuffix = 'health_consent_at';

  final double weightKg;
  final int ageYears;
  final bool isMale;
  final int? _customMaxHeartRate;
  final String sport;
  final String level;
  final DateTime? birthDate;
  final int? heightCm;
  final int? hrRest;
  final bool healthConsentGranted;
  final DateTime? healthConsentAt;

  /// Fréquence cardiaque maximale personnalisée (ou `null` si calculée via `220 - âge`).
  int? get customMaxHeartRate => _customMaxHeartRate;

  /// Âge effectif calculé depuis [birthDate] si disponible, sinon [ageYears].
  int get effectiveAgeYears =>
      birthDate != null ? computeAgeYears(birthDate!) : ageYears;

  /// Fréquence cardiaque maximale théorique selon `220 - âge` bornée dans `[120, 220]`.
  int get theoreticalMaxHeartRate =>
      (220 - effectiveAgeYears.clamp(10, 95)).clamp(120, 220);

  /// Fréquence cardiaque maximale effective (personnalisée si définie dans `[120, 230]`,
  /// sinon [theoreticalMaxHeartRate]).
  int get maxHeartRate {
    final custom = _customMaxHeartRate;
    if (custom != null && custom >= 120 && custom <= 230) {
      return custom;
    }
    return theoreticalMaxHeartRate;
  }

  /// Date de naissance formatée ISO (`YYYY-MM-DD`) pour l'API backend.
  String get birthDateIso {
    final d = birthDate ??
        DateTime(
          DateTime.now().year - ageYears.clamp(kMinAgeYears, 100),
          1,
          1,
        );
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  /// Valide le profil vis-à-vis des règles serveur `/v1/me/athlete-profile`.
  /// Retourne `null` si valide, sinon un message d'erreur explicite.
  static String? validateForServer({
    required String sport,
    required String level,
    required DateTime? birthDate,
    int? heightCm,
    double? weightKg,
    int? hrMax,
    int? hrRest,
    required bool healthConsentGranted,
  }) {
    if (!kSupportedSports.contains(sport)) {
      return 'Sport non reconnu.';
    }
    if (!kSupportedLevels.contains(level)) {
      return 'Niveau sportif non reconnu.';
    }
    if (birthDate == null) {
      return 'La date de naissance est obligatoire.';
    }
    final age = computeAgeYears(birthDate);
    if (age < kMinAgeYears) {
      return 'L\'accès à la plateforme est interdit aux personnes de moins de $kMinAgeYears ans.';
    }
    if (age > 110) {
      return 'Date de naissance invalide.';
    }
    if (heightCm != null && (heightCm < 100 || heightCm > 230)) {
      return 'La taille doit être comprise entre 100 et 230 cm.';
    }
    if (weightKg != null && (weightKg < 25 || weightKg > 250)) {
      return 'Le poids doit être compris entre 25 et 250 kg.';
    }
    if (hrMax != null && (hrMax < 40 || hrMax > 250)) {
      return 'La FC maximale doit être comprise entre 40 et 250 bpm.';
    }
    if (hrRest != null && (hrRest < 25 || hrRest > 120)) {
      return 'La FC de repos doit être comprise entre 25 et 120 bpm.';
    }
    if (hrMax != null && hrRest != null && hrRest >= hrMax) {
      return 'La FC de repos doit être strictement inférieure à la FC maximale.';
    }
    final hasHealthData = weightKg != null || hrMax != null || hrRest != null;
    if (hasHealthData && !healthConsentGranted) {
      return 'Le consentement santé RGPD est requis pour enregistrer poids ou fréquence cardiaque.';
    }
    return null;
  }

  AthleteProfile copyWith({
    double? weightKg,
    int? ageYears,
    bool? isMale,
    int? customMaxHeartRate,
    bool clearCustomMaxHeartRate = false,
    String? sport,
    String? level,
    DateTime? birthDate,
    int? heightCm,
    bool clearHeightCm = false,
    int? hrRest,
    bool clearHrRest = false,
    bool? healthConsentGranted,
    DateTime? healthConsentAt,
    bool clearHealthConsentAt = false,
  }) {
    return AthleteProfile(
      weightKg: weightKg ?? this.weightKg,
      ageYears: ageYears ?? this.ageYears,
      isMale: isMale ?? this.isMale,
      customMaxHeartRate: clearCustomMaxHeartRate
          ? null
          : (customMaxHeartRate ?? _customMaxHeartRate),
      sport: sport ?? this.sport,
      level: level ?? this.level,
      birthDate: birthDate ?? this.birthDate,
      heightCm: clearHeightCm ? null : (heightCm ?? this.heightCm),
      hrRest: clearHrRest ? null : (hrRest ?? this.hrRest),
      healthConsentGranted: healthConsentGranted ?? this.healthConsentGranted,
      healthConsentAt: clearHealthConsentAt
          ? null
          : (healthConsentAt ?? this.healthConsentAt),
    );
  }

  /// Fusionne les données serveur issues de `GET /v1/me` dans le profil local.
  factory AthleteProfile.fromServer({
    required ServerAthleteProfile? serverProfile,
    required HealthConsent? healthConsent,
    AthleteProfile fallback = const AthleteProfile(),
  }) {
    if (serverProfile == null) {
      return fallback.copyWith(
        healthConsentGranted: healthConsent?.granted ?? false,
        healthConsentAt: healthConsent?.grantedAt,
        clearHealthConsentAt: healthConsent?.grantedAt == null,
      );
    }
    final consentGranted = healthConsent?.granted == true;
    final birth = serverProfile.birthDate ?? fallback.birthDate;
    final computedAge = birth != null
        ? computeAgeYears(birth).clamp(kMinAgeYears, 95)
        : fallback.ageYears;

    return AthleteProfile(
      weightKg: consentGranted && serverProfile.weightKg != null
          ? serverProfile.weightKg!.clamp(25.0, 250.0)
          : fallback.weightKg,
      ageYears: computedAge,
      isMale: fallback.isMale,
      customMaxHeartRate: consentGranted ? serverProfile.hrMax : null,
      sport: kSupportedSports.contains(serverProfile.sport)
          ? serverProfile.sport
          : defaultSport,
      level: kSupportedLevels.contains(serverProfile.level)
          ? serverProfile.level
          : defaultLevel,
      birthDate: birth,
      heightCm: serverProfile.heightCm,
      hrRest: consentGranted ? serverProfile.hrRest : null,
      healthConsentGranted: consentGranted,
      healthConsentAt: consentGranted ? healthConsent?.grantedAt : null,
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
    final sport = store.getString('$prefix$kSportSuffix') ?? defaultSport;
    final level = store.getString('$prefix$kLevelSuffix') ?? defaultLevel;
    final birthStr = store.getString('$prefix$kBirthDateSuffix');
    final birthDate = birthStr != null ? DateTime.tryParse(birthStr) : null;
    final heightCm = store.getInt('$prefix$kHeightCmSuffix');
    final hrRest = store.getInt('$prefix$kHrRestSuffix');
    final consentGranted =
        store.getBool('$prefix$kHealthConsentSuffix') ?? false;
    final consentAtStr = store.getString('$prefix$kHealthConsentAtSuffix');
    final consentAt =
        consentAtStr != null ? DateTime.tryParse(consentAtStr) : null;

    return AthleteProfile(
      weightKg: weight.clamp(25.0, 250.0),
      ageYears: age.clamp(10, 95),
      isMale: isMale,
      customMaxHeartRate: customMaxHr,
      sport: sport,
      level: level,
      birthDate: birthDate,
      heightCm: heightCm,
      hrRest: hrRest,
      healthConsentGranted: consentGranted,
      healthConsentAt: consentAt,
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
      weightKg.clamp(25.0, 250.0),
    );
    await store.setInt(
      '$prefix$kAgeYearsSuffix',
      effectiveAgeYears.clamp(10, 95),
    );
    await store.setBool('$prefix$kIsMaleSuffix', isMale);
    if (_customMaxHeartRate != null) {
      await store.setInt('$prefix$kCustomMaxHrSuffix', _customMaxHeartRate);
    } else {
      await store.remove('$prefix$kCustomMaxHrSuffix');
    }
    await store.setString('$prefix$kSportSuffix', sport);
    await store.setString('$prefix$kLevelSuffix', level);
    if (birthDate != null) {
      await store.setString('$prefix$kBirthDateSuffix', birthDateIso);
    } else {
      await store.remove('$prefix$kBirthDateSuffix');
    }
    if (heightCm != null) {
      await store.setInt('$prefix$kHeightCmSuffix', heightCm!);
    } else {
      await store.remove('$prefix$kHeightCmSuffix');
    }
    if (hrRest != null) {
      await store.setInt('$prefix$kHrRestSuffix', hrRest!);
    } else {
      await store.remove('$prefix$kHrRestSuffix');
    }
    await store.setBool('$prefix$kHealthConsentSuffix', healthConsentGranted);
    if (healthConsentAt != null) {
      await store.setString(
        '$prefix$kHealthConsentAtSuffix',
        healthConsentAt!.toIso8601String(),
      );
    } else {
      await store.remove('$prefix$kHealthConsentAtSuffix');
    }
  }
}
