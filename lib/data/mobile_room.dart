import 'recording_state.dart';

/// Session renvoyée par `GET /mobile/rooms`.
class MobileRoom {
  const MobileRoom({
    required this.name,
    required this.participantCount,
    required this.recording,
    required this.recordingStatus,
    required this.canControlRecording,
    this.createdAt,
    this.updatedAt,
  });

  final String name;
  final int participantCount;
  final bool recording;
  final String recordingStatus;
  final bool canControlRecording;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory MobileRoom.fromJson(Map<String, dynamic> json) {
    return MobileRoom(
      name: (json['room_name'] as String?) ?? (json['name'] as String?) ?? '',
      participantCount: (json['count'] as num?)?.toInt() ?? 0,
      recording: json['recording'] == true,
      recordingStatus: (json['recording_status'] as String?) ?? 'not_started',
      canControlRecording: json['can_control_recording'] == true,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  bool get isRecording =>
      recording || RecordingState.isActiveStatus(recordingStatus);

  bool get isBusy => RecordingState.isPendingStatus(recordingStatus);

  String get recordingLabel => RecordingState.labelFor(recordingStatus);
}
