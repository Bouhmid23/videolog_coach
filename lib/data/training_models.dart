/// Modèles de calendrier d'entraînement, séances structurées, objectifs et
/// questionnaire « Forme du jour » (wellness) pour le MVP Videolog.
library;

DateTime? _parseTrainingDate(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value.trim());
}

int? _asIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double? _asDoubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

String formatIsoDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String formatDurationSeconds(int? seconds) {
  if (seconds == null || seconds <= 0) return '—';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0 && m > 0) return '${h}h ${m.toString().padLeft(2, '0')}';
  if (h > 0) return '${h}h';
  if (m > 0) return '$m min';
  return '${seconds}s';
}

class WorkoutBlock {
  const WorkoutBlock({
    this.label = '',
    this.zone,
    this.durationS = 0,
    this.intensityPct,
    this.colorHex,
    this.targetLow,
    this.targetHigh,
  });

  final String label;
  final String? zone;
  final int durationS;
  final double? intensityPct;
  final String? colorHex;
  final double? targetLow;
  final double? targetHigh;

  factory WorkoutBlock.fromJson(Map<String, dynamic> json) {
    return WorkoutBlock(
      label: (json['label'] ?? json['name'] ?? json['type'] ?? '').toString(),
      zone: json['zone']?.toString(),
      durationS: _asIntOrNull(json['duration_s'] ?? json['duration']) ?? 0,
      intensityPct: _asDoubleOrNull(
        json['intensity_pct'] ?? json['intensity'] ?? json['pct'],
      ),
      colorHex: json['color']?.toString(),
      targetLow: _asDoubleOrNull(json['target_low']),
      targetHigh: _asDoubleOrNull(json['target_high']),
    );
  }
}

class WorkoutStep {
  const WorkoutStep({
    this.name = '',
    this.type = 'interval',
    this.durationS,
    this.distanceM,
    this.targetType,
    this.targetLow,
    this.targetHigh,
    this.targetLabel,
    this.notes,
    this.repeatCount,
    this.steps = const [],
  });

  final String name;
  final String type;
  final int? durationS;
  final double? distanceM;
  final String? targetType;
  final double? targetLow;
  final double? targetHigh;
  final String? targetLabel;
  final String? notes;
  final int? repeatCount;
  final List<WorkoutStep> steps;

  String get displayTarget {
    if (targetLabel != null && targetLabel!.trim().isNotEmpty) {
      return targetLabel!.trim();
    }
    if (targetLow != null && targetHigh != null) {
      final low = targetLow!.round();
      final high = targetHigh!.round();
      final unit = _unitForTarget(targetType);
      return '$low–$high$unit';
    }
    if (targetLow != null) {
      return '${targetLow!.round()}${_unitForTarget(targetType)}';
    }
    return '';
  }

  static String _unitForTarget(String? type) {
    switch (type?.toLowerCase()) {
      case 'power':
      case 'watts':
        return ' W';
      case 'ftp_pct':
      case 'percent_ftp':
        return ' % FTP';
      case 'hr':
      case 'heart_rate':
        return ' bpm';
      case 'cadence':
        return ' rpm';
      default:
        return '';
    }
  }

  factory WorkoutStep.fromJson(Map<String, dynamic> json) {
    final nested = json['steps'];
    return WorkoutStep(
      name: (json['name'] ?? json['label'] ?? json['title'] ?? '').toString(),
      type: (json['type'] ?? json['step_type'] ?? 'interval').toString(),
      durationS: _asIntOrNull(json['duration_s'] ?? json['duration']),
      distanceM: _asDoubleOrNull(json['distance_m'] ?? json['distance']),
      targetType: json['target_type']?.toString(),
      targetLow: _asDoubleOrNull(json['target_low']),
      targetHigh: _asDoubleOrNull(json['target_high']),
      targetLabel: json['target_label']?.toString(),
      notes: json['notes']?.toString(),
      repeatCount: _asIntOrNull(json['repeat'] ?? json['repeat_count']),
      steps: nested is List
          ? nested
              .whereType<Map>()
              .map((s) => WorkoutStep.fromJson(Map<String, dynamic>.from(s)))
              .toList()
          : const [],
    );
  }
}

class WorkoutCompliance {
  const WorkoutCompliance({
    this.score,
    this.color,
    this.label,
  });

  final double? score;
  final String? color;
  final String? label;

  factory WorkoutCompliance.fromJson(Map<String, dynamic> json) {
    return WorkoutCompliance(
      score: _asDoubleOrNull(json['score']),
      color: json['color']?.toString(),
      label: json['label']?.toString(),
    );
  }
}

class PlannedWorkout {
  const PlannedWorkout({
    required this.id,
    required this.title,
    this.sport = 'autre',
    this.date,
    this.dateIso,
    this.startTime,
    this.estimatedDurationS,
    this.estimatedTss,
    this.status = 'planned',
    this.description,
    this.coachNote,
    this.compliance,
    this.blocks = const [],
    this.steps = const [],
  });

  final String id;
  final String title;
  final String sport;
  final DateTime? date;
  final String? dateIso;
  final String? startTime;
  final int? estimatedDurationS;
  final double? estimatedTss;
  final String status; // planned | done | partial | missed
  final String? description;
  final String? coachNote;
  final WorkoutCompliance? compliance;
  final List<WorkoutBlock> blocks;
  final List<WorkoutStep> steps;

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'done':
      case 'completed':
        return 'Réalisée';
      case 'partial':
        return 'Partielle';
      case 'missed':
      case 'skipped':
        return 'Manquée';
      default:
        return 'Planifiée';
    }
  }

  /// Indique si la séance planifiée est passée (commentaires en lecture seule).
  bool isExpiredAt(DateTime now) {
    final d = date;
    if (d == null) return false;
    final plannedDay = DateTime(d.year, d.month, d.day);
    final todayDay = DateTime(now.year, now.month, now.day);
    if (plannedDay.isBefore(todayDay)) return true;
    if (plannedDay == todayDay && startTime != null) {
      final parts = startTime!.trim().split(':');
      if (parts.length == 2) {
        final hh = int.tryParse(parts[0]);
        final mm = int.tryParse(parts[1]);
        if (hh != null && mm != null) {
          final endUtc = DateTime.utc(d.year, d.month, d.day, hh, mm).add(
            Duration(seconds: estimatedDurationS ?? 3600),
          );
          return endUtc.isBefore(now.toUtc());
        }
      }
    }
    return false;
  }

  factory PlannedWorkout.fromJson(Map<String, dynamic> json) {
    final rawDate =
        (json['date'] ?? json['scheduled_date'] ?? json['planned_date'])
            ?.toString();
    final rawCompliance = json['compliance'];
    final rawBlocks = json['blocks'];
    final rawSteps = json['steps'];
    return PlannedWorkout(
      id: (json['id'] ?? json['planned_id'] ?? '').toString(),
      title: (json['title'] ?? json['name'] ?? 'Séance planifiée').toString(),
      sport: (json['sport'] ?? 'autre').toString(),
      date: _parseTrainingDate(rawDate),
      dateIso: rawDate,
      startTime: json['start_time']?.toString(),
      estimatedDurationS: _asIntOrNull(
        json['estimated_duration_s'] ?? json['duration_s'],
      ),
      estimatedTss: _asDoubleOrNull(json['estimated_tss'] ?? json['tss']),
      status: (json['status'] ?? 'planned').toString(),
      description: json['description']?.toString(),
      coachNote: json['coach_note']?.toString(),
      compliance: rawCompliance is Map
          ? WorkoutCompliance.fromJson(Map<String, dynamic>.from(rawCompliance))
          : null,
      blocks: rawBlocks is List
          ? rawBlocks
              .whereType<Map>()
              .map((b) => WorkoutBlock.fromJson(Map<String, dynamic>.from(b)))
              .toList()
          : const [],
      steps: rawSteps is List
          ? rawSteps
              .whereType<Map>()
              .map((s) => WorkoutStep.fromJson(Map<String, dynamic>.from(s)))
              .toList()
          : const [],
    );
  }
}

class CalendarActivitySummary {
  const CalendarActivitySummary({
    required this.id,
    required this.title,
    this.sport = 'autre',
    this.startedAt,
    this.durationS,
    this.distanceM,
    this.tss,
    this.avgHr,
    this.plannedWorkoutId,
  });

  final String id;
  final String title;
  final String sport;
  final DateTime? startedAt;
  final int? durationS;
  final double? distanceM;
  final double? tss;
  final int? avgHr;
  final String? plannedWorkoutId;

  factory CalendarActivitySummary.fromJson(Map<String, dynamic> json) {
    return CalendarActivitySummary(
      id: (json['id'] ?? json['activity_id'] ?? '').toString(),
      title: (json['title'] ?? json['name'] ?? 'Activité').toString(),
      sport: (json['sport'] ?? 'autre').toString(),
      startedAt: _parseTrainingDate(
        json['started_at'] ?? json['date'] ?? json['start_time'],
      ),
      durationS: _asIntOrNull(json['duration_s'] ?? json['moving_time_s']),
      distanceM: _asDoubleOrNull(json['distance_m']),
      tss: _asDoubleOrNull(json['tss']),
      avgHr: _asIntOrNull(json['avg_hr']),
      plannedWorkoutId: json['planned_workout_id']?.toString(),
    );
  }
}

class CalendarGoal {
  const CalendarGoal({
    required this.id,
    required this.title,
    this.date,
    this.priority = 'B',
    this.sport,
  });

  final String id;
  final String title;
  final DateTime? date;
  final String priority; // A | B | C
  final String? sport;

  factory CalendarGoal.fromJson(Map<String, dynamic> json) {
    return CalendarGoal(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? json['name'] ?? 'Objectif').toString(),
      date: _parseTrainingDate(json['date'] ?? json['target_date']),
      priority: (json['priority'] ?? 'B').toString().toUpperCase(),
      sport: json['sport']?.toString(),
    );
  }
}

class WeeklyTotal {
  const WeeklyTotal({
    this.weekStart,
    this.durationS = 0,
    this.distanceM = 0,
    this.tss = 0,
    this.plannedTss = 0,
    this.sessionsCount = 0,
  });

  final DateTime? weekStart;
  final int durationS;
  final double distanceM;
  final double tss;
  final double plannedTss;
  final int sessionsCount;

  factory WeeklyTotal.fromJson(Map<String, dynamic> json) {
    return WeeklyTotal(
      weekStart: _parseTrainingDate(json['week_start'] ?? json['week']),
      durationS: _asIntOrNull(json['duration_s'] ?? json['total_duration_s']) ?? 0,
      distanceM: _asDoubleOrNull(json['distance_m'] ?? json['total_distance_m']) ?? 0,
      tss: _asDoubleOrNull(json['tss'] ?? json['actual_tss']) ?? 0,
      plannedTss: _asDoubleOrNull(json['planned_tss']) ?? 0,
      sessionsCount:
          _asIntOrNull(json['sessions_count'] ?? json['activities_count']) ?? 0,
    );
  }
}

class CalendarResponse {
  const CalendarResponse({
    this.plannedWorkouts = const [],
    this.activities = const [],
    this.goals = const [],
    this.weeklyTotals = const [],
  });

  final List<PlannedWorkout> plannedWorkouts;
  final List<CalendarActivitySummary> activities;
  final List<CalendarGoal> goals;
  final List<WeeklyTotal> weeklyTotals;

  List<PlannedWorkout> workoutsForDay(DateTime day) {
    final key = formatIsoDate(day);
    return plannedWorkouts.where((w) {
      if (w.date != null) return formatIsoDate(w.date!) == key;
      if (w.dateIso != null && w.dateIso!.length >= 10) {
        return w.dateIso!.substring(0, 10) == key;
      }
      return false;
    }).toList();
  }

  List<CalendarActivitySummary> activitiesForDay(DateTime day) {
    final key = formatIsoDate(day);
    return activities.where((a) {
      if (a.startedAt == null) return false;
      return formatIsoDate(a.startedAt!) == key;
    }).toList();
  }

  PlannedWorkout? todayWorkout([DateTime? now]) {
    final list = workoutsForDay(now ?? DateTime.now());
    return list.isEmpty ? null : list.first;
  }

  factory CalendarResponse.fromJson(Map<String, dynamic> json) {
    final rawWorkouts = json['planned_workouts'];
    final rawActivities = json['activities'];
    final rawGoals = json['goals'];
    final rawWeekly = json['weekly_totals'];

    return CalendarResponse(
      plannedWorkouts: rawWorkouts is List
          ? rawWorkouts
              .whereType<Map>()
              .map((w) => PlannedWorkout.fromJson(Map<String, dynamic>.from(w)))
              .toList()
          : const [],
      activities: rawActivities is List
          ? rawActivities
              .whereType<Map>()
              .map(
                (a) => CalendarActivitySummary.fromJson(
                  Map<String, dynamic>.from(a),
                ),
              )
              .toList()
          : const [],
      goals: rawGoals is List
          ? rawGoals
              .whereType<Map>()
              .map((g) => CalendarGoal.fromJson(Map<String, dynamic>.from(g)))
              .toList()
          : const [],
      weeklyTotals: rawWeekly is List
          ? rawWeekly
              .whereType<Map>()
              .map((t) => WeeklyTotal.fromJson(Map<String, dynamic>.from(t)))
              .toList()
          : const [],
    );
  }
}

class WellnessEntry {
  const WellnessEntry({
    required this.date,
    required this.sleepH,
    required this.sleepQuality,
    required this.fatigue,
    required this.soreness,
    required this.stress,
    required this.mood,
    this.notes,
    this.hrvMs,
    this.restingHr,
    this.weightKg,
  });

  final String date; // YYYY-MM-DD
  final double sleepH;
  final int sleepQuality; // 1..5
  final int fatigue; // 1..5
  final int soreness; // 1..5
  final int stress; // 1..5
  final int mood; // 1..5
  final String? notes;

  // Données de santé soumises uniquement si health_consent.granted == true
  final double? hrvMs;
  final int? restingHr;
  final double? weightKg;

  /// Sérialise le questionnaire en respectant la règle RGPD :
  /// `hrv_ms`, `resting_hr` et `weight_kg` ne sont inclus que si
  /// [includeHealthData] est `true`.
  Map<String, dynamic> toJson({required bool includeHealthData}) {
    return <String, dynamic>{
      'date': date,
      'sleep_h': sleepH,
      'sleep_quality': sleepQuality,
      'fatigue': fatigue,
      'soreness': soreness,
      'stress': stress,
      'mood': mood,
      if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
      if (includeHealthData && hrvMs != null) 'hrv_ms': hrvMs,
      if (includeHealthData && restingHr != null) 'resting_hr': restingHr,
      if (includeHealthData && weightKg != null) 'weight_kg': weightKg,
    };
  }
}
