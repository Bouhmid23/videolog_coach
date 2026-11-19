/// Modèles des séances, enregistrements, télémétrie, alertes et marqueurs (/v1/orgs/{org_id}/sessions).
DateTime? _parseSessionDate(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value.trim());
}

double _asDouble(Object? value, [double fallback = 0.0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? fallback;
  return fallback;
}

double? _asNullableDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

int _asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
}

class OrgSession {
  const OrgSession({
    required this.roomName,
    required this.orgId,
    this.ownerUid,
    this.groupId,
    this.title = '',
    this.scheduledAt,
    this.participantUids = const [],
    this.count = 0,
    this.recording = false,
    this.recordingStatus = 'not_started',
    this.finished = false,
    this.createdAt,
    this.updatedAt,
  });

  final String roomName;
  final String orgId;
  final String? ownerUid;
  final String? groupId;
  final String title;
  final DateTime? scheduledAt;
  final List<String> participantUids;
  final int count;
  final bool recording;
  final String recordingStatus;
  final bool finished;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayTitle =>
      title.trim().isNotEmpty ? title.trim() : roomName;

  factory OrgSession.fromJson(Map<String, dynamic> json) {
    final mobileRec = json['mobile_recording'];
    final statusFromMobile = mobileRec is Map
        ? (mobileRec['status'] as String?)
        : null;
    return OrgSession(
      roomName: (json['room_name'] as String?) ?? '',
      orgId: (json['org_id'] as String?) ?? '',
      ownerUid: json['owner_uid'] as String?,
      groupId: json['group_id'] as String?,
      title: (json['title'] as String?) ?? '',
      scheduledAt: _parseSessionDate(json['scheduled_at']),
      participantUids: (json['participant_uids'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      count: _asInt(json['count']),
      recording: json['recording'] == true,
      recordingStatus:
          (json['recording_status'] as String?) ??
          statusFromMobile ??
          'not_started',
      finished: json['finished'] == true,
      createdAt: _parseSessionDate(json['created_at']),
      updatedAt: _parseSessionDate(json['updated_at']),
    );
  }
}

class SessionParticipant {
  const SessionParticipant({
    required this.uid,
    required this.identity,
    required this.displayName,
    this.email,
    this.role = 'athlete',
  });

  final String uid;
  final String identity;
  final String displayName;
  final String? email;
  final String role;

  factory SessionParticipant.fromJson(Map<String, dynamic> json) {
    return SessionParticipant(
      uid: (json['uid'] as String?) ?? '',
      identity: (json['identity'] as String?) ?? (json['uid'] as String?) ?? '',
      displayName: (json['display_name'] as String?) ??
          (json['email'] as String?) ??
          (json['uid'] as String?) ??
          '',
      email: json['email'] as String?,
      role: (json['role'] as String?) ?? 'athlete',
    );
  }
}

class SessionRecording {
  const SessionRecording({
    required this.egressId,
    required this.status,
    required this.mp4Url,
    this.durationS = 0.0,
    this.videoStartedAt,
  });

  final String egressId;
  final String status;
  final String mp4Url;
  final double durationS;
  final DateTime? videoStartedAt;

  bool get hasPlayableUrl => mp4Url.trim().isNotEmpty;

  factory SessionRecording.fromJson(Map<String, dynamic> json) {
    return SessionRecording(
      egressId: (json['egress_id'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'EGRESS_COMPLETE',
      mp4Url: (json['mp4_url'] as String?) ?? (json['url'] as String?) ?? '',
      durationS: _asDouble(json['duration_s']),
      videoStartedAt: _parseSessionDate(json['video_started_at']),
    );
  }
}

class SessionDetail {
  const SessionDetail({
    required this.roomName,
    required this.orgId,
    required this.fetchedAt,
    this.title = '',
    this.groupId,
    this.ownerUid,
    this.createdAt,
    this.updatedAt,
    this.scheduledAt,
    this.finished = false,
    this.recording = false,
    this.recordingStatus = 'not_started',
    this.participantUids = const [],
    this.participants = const [],
    this.recordings = const [],
  });

  final String roomName;
  final String orgId;
  final DateTime fetchedAt;
  final String title;
  final String? groupId;
  final String? ownerUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? scheduledAt;
  final bool finished;
  final bool recording;
  final String recordingStatus;
  final List<String> participantUids;
  final List<SessionParticipant> participants;
  final List<SessionRecording> recordings;

  String get displayTitle =>
      title.trim().isNotEmpty ? title.trim() : roomName;

  /// Les URLs présignées MinIO expirent au bout d'une heure ; on rafraîchit dès 50 min.
  bool get areSignedUrlsNearExpiry =>
      DateTime.now().difference(fetchedAt) >= const Duration(minutes: 50);

  factory SessionDetail.fromJson(
    Map<String, dynamic> json, {
    DateTime? fetchedAt,
  }) {
    return SessionDetail(
      roomName: (json['room_name'] as String?) ?? '',
      orgId: (json['org_id'] as String?) ?? '',
      fetchedAt: fetchedAt ?? DateTime.now(),
      title: (json['title'] as String?) ?? '',
      groupId: json['group_id'] as String?,
      ownerUid: json['owner_uid'] as String?,
      createdAt: _parseSessionDate(json['created_at']),
      updatedAt: _parseSessionDate(json['updated_at']),
      scheduledAt: _parseSessionDate(json['scheduled_at']),
      finished: json['finished'] == true,
      recording: json['recording'] == true,
      recordingStatus: (json['recording_status'] as String?) ?? 'not_started',
      participantUids: (json['participant_uids'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      participants: (json['participants'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((p) => SessionParticipant.fromJson(Map<String, dynamic>.from(p)))
          .toList(),
      recordings: (json['recordings'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((r) => SessionRecording.fromJson(Map<String, dynamic>.from(r)))
          .toList(),
    );
  }
}

class SessionTelemetrySample {
  const SessionTelemetrySample({
    required this.ptsMs,
    required this.serverTs,
    required this.participant,
    required this.speed,
    required this.heartRate,
    required this.cadence,
  });

  final double ptsMs;
  final double serverTs;
  final String participant;
  final double speed;
  final int heartRate;
  final double cadence;

  factory SessionTelemetrySample.fromJson(Map<String, dynamic> json) {
    return SessionTelemetrySample(
      ptsMs: _asDouble(json['pts_ms']),
      serverTs: _asDouble(json['server_ts']),
      participant: (json['participant'] as String?) ?? '',
      speed: _asDouble(json['speed']),
      heartRate: _asInt(json['heart_rate']),
      cadence: _asDouble(json['cadence']),
    );
  }
}

class SessionAlert {
  const SessionAlert({
    required this.id,
    required this.type,
    required this.participant,
    required this.ptsMs,
    required this.message,
    required this.ts,
    this.value,
    this.threshold,
  });

  final String id;
  final String type;
  final double? value;
  final double? threshold;
  final String participant;
  final double ptsMs;
  final String message;
  final double ts;

  factory SessionAlert.fromJson(Map<String, dynamic> json) {
    return SessionAlert(
      id: (json['id'] as String?) ?? '',
      type: (json['type'] as String?) ?? '',
      value: _asNullableDouble(json['value']),
      threshold: _asNullableDouble(json['threshold']),
      participant: (json['participant'] as String?) ?? '',
      ptsMs: _asDouble(json['pts_ms']),
      message: (json['message'] as String?) ?? '',
      ts: _asDouble(json['ts']),
    );
  }
}

class SessionMarker {
  const SessionMarker({
    required this.id,
    required this.roomName,
    required this.orgId,
    required this.ptsMs,
    required this.label,
    this.note,
    this.category = 'general',
    this.createdBy = '',
    this.authorName = '',
    this.createdAt,
  });

  final String id;
  final String roomName;
  final String orgId;
  final double ptsMs;
  final String label;
  final String? note;
  final String category;
  final String createdBy;
  final String authorName;
  final DateTime? createdAt;

  factory SessionMarker.fromJson(Map<String, dynamic> json) {
    return SessionMarker(
      id: (json['id'] as String?) ?? '',
      roomName: (json['room_name'] as String?) ?? '',
      orgId: (json['org_id'] as String?) ?? '',
      ptsMs: _asDouble(json['pts_ms']),
      label: (json['label'] as String?) ?? '',
      note: json['note'] as String?,
      category: (json['category'] as String?) ?? 'general',
      createdBy: (json['created_by'] as String?) ?? '',
      authorName: (json['author_name'] as String?) ?? '',
      createdAt: _parseSessionDate(json['created_at']),
    );
  }
}
