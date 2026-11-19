import 'training_models.dart';

DateTime? _parseDate(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value.trim());
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

bool _asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final lower = value.trim().toLowerCase();
    return lower == 'true' || lower == '1' || lower == 'yes';
  }
  return false;
}

/// Point journalier de la courbe PMC (Performance Management Chart).
class PmcEntry {
  const PmcEntry({
    required this.dateIso,
    this.date,
    this.ctl = 0,
    this.atl = 0,
    this.tsb = 0,
    this.rampRate,
    this.tss,
    this.projected = false,
  });

  final String dateIso;
  final DateTime? date;
  final double ctl;
  final double atl;
  final double tsb;
  final double? rampRate;
  final double? tss;
  final bool projected;

  factory PmcEntry.fromJson(Map<String, dynamic> json) {
    final rawDate = (json['date'] ?? json['day'])?.toString() ?? '';
    final normalizedIso = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;
    final ctl = _asDouble(json['ctl'] ?? json['fitness']) ?? 0;
    final atl = _asDouble(json['atl'] ?? json['fatigue']) ?? 0;
    final tsb = _asDouble(json['tsb'] ?? json['form'] ?? json['freshness']) ?? (ctl - atl);
    return PmcEntry(
      dateIso: normalizedIso,
      date: _parseDate(rawDate),
      ctl: ctl,
      atl: atl,
      tsb: tsb,
      rampRate: _asDouble(json['ramp_rate'] ?? json['ctl_ramp_rate']),
      tss: _asDouble(json['tss'] ?? json['daily_tss']),
      projected: _asBool(json['projected'] ?? json['is_projected']),
    );
  }
}

/// Réponse complète de `GET /v1/orgs/{org_id}/analytics/pmc`.
class PmcResponse {
  const PmcResponse({
    this.series = const [],
    this.current,
    this.goals = const [],
  });

  final List<PmcEntry> series;
  final PmcEntry? current;
  final List<CalendarGoal> goals;

  PmcEntry? todayOrLatest([DateTime? now]) {
    final targetIso = formatIsoDate(now ?? DateTime.now());
    for (final entry in series) {
      if (entry.dateIso == targetIso) return entry;
    }
    if (current != null) return current;
    final actuals = series.where((e) => !e.projected).toList();
    if (actuals.isNotEmpty) return actuals.last;
    if (series.isNotEmpty) return series.last;
    return null;
  }

  static String tsbStatusLabel(double tsb) {
    if (tsb >= 10) return 'Très frais';
    if (tsb >= -5) return 'Optimal';
    if (tsb >= -20) return 'Charge productive';
    return 'Fatigue élevée';
  }

  factory PmcResponse.fromJson(Map<String, dynamic> json) {
    final rawSeries =
        json['series'] ?? json['points'] ?? json['days'] ?? json['items'] ?? json['pmc'];
    final series = rawSeries is List
        ? rawSeries
            .whereType<Map>()
            .map((e) => PmcEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <PmcEntry>[];

    final rawCurrent = json['current'] ?? json['today'] ?? json['summary'];
    final current = rawCurrent is Map
        ? PmcEntry.fromJson(Map<String, dynamic>.from(rawCurrent))
        : null;

    final rawGoals = json['goals'];
    final goals = rawGoals is List
        ? rawGoals
            .whereType<Map>()
            .map((g) => CalendarGoal.fromJson(Map<String, dynamic>.from(g)))
            .toList()
        : <CalendarGoal>[];

    return PmcResponse(
      series: series,
      current: current,
      goals: goals,
    );
  }
}

/// Zone d'entraînement calculée (puissance ou fréquence cardiaque).
class ThresholdZone {
  const ThresholdZone({
    required this.code,
    required this.name,
    required this.rangeLabel,
    this.minValue,
    this.maxValue,
  });

  final String code;
  final String name;
  final String rangeLabel;
  final int? minValue;
  final int? maxValue;

  factory ThresholdZone.fromJson(Map<String, dynamic> json, {String unit = ''}) {
    final code = (json['code'] ?? json['zone'] ?? json['name'] ?? '').toString();
    final name = (json['label'] ?? json['name'] ?? code).toString();
    final minVal = _asInt(json['min'] ?? json['low'] ?? json['min_w'] ?? json['min_bpm']);
    final maxVal = _asInt(json['max'] ?? json['high'] ?? json['max_w'] ?? json['max_bpm']);
    final suffix = unit.isEmpty ? '' : ' $unit';
    final rangeLabel = minVal != null && maxVal != null
        ? '$minVal–$maxVal$suffix'
        : minVal != null
            ? '≥ $minVal$suffix'
            : maxVal != null
                ? '≤ $maxVal$suffix'
                : '—';
    return ThresholdZone(
      code: code,
      name: name,
      rangeLabel: rangeLabel,
      minValue: minVal,
      maxValue: maxVal,
    );
  }
}

/// Seuils physiologiques actifs d'un athlète pour une discipline.
class AthleteThreshold {
  const AthleteThreshold({
    required this.sport,
    this.effectiveFrom,
    this.ftpW,
    this.lthrBpm,
    this.thresholdPaceSecPerKm,
    this.cssSecPer100m,
    this.powerZones = const [],
    this.hrZones = const [],
  });

  final String sport;
  final DateTime? effectiveFrom;
  final int? ftpW;
  final int? lthrBpm;
  final int? thresholdPaceSecPerKm;
  final int? cssSecPer100m;
  final List<ThresholdZone> powerZones;
  final List<ThresholdZone> hrZones;

  List<ThresholdZone> get effectivePowerZones {
    if (powerZones.isNotEmpty) return powerZones;
    final ftp = ftpW;
    if (ftp == null || ftp <= 0) return const [];
    return buildPowerZones(ftp);
  }

  List<ThresholdZone> get effectiveHrZones {
    if (hrZones.isNotEmpty) return hrZones;
    final lthr = lthrBpm;
    if (lthr == null || lthr <= 0) return const [];
    return buildLthrZones(lthr);
  }

  /// Modèle Coggan à 7 zones à partir de la FTP (en Watts).
  static List<ThresholdZone> buildPowerZones(int ftpW) {
    if (ftpW <= 0) return const [];
    final z1Max = (ftpW * 0.55).round();
    final z2Min = z1Max + 1;
    final z2Max = (ftpW * 0.75).round();
    final z3Min = z2Max + 1;
    final z3Max = (ftpW * 0.90).round();
    final z4Min = z3Max + 1;
    final z4Max = (ftpW * 1.05).round();
    final z5Min = z4Max + 1;
    final z5Max = (ftpW * 1.20).round();
    final z6Min = z5Max + 1;
    final z6Max = (ftpW * 1.50).round();
    final z7Min = z6Max + 1;
    return [
      ThresholdZone(code: 'Z1', name: 'Récupération active', rangeLabel: '< $z2Min W', maxValue: z1Max),
      ThresholdZone(code: 'Z2', name: 'Endurance', rangeLabel: '$z2Min–$z2Max W', minValue: z2Min, maxValue: z2Max),
      ThresholdZone(code: 'Z3', name: 'Tempo', rangeLabel: '$z3Min–$z3Max W', minValue: z3Min, maxValue: z3Max),
      ThresholdZone(code: 'Z4', name: 'Seuil lactique', rangeLabel: '$z4Min–$z4Max W', minValue: z4Min, maxValue: z4Max),
      ThresholdZone(code: 'Z5', name: 'VO2 max', rangeLabel: '$z5Min–$z5Max W', minValue: z5Min, maxValue: z5Max),
      ThresholdZone(code: 'Z6', name: 'Anaérobie', rangeLabel: '$z6Min–$z6Max W', minValue: z6Min, maxValue: z6Max),
      ThresholdZone(code: 'Z7', name: 'Neuromusculaire', rangeLabel: '≥ $z7Min W', minValue: z7Min),
    ];
  }

  /// Modèle Friel à 5 zones à partir de la FC au seuil (LTHR en bpm).
  static List<ThresholdZone> buildLthrZones(int lthrBpm) {
    if (lthrBpm <= 0) return const [];
    final z1Max = (lthrBpm * 0.81).round();
    final z2Min = z1Max + 1;
    final z2Max = (lthrBpm * 0.89).round();
    final z3Min = z2Max + 1;
    final z3Max = (lthrBpm * 0.93).round();
    final z4Min = z3Max + 1;
    final z4Max = (lthrBpm * 0.99).round();
    final z5Min = z4Max + 1;
    return [
      ThresholdZone(code: 'Z1', name: 'Récupération', rangeLabel: '< $z2Min bpm', maxValue: z1Max),
      ThresholdZone(code: 'Z2', name: 'Aérobie', rangeLabel: '$z2Min–$z2Max bpm', minValue: z2Min, maxValue: z2Max),
      ThresholdZone(code: 'Z3', name: 'Tempo', rangeLabel: '$z3Min–$z3Max bpm', minValue: z3Min, maxValue: z3Max),
      ThresholdZone(code: 'Z4', name: 'Seuil', rangeLabel: '$z4Min–$z4Max bpm', minValue: z4Min, maxValue: z4Max),
      ThresholdZone(code: 'Z5', name: 'VO2 / Supra-seuil', rangeLabel: '≥ $z5Min bpm', minValue: z5Min),
    ];
  }

  factory AthleteThreshold.fromJson(
    Map<String, dynamic> json, {
    String? fallbackSport,
  }) {
    final rawPowerZones = json['power_zones'];
    final rawHrZones = json['hr_zones'];
    return AthleteThreshold(
      sport: (json['sport'] ?? fallbackSport ?? 'cyclisme').toString(),
      effectiveFrom: _parseDate(json['effective_from'] ?? json['updated_at']),
      ftpW: _asInt(json['ftp_w'] ?? json['ftp']),
      lthrBpm: _asInt(json['lthr_bpm'] ?? json['lthr']),
      thresholdPaceSecPerKm: _asInt(json['threshold_pace_sec_per_km']),
      cssSecPer100m: _asInt(json['css_sec_per_100m']),
      powerZones: rawPowerZones is List
          ? rawPowerZones
              .whereType<Map>()
              .map((z) => ThresholdZone.fromJson(Map<String, dynamic>.from(z), unit: 'W'))
              .toList()
          : const [],
      hrZones: rawHrZones is List
          ? rawHrZones
              .whereType<Map>()
              .map((z) => ThresholdZone.fromJson(Map<String, dynamic>.from(z), unit: 'bpm'))
              .toList()
          : const [],
    );
  }

  static List<AthleteThreshold> parseList(Object? decoded) {
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((e) => AthleteThreshold.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      final listCandidate = map['thresholds'] ?? map['items'] ?? map['active'];
      if (listCandidate is List) {
        return listCandidate
            .whereType<Map>()
            .map((e) => AthleteThreshold.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      if (listCandidate is Map) {
        final out = <AthleteThreshold>[];
        for (final entry in listCandidate.entries) {
          if (entry.value is Map) {
            out.add(
              AthleteThreshold.fromJson(
                Map<String, dynamic>.from(entry.value as Map),
                fallbackSport: entry.key.toString(),
              ),
            );
          }
        }
        return out;
      }
      if (map.containsKey('ftp_w') ||
          map.containsKey('lthr_bpm') ||
          map.containsKey('sport')) {
        return [AthleteThreshold.fromJson(map)];
      }
      final bySport = <AthleteThreshold>[];
      for (final entry in map.entries) {
        if (entry.value is Map) {
          bySport.add(
            AthleteThreshold.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
              fallbackSport: entry.key.toString(),
            ),
          );
        }
      }
      return bySport;
    }
    return const [];
  }
}
