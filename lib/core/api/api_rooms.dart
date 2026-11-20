part of '../api_service.dart';

/// Domaine API : Salles LiveKit, Lobbies, Jetons d'appel, Egress (Recording)
/// et Séances d'organisation (replay, télémétrie, alertes, marqueurs).
mixin _ApiRoomsMixin on _ApiClientBase {
  // ── Routes mobiles live & Egress ───────────────────────────────────────────

  Future<List<MobileRoom>> fetchRooms({int limit = 50}) async {
    final body = await _send(
      'GET',
      '/mobile/rooms',
      query: {'limit': limit.clamp(1, 100).toString()},
    );
    final rooms = body['rooms'];
    if (rooms is! List) {
      throw const ApiException(0, 'Réponse des rooms invalide.');
    }
    final parsed = rooms
        .whereType<Map>()
        .map((item) => MobileRoom.fromJson(Map<String, dynamic>.from(item)))
        .where((room) => room.name.isNotEmpty)
        .toList();
    if (kDebugMode) {
      debugPrint(
        '[API] GET /mobile/rooms -> ${rooms.length} élément(s) reçu(s), '
        '${parsed.length} room(s) valide(s)',
      );
    }
    if (rooms.isNotEmpty && parsed.isEmpty) {
      throw const ApiException(
        0,
        'Réponse des rooms invalide : champs manquants.',
      );
    }
    return parsed;
  }

  Future<RoomLobby> fetchRoomLobby(String roomName) async {
    final body = await _send(
      'GET',
      '/rooms/${Uri.encodeComponent(roomName)}/lobby',
    );
    return RoomLobby.fromJson(body);
  }

  Future<LiveKitToken> fetchLiveKitToken(String roomName) async {
    final body = await _send('POST', '/token', body: {'room': roomName});
    final LiveKitToken parsedToken;
    try {
      parsedToken = LiveKitToken.fromJson(body);
    } on FormatException catch (error) {
      throw ApiException(0, error.message);
    }
    final overrideUrl = AppConfig.liveKitUrlOverride;
    final token = overrideUrl.isEmpty
        ? parsedToken
        : LiveKitToken(
            token: parsedToken.token,
            url: overrideUrl,
            room: parsedToken.room,
            identity: parsedToken.identity,
          );
    final allowWs =
        allowInsecureLiveKit ??
        (AppConfig.allowInsecureProtocols ||
            _effectiveBaseUrl.toLowerCase().startsWith('http://'));
    final url = Uri.tryParse(token.url);
    final validScheme =
        url != null && (url.scheme == 'wss' || (allowWs && url.scheme == 'ws'));
    if (!validScheme || url.host.isEmpty) {
      throw const ApiException(
        0,
        'URL LiveKit invalide dans la réponse token.',
      );
    }
    return token;
  }

  Future<RecordingState> requestStartRecording(
    String roomName, {
    String layout = 'grid',
  }) async {
    final body = await _send(
      'POST',
      '/mobile/rooms/${Uri.encodeComponent(roomName)}/recording/start',
      query: {'layout': layout},
    );
    return _recordingFrom(body, roomName);
  }

  Future<RecordingState> requestStopRecording(String roomName) async {
    final body = await _send(
      'POST',
      '/mobile/rooms/${Uri.encodeComponent(roomName)}/recording/stop',
    );
    return _recordingFrom(body, roomName);
  }

  Future<RecordingState> fetchRecording(String roomName) async {
    final body = await _send(
      'GET',
      '/mobile/rooms/${Uri.encodeComponent(roomName)}/recording',
    );
    return _recordingFrom(body, roomName);
  }

  static RecordingState _recordingFrom(
    Map<String, dynamic> body,
    String fallbackRoomName,
  ) {
    final normalized = Map<String, dynamic>.from(body);
    if ((normalized['room_name'] as String?)?.isEmpty ?? true) {
      normalized['room_name'] = fallbackRoomName;
    }
    return RecordingState.fromJson(normalized);
  }

  // ── Séances d'organisation, Replay, Télémétrie & Marqueurs ─────────────────

  Future<List<OrgSession>> fetchOrgSessions(String orgId) async {
    final body = await _send(
      'GET',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/sessions',
    );
    final raw = body['sessions'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((s) => OrgSession.fromJson(Map<String, dynamic>.from(s)))
        .where((s) => s.roomName.isNotEmpty)
        .toList();
  }

  Future<OrgSession> createOrgSession(
    String orgId, {
    required String title,
    String? groupId,
    List<String> participantUids = const [],
    DateTime? scheduledAt,
  }) async {
    final body = await _send(
      'POST',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/sessions',
      body: {
        'title': title.trim(),
        'group_id': (groupId == null || groupId.isEmpty) ? null : groupId,
        'participant_uids': participantUids,
        if (scheduledAt != null)
          'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      },
    );
    final rawSession = body['session'];
    if (rawSession is! Map) {
      throw const ApiException(0, 'Réponse de création de séance invalide.');
    }
    return OrgSession.fromJson(Map<String, dynamic>.from(rawSession));
  }

  Future<SessionDetail> fetchSessionDetail(
    String orgId,
    String roomName,
  ) async {
    final body = await _send(
      'GET',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/sessions/${Uri.encodeComponent(roomName)}',
    );
    return SessionDetail.fromJson(body);
  }

  Future<List<SessionTelemetrySample>> fetchSessionTelemetry(
    String orgId,
    String roomName, {
    String? participant,
  }) async {
    final decoded = await _sendList(
      'GET',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/sessions/${Uri.encodeComponent(roomName)}/telemetry',
      query: participant == null || participant.isEmpty
          ? null
          : {'participant': participant},
    );
    return decoded
        .whereType<Map>()
        .map(
          (item) =>
              SessionTelemetrySample.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<List<SessionAlert>> fetchSessionAlerts(
    String orgId,
    String roomName, {
    String? participant,
  }) async {
    final decoded = await _sendList(
      'GET',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/sessions/${Uri.encodeComponent(roomName)}/alerts',
      query: participant == null || participant.isEmpty
          ? null
          : {'participant': participant},
    );
    return decoded
        .whereType<Map>()
        .map(
          (item) => SessionAlert.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<List<SessionMarker>> fetchSessionMarkers(
    String orgId,
    String roomName,
  ) async {
    final decoded = await _sendList(
      'GET',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/sessions/${Uri.encodeComponent(roomName)}/markers',
    );
    return decoded
        .whereType<Map>()
        .map(
          (item) => SessionMarker.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<SessionMarker> createSessionMarker(
    String orgId,
    String roomName, {
    required double ptsMs,
    required String label,
    String? note,
    String category = 'technique',
  }) async {
    final body = await _send(
      'POST',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/sessions/${Uri.encodeComponent(roomName)}/markers',
      body: {
        'pts_ms': ptsMs,
        'label': label.trim(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        'category': category,
      },
    );
    return SessionMarker.fromJson(body);
  }

  Future<void> deleteSessionMarker(
    String orgId,
    String roomName,
    String markerId,
  ) async {
    await _send(
      'DELETE',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/sessions/${Uri.encodeComponent(roomName)}/markers/${Uri.encodeComponent(markerId)}',
    );
  }
}
