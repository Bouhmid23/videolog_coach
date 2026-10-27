/// État d'un enregistrement Egress pour une room.
///
/// Le serveur peut renvoyer les statuts LiveKit bruts (`EGRESS_STARTING`,
/// `EGRESS_ACTIVE`, `EGRESS_ENDING`, `EGRESS_COMPLETE`, `EGRESS_FAILED`,
/// `EGRESS_ABORTED`) ou les statuts normalisés stockés dans
/// `mobile_recording.status` (`not_started`, `starting`, `recording`,
/// `stopping`, `completed`, `failed`, `stopped`).
class RecordingState {
  const RecordingState({
    required this.roomName,
    required this.rawStatus,
    this.egressId,
    this.startedAt,
    this.endedAt,
    this.maxDurationSeconds,
    this.error,
    this.files = const [],
  });

  final String roomName;
  final String rawStatus;
  final String? egressId;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? maxDurationSeconds;
  final String? error;
  final List<RecordingFile> files;

  factory RecordingState.fromJson(Map<String, dynamic> json) {
    return RecordingState(
      roomName: (json['room_name'] as String?) ?? '',
      rawStatus: (json['status'] as String?) ?? 'not_started',
      egressId: json['egress_id'] as String?,
      startedAt: _parseDate(json['started_at']),
      endedAt: _parseDate(json['ended_at']),
      maxDurationSeconds: _parseIntValue(json['max_duration_seconds']),
      error: json['error'] as String?,
      files: (json['files'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => RecordingFile.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  /// Statut normalisé, quel que soit le format renvoyé par le serveur.
  String get status {
    switch (rawStatus) {
      case 'EGRESS_STARTING':
        return 'starting';
      case 'EGRESS_ACTIVE':
        return 'recording';
      case 'EGRESS_ENDING':
        return 'stopping';
      case 'EGRESS_COMPLETE':
        return 'completed';
      case 'EGRESS_FAILED':
        return 'failed';
      case 'EGRESS_ABORTED':
        return 'stopped';
      default:
        return rawStatus;
    }
  }

  static const _notStarted = 'not_started';
  static const _starting = 'starting';
  static const _recording = 'recording';
  static const _stopping = 'stopping';
  static const _completed = 'completed';
  static const _failed = 'failed';
  static const _stopped = 'stopped';

  bool get isNotStarted => status == _notStarted;

  bool get isStarting => status == _starting;

  bool get isRecording => status == _recording;

  bool get isStopping => status == _stopping;

  bool get isActive => isRecording;

  bool get isPending => isStarting || isStopping;

  bool get isTerminal =>
      status == _completed || status == _failed || status == _stopped;

  bool get canStart => isNotStarted || isTerminal;

  bool get canStop => isRecording;

  String get label {
    switch (status) {
      case _notStarted:
        return 'Non démarré';
      case _starting:
        return 'Démarrage…';
      case _recording:
        return 'Enregistrement';
      case _stopping:
        return 'Arrêt…';
      case _completed:
        return 'Terminé';
      case _failed:
        return 'Échec';
      case _stopped:
        return 'Arrêté';
      default:
        return rawStatus;
    }
  }

  /// Libellé pour un statut brut, utilisable sans instance (liste des rooms).
  static String labelFor(String rawStatus) {
    return RecordingState(roomName: '', rawStatus: rawStatus).label;
  }

  static bool isActiveStatus(String rawStatus) =>
      RecordingState(roomName: '', rawStatus: rawStatus).isActive;

  static bool isPendingStatus(String rawStatus) =>
      RecordingState(roomName: '', rawStatus: rawStatus).isPending;
}

int? _parseIntValue(Object? value) {
  final number = _parseNumber(value);
  return number?.toInt();
}

double? _parseDoubleValue(Object? value) {
  final number = _parseNumber(value);
  return number?.toDouble();
}

num? _parseNumber(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value.trim());
  return null;
}

class RecordingFile {
  const RecordingFile({
    required this.filename,
    this.url,
    this.sizeBytes = 0,
    this.durationSeconds = 0,
  });

  final String filename;
  final String? url;
  final int sizeBytes;
  final double durationSeconds;

  factory RecordingFile.fromJson(Map<String, dynamic> json) {
    return RecordingFile(
      filename: (json['filename'] as String?) ?? '',
      url: (json['url'] as String?) ?? (json['minio_url'] as String?),
      sizeBytes: _parseIntValue(json['size']) ?? 0,
      durationSeconds: _parseDoubleValue(json['duration']) ?? 0,
    );
  }
}
