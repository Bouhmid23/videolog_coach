/// Modèles de la route `GET /rooms/{room_name}/lobby`.
class LobbyParticipant {
  const LobbyParticipant({
    required this.uid,
    required this.name,
    this.isOwner = false,
    this.connected = false,
  });

  final String uid;
  final String name;
  final bool isOwner;
  final bool connected;

  String get displayName {
    final trimmed = name.trim();
    return trimmed.isNotEmpty ? trimmed : uid;
  }

  String get initials {
    final source = displayName.trim();
    if (source.isEmpty) return '?';
    final parts = source
        .split(RegExp(r'[\s@._-]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return source.substring(0, 1).toUpperCase();
  }

  factory LobbyParticipant.fromJson(Map<String, dynamic> json) {
    final uid = (json['uid'] as String?)?.trim() ?? '';
    final rawName = (json['name'] as String?)?.trim() ?? '';
    return LobbyParticipant(
      uid: uid,
      name: rawName.isNotEmpty ? rawName : uid,
      isOwner: json['is_owner'] == true,
      connected: json['connected'] == true,
    );
  }
}

class RoomLobby {
  const RoomLobby({
    required this.roomName,
    required this.title,
    this.orgName,
    this.durationS = 3600,
    this.scheduledAt,
    this.scheduledEndAt,
    this.activeCount = 0,
    this.finished = false,
    this.invitedParticipants = const [],
    this.accessible = true,
    this.reason,
  });

  final String roomName;
  final String title;
  final String? orgName;
  final int durationS;
  final DateTime? scheduledAt;
  final DateTime? scheduledEndAt;
  final int activeCount;
  final bool finished;
  final List<LobbyParticipant> invitedParticipants;
  final bool accessible;
  final String? reason;

  String get displayTitle => title.trim().isNotEmpty ? title.trim() : roomName;

  int get connectedCount {
    final invitedConnected = invitedParticipants
        .where((p) => p.connected)
        .length;
    return activeCount > invitedConnected ? activeCount : invitedConnected;
  }

  /// Table `uid -> nom` utilisable comme cache d'affichage dans la room.
  Map<String, String> get namesByUid {
    final map = <String, String>{};
    for (final p in invitedParticipants) {
      final uid = p.uid.trim();
      final name = p.name.trim();
      if (uid.isNotEmpty && name.isNotEmpty && name != uid) {
        map[uid] = name;
      }
    }
    return map;
  }

  factory RoomLobby.fromJson(Map<String, dynamic> json) {
    final roomName = (json['room_name'] as String?)?.trim() ?? '';
    final rawTitle = (json['title'] as String?)?.trim() ?? '';
    final rawOrgName = (json['org_name'] as String?)?.trim();
    final rawReason = (json['reason'] as String?)?.trim();
    final rawInvited = json['invited_participants'];
    final invited = rawInvited is List
        ? rawInvited
              .whereType<Map>()
              .map(
                (item) => LobbyParticipant.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((p) => p.uid.isNotEmpty || p.name.isNotEmpty)
              .toList()
        : const <LobbyParticipant>[];

    // Affiche d'abord les participants déjà connectés, puis l'organisateur, puis par nom.
    final sortedInvited = List<LobbyParticipant>.from(invited)
      ..sort((a, b) {
        if (a.connected != b.connected) return a.connected ? -1 : 1;
        if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });

    return RoomLobby(
      roomName: roomName,
      title: rawTitle.isNotEmpty ? rawTitle : roomName,
      orgName: (rawOrgName != null && rawOrgName.isNotEmpty)
          ? rawOrgName
          : null,
      durationS: (json['duration_s'] as num?)?.toInt() ?? 3600,
      scheduledAt: _parseDate(json['scheduled_at']),
      scheduledEndAt: _parseDate(json['scheduled_end_at']),
      activeCount: (json['active_count'] as num?)?.toInt() ?? 0,
      finished: json['finished'] == true,
      invitedParticipants: sortedInvited,
      accessible: json['accessible'] != false,
      reason: (rawReason != null && rawReason.isNotEmpty) ? rawReason : null,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim());
  }
}
