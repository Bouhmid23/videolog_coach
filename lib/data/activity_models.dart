/// Modèles d'activités d'endurance, import FIT/GPX/TCX, courbes (streams)
/// et débriefing (RPE, ressenti, commentaires) pour le MVP Videolog.
library;

DateTime? _parseActivityDate(Object? value) {
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

class ActivitySummary {
  const ActivitySummary({
    required this.id,
    required this.title,
    this.orgId,
    this.uid,
    this.sport = 'autre',
    this.startedAt,
    this.durationS,
    this.distanceM,
    this.tss,
    this.normalizedPower,
    this.intensityFactor,
    this.avgHr,
    this.maxHr,
    this.avgPower,
    this.elevationGainM,
    this.plannedWorkoutId,
    this.rpe,
    this.feeling,
    this.source,
    this.sharedOrgIds = const [],
  });

  final String id;
  final String title;
  final String? orgId;
  final String? uid;
  final String sport;
  final DateTime? startedAt;
  final int? durationS;
  final double? distanceM;
  final double? tss;
  final double? normalizedPower;
  final double? intensityFactor;
  final int? avgHr;
  final int? maxHr;
  final double? avgPower;
  final double? elevationGainM;
  final String? plannedWorkoutId;
  final int? rpe; // 1..10
  final int? feeling; // 1..5
  final String? source;
  final List<String> sharedOrgIds;

  bool get isMatched =>
      plannedWorkoutId != null && plannedWorkoutId!.trim().isNotEmpty;

  factory ActivitySummary.fromJson(Map<String, dynamic> json) {
    final rawShared = json['shared_org_ids'];
    return ActivitySummary(
      id: (json['id'] ?? json['activity_id'] ?? '').toString(),
      title: (json['title'] ?? json['name'] ?? 'Activité').toString(),
      orgId: json['org_id']?.toString(),
      uid: json['uid']?.toString(),
      sport: (json['sport'] ?? 'autre').toString(),
      startedAt: _parseActivityDate(
        json['started_at'] ?? json['start_time'] ?? json['date'],
      ),
      durationS: _asIntOrNull(
        json['duration_s'] ?? json['moving_time_s'] ?? json['elapsed_time_s'],
      ),
      distanceM: _asDoubleOrNull(json['distance_m']),
      tss: _asDoubleOrNull(json['tss']),
      normalizedPower: _asDoubleOrNull(
        json['normalized_power'] ?? json['np_w'],
      ),
      intensityFactor: _asDoubleOrNull(
        json['intensity_factor'] ?? json['if'],
      ),
      avgHr: _asIntOrNull(json['avg_hr'] ?? json['average_hr']),
      maxHr: _asIntOrNull(json['max_hr']),
      avgPower: _asDoubleOrNull(json['avg_power'] ?? json['average_power']),
      elevationGainM: _asDoubleOrNull(
        json['elevation_gain_m'] ?? json['total_ascent_m'],
      ),
      plannedWorkoutId: json['planned_workout_id']?.toString(),
      rpe: _asIntOrNull(json['rpe']),
      feeling: _asIntOrNull(json['feeling']),
      source: json['source']?.toString(),
      sharedOrgIds: rawShared is List
          ? rawShared.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : const [],
    );
  }
}

class ActivityLap {
  const ActivityLap({
    required this.index,
    this.name,
    this.durationS,
    this.distanceM,
    this.avgPower,
    this.avgHr,
    this.avgCadence,
    this.avgSpeedKmh,
  });

  final int index;
  final String? name;
  final int? durationS;
  final double? distanceM;
  final double? avgPower;
  final int? avgHr;
  final double? avgCadence;
  final double? avgSpeedKmh;

  factory ActivityLap.fromJson(Map<String, dynamic> json, int fallbackIndex) {
    return ActivityLap(
      index: _asIntOrNull(json['index'] ?? json['lap_index']) ?? fallbackIndex,
      name: json['name']?.toString(),
      durationS: _asIntOrNull(json['duration_s'] ?? json['elapsed_time_s']),
      distanceM: _asDoubleOrNull(json['distance_m']),
      avgPower: _asDoubleOrNull(json['avg_power'] ?? json['average_power']),
      avgHr: _asIntOrNull(json['avg_hr'] ?? json['average_hr']),
      avgCadence: _asDoubleOrNull(json['avg_cadence']),
      avgSpeedKmh: _asDoubleOrNull(json['avg_speed_kmh']),
    );
  }
}

class ActivityVideoAsset {
  const ActivityVideoAsset({
    this.roomName,
    this.title,
    this.mp4Url,
    this.durationS,
  });

  final String? roomName;
  final String? title;
  final String? mp4Url;
  final int? durationS;

  factory ActivityVideoAsset.fromJson(Map<String, dynamic> json) {
    return ActivityVideoAsset(
      roomName: json['room_name']?.toString(),
      title: (json['title'] ?? json['filename'])?.toString(),
      mp4Url: (json['mp4_url'] ?? json['url'])?.toString(),
      durationS: _asIntOrNull(json['duration_s'] ?? json['duration']),
    );
  }
}

class ActivityDetail {
  const ActivityDetail({
    required this.summary,
    this.laps = const [],
    this.videoAssets = const [],
    this.notes,
  });

  final ActivitySummary summary;
  final List<ActivityLap> laps;
  final List<ActivityVideoAsset> videoAssets;
  final String? notes;

  ActivityDetail copyWith({
    ActivitySummary? summary,
    List<ActivityLap>? laps,
    List<ActivityVideoAsset>? videoAssets,
    String? notes,
  }) {
    return ActivityDetail(
      summary: summary ?? this.summary,
      laps: laps ?? this.laps,
      videoAssets: videoAssets ?? this.videoAssets,
      notes: notes ?? this.notes,
    );
  }

  factory ActivityDetail.fromJson(Map<String, dynamic> json) {
    final rawLaps = json['laps'];
    final rawVideos = json['video_assets'];
    final lapsList = <ActivityLap>[];
    if (rawLaps is List) {
      for (var i = 0; i < rawLaps.length; i++) {
        final item = rawLaps[i];
        if (item is Map) {
          lapsList.add(
            ActivityLap.fromJson(Map<String, dynamic>.from(item), i + 1),
          );
        }
      }
    }

    return ActivityDetail(
      summary: ActivitySummary.fromJson(json),
      laps: lapsList,
      videoAssets: rawVideos is List
          ? rawVideos
              .whereType<Map>()
              .map(
                (v) => ActivityVideoAsset.fromJson(
                  Map<String, dynamic>.from(v),
                ),
              )
              .toList()
          : const [],
      notes: json['notes']?.toString(),
    );
  }
}

class ActivityStreamPoint {
  const ActivityStreamPoint({
    required this.timeS,
    this.hr,
    this.power,
    this.speedKmh,
    this.cadence,
    this.altitudeM,
  });

  final double timeS;
  final double? hr;
  final double? power;
  final double? speedKmh;
  final double? cadence;
  final double? altitudeM;
}

class ActivityStreams {
  const ActivityStreams({this.points = const []});

  final List<ActivityStreamPoint> points;

  bool get hasHr => points.any((p) => p.hr != null);
  bool get hasPower => points.any((p) => p.power != null);
  bool get hasSpeed => points.any((p) => p.speedKmh != null);
  bool get hasAltitude => points.any((p) => p.altitudeM != null);

  /// Accepte à la fois le format orienté colonnes
  /// (`time_s: []`, `hr: []`, `power: []`, `speed_kmh: []`, `altitude_m: []`)
  /// et le format orienté lignes (`points: [...]` / `samples: [...]`).
  factory ActivityStreams.fromJson(Map<String, dynamic> json) {
    final rowList = json['points'] ?? json['samples'] ?? json['streams'];
    if (rowList is List) {
      final parsed = <ActivityStreamPoint>[];
      for (var i = 0; i < rowList.length; i++) {
        final item = rowList[i];
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final t = _asDoubleOrNull(m['time_s'] ?? m['t'] ?? m['elapsed_s']) ??
            (i * 5.0);
        parsed.add(
          ActivityStreamPoint(
            timeS: t,
            hr: _asDoubleOrNull(m['hr'] ?? m['heart_rate']),
            power: _asDoubleOrNull(m['power'] ?? m['power_w']),
            speedKmh: _asDoubleOrNull(m['speed_kmh'] ?? m['speed']),
            cadence: _asDoubleOrNull(m['cadence']),
            altitudeM: _asDoubleOrNull(m['altitude_m'] ?? m['altitude']),
          ),
        );
      }
      return ActivityStreams(points: parsed);
    }

    final times = _readNumList(json['time_s'] ?? json['time'] ?? json['t']);
    final hrs = _readNumList(json['hr'] ?? json['heart_rate']);
    final powers = _readNumList(json['power'] ?? json['power_w']);
    final speeds = _readNumList(json['speed_kmh'] ?? json['speed']);
    final cadences = _readNumList(json['cadence']);
    final altitudes = _readNumList(json['altitude_m'] ?? json['altitude']);

    final len = [
      times.length,
      hrs.length,
      powers.length,
      speeds.length,
      cadences.length,
      altitudes.length,
    ].fold<int>(0, (a, b) => a > b ? a : b);

    final parsed = <ActivityStreamPoint>[];
    for (var i = 0; i < len; i++) {
      parsed.add(
        ActivityStreamPoint(
          timeS: i < times.length && times[i] != null ? times[i]! : (i * 5.0),
          hr: i < hrs.length ? hrs[i] : null,
          power: i < powers.length ? powers[i] : null,
          speedKmh: i < speeds.length ? speeds[i] : null,
          cadence: i < cadences.length ? cadences[i] : null,
          altitudeM: i < altitudes.length ? altitudes[i] : null,
        ),
      );
    }
    return ActivityStreams(points: parsed);
  }

  static List<double?> _readNumList(Object? raw) {
    if (raw is! List) return const [];
    return raw.map(_asDoubleOrNull).toList();
  }
}

class ActivityComment {
  const ActivityComment({
    required this.id,
    required this.body,
    this.authorUid,
    this.authorName,
    this.authorRole,
    this.createdAt,
  });

  final String id;
  final String body;
  final String? authorUid;
  final String? authorName;
  final String? authorRole;
  final DateTime? createdAt;

  String get displayAuthor =>
      (authorName != null && authorName!.trim().isNotEmpty)
          ? authorName!.trim()
          : (authorUid ?? 'Utilisateur');

  factory ActivityComment.fromJson(Map<String, dynamic> json) {
    return ActivityComment(
      id: (json['id'] ?? '').toString(),
      body: (json['body'] ?? json['text'] ?? '').toString(),
      authorUid: json['author_uid']?.toString(),
      authorName: (json['author_name'] ?? json['author'])?.toString(),
      authorRole: json['author_role']?.toString(),
      createdAt: _parseActivityDate(json['created_at']),
    );
  }
}
