import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../data/account_models.dart';
import '../data/activity_models.dart';
import '../data/directory_models.dart';
import '../data/livekit_token.dart';
import '../data/mobile_room.dart';
import '../data/pmc_models.dart';
import '../data/recording_state.dart';
import '../data/room_lobby.dart';
import '../data/session_models.dart';
import '../data/training_models.dart';
import 'auth_service.dart';

/// Client des routes mobiles et back-office v1 Videolog.
///
/// Toutes les requêtes authentifiées portent l'ID token Firebase courant en
/// Bearer. Aucun secret LiveKit, MinIO ou Firebase Admin n'est présent côté
/// application.
class ApiService {
  ApiService({
    http.Client? httpClient,
    AuthService? authService,
    String? baseUrl,
    this.allowInsecureLiveKit,
  }) : _httpClient = httpClient ?? http.Client(),
       _authService = authService, // ignore: prefer_initializing_formals
       _baseUrlOverride = baseUrl;

  /// Instance partagée par défaut (réutilise les connexions HTTP keep-alive).
  static ApiService instance = ApiService();

  static String get baseUrl => AppConfig.apiBaseUrl;
  static const Duration _timeout = Duration(seconds: 15);

  final http.Client _httpClient;
  final AuthService? _authService;
  final String? _baseUrlOverride;
  final bool? allowInsecureLiveKit;

  AuthService get _auth => _authService ?? AuthService.instance;

  String get _effectiveBaseUrl {
    final override = _baseUrlOverride?.trim();
    if (override != null && override.isNotEmpty) {
      var normalized = override;
      while (normalized.endsWith('/')) {
        normalized = normalized.substring(0, normalized.length - 1);
      }
      return normalized;
    }
    return AppConfig.apiBaseUrl;
  }

  static Future<List<MobileRoom>> getRooms({int limit = 50}) =>
      instance.fetchRooms(limit: limit);

  static Future<RoomLobby> getRoomLobby(String roomName) =>
      instance.fetchRoomLobby(roomName);

  static Future<LiveKitToken> getLiveKitToken(String roomName) =>
      instance.fetchLiveKitToken(roomName);

  static Future<RecordingState> startRecording(
    String roomName, {
    String layout = 'grid',
  }) => instance.requestStartRecording(roomName, layout: layout);

  static Future<RecordingState> stopRecording(String roomName) =>
      instance.requestStopRecording(roomName);

  static Future<RecordingState> getRecording(String roomName) =>
      instance.fetchRecording(roomName);

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

  // ── Compte, Onboarding & Profil sportif (/v1/me) ───────────────────────────

  Future<AccountMe> fetchMe() async {
    final body = await _send('GET', '/v1/me');
    return AccountMe.fromJson(body);
  }

  Future<AppUser?> updateMe({
    String? firstName,
    String? lastName,
    String? phone,
    String? locale,
  }) async {
    final payload = <String, dynamic>{
      if (firstName != null) 'first_name': firstName.trim(),
      if (lastName != null) 'last_name': lastName.trim(),
      if (phone != null) 'phone': phone.trim(),
      'locale': ?locale,
    };
    final body = await _send('PATCH', '/v1/me', body: payload);
    final rawUser = body['user'];
    return rawUser is Map
        ? AppUser.fromJson(Map<String, dynamic>.from(rawUser))
        : null;
  }

  Future<AccountMe> submitOnboarding({
    required String accountType, // 'club' | 'solo_coach'
    required String organizationName,
    required List<String> sports,
    String? city,
    required String firstName,
    required String lastName,
    String? phone,
    bool ageConfirmed = true,
  }) async {
    await _send(
      'POST',
      '/v1/me/onboarding',
      body: {
        'account_type': accountType,
        'organization_name': organizationName.trim(),
        'sports': sports,
        if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        'age_confirmed': ageConfirmed,
      },
    );
    return fetchMe();
  }

  Future<AppUser?> updateAthleteProfile({
    required String sport,
    required String level,
    required String birthDateIso,
    int? heightCm,
    double? weightKg,
    int? hrMax,
    int? hrRest,
    required bool healthConsent,
  }) async {
    final body = await _send(
      'PUT',
      '/v1/me/athlete-profile',
      body: {
        'sport': sport,
        'level': level,
        'birth_date': birthDateIso,
        'height_cm': heightCm,
        'weight_kg': healthConsent ? weightKg : null,
        'hr_max': healthConsent ? hrMax : null,
        'hr_rest': healthConsent ? hrRest : null,
        'health_consent': healthConsent,
      },
    );
    final rawUser = body['user'];
    return rawUser is Map
        ? AppUser.fromJson(Map<String, dynamic>.from(rawUser))
        : null;
  }

  Future<AppUser?> revokeHealthConsent() async {
    final body = await _send('DELETE', '/v1/me/health-consent');
    final rawUser = body['user'];
    return rawUser is Map
        ? AppUser.fromJson(Map<String, dynamic>.from(rawUser))
        : null;
  }

  // ── Invitations (/v1/invitations) ──────────────────────────────────────────

  Future<InvitationPreview> previewInvitation(String token) async {
    final body = await _send(
      'GET',
      '/v1/invitations/${Uri.encodeComponent(token.trim())}',
      requiresAuth: false,
    );
    return InvitationPreview.fromJson(body);
  }

  Future<Map<String, dynamic>> acceptInvitation(
    String token, {
    String? firstName,
    String? lastName,
    bool ageConfirmed = true,
  }) async {
    return _send(
      'POST',
      '/v1/invitations/${Uri.encodeComponent(token.trim())}/accept',
      body: {
        if (firstName != null && firstName.trim().isNotEmpty)
          'first_name': firstName.trim(),
        if (lastName != null && lastName.trim().isNotEmpty)
          'last_name': lastName.trim(),
        'age_confirmed': ageConfirmed,
      },
    );
  }

  /// Liste les invitations en attente destinées à l'utilisateur connecté (`/v1/me/invitations`).
  Future<List<InAppInvitation>> fetchMyInvitations() async {
    final body = await _send('GET', '/v1/me/invitations');
    final raw = body['invitations'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => InAppInvitation.fromJson(Map<String, dynamic>.from(item)))
        .where((inv) => inv.id.isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>> acceptMyInvitation(String invitationId) async {
    return _send(
      'POST',
      '/v1/me/invitations/${Uri.encodeComponent(invitationId.trim())}/accept',
    );
  }

  Future<Map<String, dynamic>> declineMyInvitation(String invitationId) async {
    return _send(
      'POST',
      '/v1/me/invitations/${Uri.encodeComponent(invitationId.trim())}/decline',
    );
  }

  // ── Notifications (/v1/me/notifications) ───────────────────────────────────

  Future<NotificationsResponse> fetchNotifications() async {
    final body = await _send('GET', '/v1/me/notifications');
    return NotificationsResponse.fromJson(body);
  }

  Future<void> markAllNotificationsRead() async {
    await _send('POST', '/v1/me/notifications/read-all');
  }

  Future<void> markNotificationRead(String notifId) async {
    await _send(
      'POST',
      '/v1/me/notifications/${Uri.encodeComponent(notifId.trim())}/read',
    );
  }

  // ── Organisations, Groupes, Membres & Séances (/v1/orgs/{org_id}) ──────────

  /// Permet au membre connecté de quitter une organisation (`DELETE /v1/orgs/{org_id}/members/me`).
  Future<Map<String, dynamic>> leaveOrganization(String orgId) async {
    return _send(
      'DELETE',
      '/v1/orgs/${Uri.encodeComponent(orgId.trim())}/members/me',
    );
  }

  Future<List<OrgGroup>> fetchOrgGroups(String orgId) async {
    final body = await _send(
      'GET',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/groups',
    );
    final raw = body['groups'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((g) => OrgGroup.fromJson(Map<String, dynamic>.from(g)))
        .where((g) => g.id.isNotEmpty)
        .toList();
  }

  Future<List<OrgMemberSummary>> fetchOrgMembers(
    String orgId, {
    String? role,
    String? groupId,
  }) async {
    final query = <String, String>{
      if (role != null && role.isNotEmpty) 'role': role,
      if (groupId != null && groupId.isNotEmpty) 'group_id': groupId,
    };
    final body = await _send(
      'GET',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/members',
      query: query.isEmpty ? null : query,
    );
    final raw = body['members'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => OrgMemberSummary.fromJson(Map<String, dynamic>.from(m)))
        .where((m) => m.uid.isNotEmpty)
        .toList();
  }

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
        if (scheduledAt != null) 'scheduled_at': scheduledAt.toUtc().toIso8601String(),
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
        .map((item) => SessionTelemetrySample.fromJson(Map<String, dynamic>.from(item)))
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
        .map((item) => SessionAlert.fromJson(Map<String, dynamic>.from(item)))
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
        .map((item) => SessionMarker.fromJson(Map<String, dynamic>.from(item)))
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

  // ── Calendrier, Séances structurées & Forme du jour (/v1/orgs/{org_id}) ───

  Future<CalendarResponse> fetchCalendar(
    String orgId, {
    required String from,
    required String to,
    String? uid,
  }) async {
    final body = await _send(
      'GET',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/calendar',
      query: {
        'from': from,
        'to': to,
        if (uid != null && uid.trim().isNotEmpty) 'uid': uid.trim(),
      },
    );
    return CalendarResponse.fromJson(body);
  }

  Future<Uint8List> exportPlannedWorkout(
    String orgId,
    String plannedId, {
    String format = 'fit',
  }) {
    return getBytes(
      '/v1/orgs/${Uri.encodeComponent(orgId)}/workouts/planned/${Uri.encodeComponent(plannedId)}/export',
      query: {'format': format},
    );
  }

  Future<Map<String, dynamic>> submitWellness(
    String orgId, {
    required String uid,
    required WellnessEntry entry,
    required bool includeHealthData,
  }) {
    return _send(
      'POST',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/wellness',
      query: {'uid': uid},
      body: entry.toJson(includeHealthData: includeHealthData),
    );
  }

  Future<List<ActivityComment>> fetchPlannedWorkoutComments(
    String orgId,
    String plannedId,
  ) async {
    final decoded = await _sendRaw(
      'GET',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/workouts/planned/${Uri.encodeComponent(plannedId)}/comments',
    );
    final rawList = decoded is List
        ? decoded
        : (decoded is Map ? (decoded['items'] ?? decoded['comments']) : null);
    if (rawList is! List) return const [];
    return rawList
        .whereType<Map>()
        .map((c) => ActivityComment.fromJson(Map<String, dynamic>.from(c)))
        .toList();
  }

  Future<ActivityComment> postPlannedWorkoutComment(
    String orgId,
    String plannedId,
    String bodyText,
  ) async {
    final body = await _send(
      'POST',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/workouts/planned/${Uri.encodeComponent(plannedId)}/comments',
      body: {'body': bodyText.trim()},
    );
    final raw = body['comment'];
    final map = raw is Map ? Map<String, dynamic>.from(raw) : body;
    return ActivityComment.fromJson(map);
  }

  // ── Activités, Import FIT/GPX/TCX, Courbes & Débriefing ────────────────────

  Future<List<ActivitySummary>> fetchActivities(
    String orgId, {
    String? uid,
    int limit = 30,
  }) async {
    final decoded = await _sendRaw(
      'GET',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/activities',
      query: {
        'limit': limit.clamp(1, 100).toString(),
        if (uid != null && uid.trim().isNotEmpty) 'uid': uid.trim(),
      },
    );
    final rawList = decoded is List
        ? decoded
        : (decoded is Map ? (decoded['activities'] ?? decoded['items']) : null);
    if (rawList is! List) return const [];
    return rawList
        .whereType<Map>()
        .map((a) => ActivitySummary.fromJson(Map<String, dynamic>.from(a)))
        .where((a) => a.id.isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>> uploadActivityFile(
    String orgId, {
    String? filePath,
    Uint8List? fileBytes,
    String? filename,
    String? title,
  }) async {
    try {
      return await postMultipart(
        '/v1/orgs/${Uri.encodeComponent(orgId)}/activities/upload',
        filePath: filePath,
        fileBytes: fileBytes,
        filename: filename,
        fields: {
          if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        },
      );
    } on ApiException catch (e) {
      if (e.isConflict && (e.detail == null || e.detail!.isEmpty)) {
        throw const ApiException(
          409,
          'Cette activité a déjà été importée.',
        );
      }
      rethrow;
    }
  }

  Future<ActivityDetail> fetchActivityDetail(
    String orgId,
    String activityId,
  ) async {
    final body = await _send(
      'GET',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/activities/${Uri.encodeComponent(activityId)}',
    );
    return ActivityDetail.fromJson(body);
  }

  Future<ActivityStreams> fetchActivityStreams(
    String orgId,
    String activityId, {
    int downsample = 5,
  }) async {
    final body = await _send(
      'GET',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/activities/${Uri.encodeComponent(activityId)}/streams',
      query: {'downsample': downsample.clamp(1, 60).toString()},
    );
    return ActivityStreams.fromJson(body);
  }

  Future<ActivitySummary> updateActivityFeedback(
    String orgId,
    String activityId, {
    int? rpe,
    int? feeling,
  }) async {
    final body = await _send(
      'PATCH',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/activities/${Uri.encodeComponent(activityId)}',
      body: {
        if (rpe != null) 'rpe': rpe.clamp(1, 10),
        if (feeling != null) 'feeling': feeling.clamp(1, 5),
      },
    );
    return ActivitySummary.fromJson(body);
  }

  Future<List<ActivityComment>> fetchActivityComments(
    String orgId,
    String activityId,
  ) async {
    final decoded = await _sendRaw(
      'GET',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/activities/${Uri.encodeComponent(activityId)}/comments',
    );
    final rawList = decoded is List
        ? decoded
        : (decoded is Map ? (decoded['comments'] ?? decoded['items']) : null);
    if (rawList is! List) return const [];
    return rawList
        .whereType<Map>()
        .map((c) => ActivityComment.fromJson(Map<String, dynamic>.from(c)))
        .toList();
  }

  Future<ActivitySummary> updateActivitySharing(
    String orgId,
    String activityId,
    List<String> sharedOrgIds,
  ) async {
    final body = await _send(
      'PATCH',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/activities/${Uri.encodeComponent(activityId)}/sharing',
      body: {'shared_org_ids': sharedOrgIds},
    );
    final raw = body['activity'];
    final map = raw is Map ? Map<String, dynamic>.from(raw) : body;
    return ActivitySummary.fromJson(map);
  }

  Future<ActivityComment> postActivityComment(
    String orgId,
    String activityId,
    String bodyText,
  ) async {
    final body = await _send(
      'POST',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/activities/${Uri.encodeComponent(activityId)}/comments',
      body: {'body': bodyText.trim()},
    );
    final raw = body['comment'];
    final map = raw is Map ? Map<String, dynamic>.from(raw) : body;
    return ActivityComment.fromJson(map);
  }

  // ── Analytics PMC & Seuils (P3) ────────────────────────────────────────────

  Future<PmcResponse> fetchPmc(
    String orgId, {
    required String uid,
    required String from,
    bool includeProjected = true,
  }) async {
    final body = await _send(
      'GET',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/analytics/pmc',
      query: {
        'uid': uid,
        'from': from,
        'include_projected': includeProjected ? 'true' : 'false',
      },
    );
    return PmcResponse.fromJson(body);
  }

  Future<List<AthleteThreshold>> fetchMyThresholds() async {
    final decoded = await _sendRaw('GET', '/v1/me/thresholds');
    return AthleteThreshold.parseList(decoded);
  }

  Future<AthleteThreshold> updateAthleteThresholds(
    String orgId,
    String uid, {
    required String sport,
    required String effectiveFrom,
    int? ftpW,
    int? lthrBpm,
    bool recalculateActivities = true,
  }) async {
    final body = await _send(
      'PUT',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/athletes/${Uri.encodeComponent(uid)}/thresholds',
      body: {
        'sport': sport,
        'effective_from': effectiveFrom,
        'ftp_w': ?ftpW,
        'lthr_bpm': ?lthrBpm,
        'recalculate_activities': recalculateActivities,
      },
    );
    return AthleteThreshold.fromJson(body, fallbackSport: sport);
  }

  // ── Référentiel des sports, Annuaire & Demandes d'adhésion ────────────────

  /// Charge le référentiel des sports (`GET /v1/sports`, route publique).
  Future<List<SportMeta>> fetchSports({
    bool? isIndoor,
    String? category,
  }) async {
    final query = <String, String>{
      if (isIndoor != null) 'is_indoor': isIndoor.toString(),
      if (category != null && category.trim().isNotEmpty)
        'category': category.trim(),
    };
    final body = await _send(
      'GET',
      '/v1/sports',
      query: query.isEmpty ? null : query,
      requiresAuth: false,
    );
    final raw = body['sports'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => SportMeta.fromJson(Map<String, dynamic>.from(e)))
        .where((s) => s.code.isNotEmpty)
        .toList();
  }

  /// Recherche dans l'annuaire public des clubs et coachs privés.
  Future<DirectoryPageResult> searchDirectoryOrganizations({
    String? type, // 'club' | 'solo_coach'
    String? sport,
    bool indoorOnly = false,
    String? city,
    String? q,
    bool acceptingOnly = false,
    int limit = 20,
    int offset = 0,
  }) async {
    final safeLimit = limit.clamp(1, 100);
    final safeOffset = offset < 0 ? 0 : offset;
    final query = <String, String>{
      'limit': '$safeLimit',
      'offset': '$safeOffset',
      if (type != null && type.trim().isNotEmpty) 'type': type.trim(),
      if (sport != null && sport.trim().isNotEmpty) 'sport': sport.trim(),
      if (indoorOnly) 'indoor_only': 'true',
      if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      if (acceptingOnly) 'accepting_only': 'true',
    };
    final body = await _send(
      'GET',
      '/v1/directory/organizations',
      query: query,
    );
    final raw = body['organizations'];
    final items = raw is List
        ? raw
              .whereType<Map>()
              .map(
                (e) =>
                    DirectoryOrganization.fromJson(Map<String, dynamic>.from(e)),
              )
              .where((o) => o.id.isNotEmpty)
              .toList()
        : const <DirectoryOrganization>[];
    return DirectoryPageResult(
      organizations: items,
      total: (body['total'] as num?)?.toInt() ?? items.length,
      limit: (body['limit'] as num?)?.toInt() ?? safeLimit,
      offset: (body['offset'] as num?)?.toInt() ?? safeOffset,
    );
  }

  /// Fiche détaillée d'un club ou coach (`GET /v1/directory/organizations/{org_id}`).
  Future<DirectoryOrganizationDetail> fetchDirectoryOrganizationDetail(
    String orgId,
  ) async {
    final body = await _send(
      'GET',
      '/v1/directory/organizations/${Uri.encodeComponent(orgId)}',
    );
    return DirectoryOrganizationDetail.fromJson(body);
  }

  /// Soumet une demande d'adhésion (`POST /v1/orgs/{org_id}/join-requests`).
  Future<MyJoinRequest> submitJoinRequest({
    required String orgId,
    List<String> requestedSports = const [],
    String? requestedGroupId,
    String? targetCoachUid,
    String? message,
    String? firstName,
    String? lastName,
    bool ageConfirmed = true,
  }) async {
    final payload = <String, dynamic>{
      'requested_sports': requestedSports,
      'age_confirmed': ageConfirmed,
      if (requestedGroupId != null && requestedGroupId.trim().isNotEmpty)
        'requested_group_id': requestedGroupId.trim(),
      if (targetCoachUid != null && targetCoachUid.trim().isNotEmpty)
        'target_coach_uid': targetCoachUid.trim(),
      if (message != null && message.trim().isNotEmpty)
        'message': message.trim(),
      if (firstName != null && firstName.trim().isNotEmpty)
        'first_name': firstName.trim(),
      if (lastName != null && lastName.trim().isNotEmpty)
        'last_name': lastName.trim(),
    };
    final body = await _send(
      'POST',
      '/v1/orgs/${Uri.encodeComponent(orgId)}/join-requests',
      body: payload,
    );
    final rawReq = body['join_request'];
    if (rawReq is! Map) {
      throw const ApiException(0, 'Réponse de demande d\'adhésion invalide.');
    }
    return MyJoinRequest.fromJson(
      Map<String, dynamic>.from(rawReq),
      fallbackOrgId: orgId,
    );
  }

  /// Liste les demandes d'adhésion de l'utilisateur courant (`GET /v1/me/join-requests`).
  Future<List<MyJoinRequest>> fetchMyJoinRequests({String? status}) async {
    final query = <String, String>{
      if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
    };
    final body = await _send(
      'GET',
      '/v1/me/join-requests',
      query: query.isEmpty ? null : query,
    );
    final raw = body['join_requests'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => MyJoinRequest.fromJson(Map<String, dynamic>.from(e)))
        .where((r) => r.id.isNotEmpty)
        .toList();
  }

  /// Annule une demande d'adhésion en attente (`DELETE /v1/me/join-requests/{request_id}`).
  Future<void> cancelJoinRequest(String requestId) async {
    await _sendRaw(
      'DELETE',
      '/v1/me/join-requests/${Uri.encodeComponent(requestId)}',
    );
  }

  // ── Transport HTTP ─────────────────────────────────────────────────────────

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

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    bool requiresAuth = true,
    bool retriedAfterUnauthorized = false,
  }) async {
    final decoded = await _sendRaw(
      method,
      path,
      query: query,
      body: body,
      requiresAuth: requiresAuth,
      retriedAfterUnauthorized: retriedAfterUnauthorized,
    );
    if (decoded is! Map) {
      throw const ApiException(0, 'Réponse serveur invalide.');
    }
    final map = Map<String, dynamic>.from(decoded);
    final apiError = map['error'];
    if (apiError != null && apiError.toString().isNotEmpty) {
      throw ApiException(200, apiError.toString());
    }
    return map;
  }

  Future<List<dynamic>> _sendList(
    String method,
    String path, {
    Map<String, String>? query,
    bool requiresAuth = true,
  }) async {
    final decoded = await _sendRaw(
      method,
      path,
      query: query,
      requiresAuth: requiresAuth,
    );
    if (decoded is! List) {
      throw const ApiException(0, 'Réponse serveur invalide (liste attendue).');
    }
    return decoded;
  }

  Future<Object?> _sendRaw(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    bool requiresAuth = true,
    bool retriedAfterUnauthorized = false,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };

    if (requiresAuth) {
      final idToken = await _auth.requireIdToken(
        forceRefresh: retriedAfterUnauthorized,
      );
      headers['Authorization'] = 'Bearer $idToken';
    }

    final base = Uri.parse('$_effectiveBaseUrl$path');
    final uri = query == null ? base : base.replace(queryParameters: query);
    final isRecordingRequest = path.contains('/recording');

    if (kDebugMode) {
      debugPrint('[API] -> $method $uri');
    }

    final encodedBody = body == null ? null : jsonEncode(body);
    late final http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await _httpClient.get(uri, headers: headers).timeout(_timeout);
        case 'POST':
          response = await _httpClient
              .post(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);
        case 'PUT':
          response = await _httpClient
              .put(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);
        case 'PATCH':
          response = await _httpClient
              .patch(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);
        case 'DELETE':
          response = await _httpClient
              .delete(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);
        default:
          throw ApiException(0, 'Méthode HTTP non supportée: $method');
      }
    } on TimeoutException {
      if (kDebugMode) debugPrint('[API] TIMEOUT $method $path');
      throw const ApiException(0, 'Délai dépassé. Vérifiez votre connexion.');
    } on SocketException {
      if (kDebugMode) debugPrint('[API] SOCKET $method $path');
      throw const ApiException(
        0,
        'Réseau indisponible. Vérifiez votre connexion.',
      );
    } on http.ClientException {
      if (kDebugMode) debugPrint('[API] CLIENT $method $path');
      throw const ApiException(0, 'Connexion au serveur impossible.');
    }

    if (kDebugMode) {
      debugPrint('[API] $method $path -> HTTP ${response.statusCode}');
      if (path == '/mobile/rooms' || isRecordingRequest) {
        final raw = response.body;
        final preview = raw.length > 2000
            ? '${raw.substring(0, 2000)}… (${raw.length} caractères)'
            : raw;
        debugPrint('[API] $method $path body: $preview');
      }
    }

    if (requiresAuth &&
        response.statusCode == 401 &&
        !retriedAfterUnauthorized) {
      if (kDebugMode) {
        debugPrint(
          '[API] 401 sur $method $path -> rafraîchissement du jeton et nouvel essai',
        );
      }
      return _sendRaw(
        method,
        path,
        query: query,
        body: body,
        requiresAuth: requiresAuth,
        retriedAfterUnauthorized: true,
      );
    }

    Object? decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = null;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = _extractDetail(decoded);
      throw ApiException(
        response.statusCode,
        _messageFor(response.statusCode, detail),
        detail: detail,
      );
    }

    return decoded;
  }

  /// Télécharge une ressource binaire (ex: export `.fit`, `.zwo`, `.erg`).
  Future<Uint8List> getBytes(
    String path, {
    Map<String, String>? query,
    bool requiresAuth = true,
    bool retriedAfterUnauthorized = false,
  }) async {
    final headers = <String, String>{};
    if (requiresAuth) {
      final idToken = await _auth.requireIdToken(
        forceRefresh: retriedAfterUnauthorized,
      );
      headers['Authorization'] = 'Bearer $idToken';
    }

    final base = Uri.parse('$_effectiveBaseUrl$path');
    final uri = query == null ? base : base.replace(queryParameters: query);

    if (kDebugMode) {
      debugPrint('[API] -> GET (bytes) $uri');
    }

    late final http.Response response;
    try {
      response = await _httpClient.get(uri, headers: headers).timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(0, 'Délai dépassé. Vérifiez votre connexion.');
    } on SocketException {
      throw const ApiException(
        0,
        'Réseau indisponible. Vérifiez votre connexion.',
      );
    } on http.ClientException {
      throw const ApiException(0, 'Connexion au serveur impossible.');
    }

    if (requiresAuth &&
        response.statusCode == 401 &&
        !retriedAfterUnauthorized) {
      return getBytes(
        path,
        query: query,
        requiresAuth: requiresAuth,
        retriedAfterUnauthorized: true,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      Object? decoded;
      if (response.body.isNotEmpty) {
        try {
          decoded = jsonDecode(response.body);
        } on FormatException {
          decoded = null;
        }
      }
      final detail = _extractDetail(decoded);
      throw ApiException(
        response.statusCode,
        _messageFor(response.statusCode, detail),
        detail: detail,
      );
    }

    return response.bodyBytes;
  }

  /// Envoie un fichier en `multipart/form-data` (ex: import `.fit`, `.gpx`, `.tcx`).
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    String? filePath,
    Uint8List? fileBytes,
    String? filename,
    String fileField = 'file',
    Map<String, String>? fields,
    bool requiresAuth = true,
    bool retriedAfterUnauthorized = false,
  }) async {
    if (filePath == null && fileBytes == null) {
      throw ArgumentError('filePath ou fileBytes doit être fourni.');
    }

    final base = Uri.parse('$_effectiveBaseUrl$path');
    final request = http.MultipartRequest('POST', base);

    if (requiresAuth) {
      final idToken = await _auth.requireIdToken(
        forceRefresh: retriedAfterUnauthorized,
      );
      request.headers['Authorization'] = 'Bearer $idToken';
    }

    if (fields != null && fields.isNotEmpty) {
      request.fields.addAll(fields);
    }

    if (fileBytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          fileField,
          fileBytes,
          filename: filename ?? 'upload.bin',
        ),
      );
    } else {
      request.files.add(
        await http.MultipartFile.fromPath(
          fileField,
          filePath!,
          filename: filename,
        ),
      );
    }

    if (kDebugMode) {
      debugPrint('[API] -> POST (multipart) $base');
    }

    late final http.Response response;
    try {
      final streamed = await _httpClient.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException(0, 'Délai dépassé. Vérifiez votre connexion.');
    } on SocketException {
      throw const ApiException(
        0,
        'Réseau indisponible. Vérifiez votre connexion.',
      );
    } on http.ClientException {
      throw const ApiException(0, 'Connexion au serveur impossible.');
    }

    if (requiresAuth &&
        response.statusCode == 401 &&
        !retriedAfterUnauthorized) {
      return postMultipart(
        path,
        filePath: filePath,
        fileBytes: fileBytes,
        filename: filename,
        fileField: fileField,
        fields: fields,
        requiresAuth: requiresAuth,
        retriedAfterUnauthorized: true,
      );
    }

    Object? decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = null;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = _extractDetail(decoded);
      throw ApiException(
        response.statusCode,
        _messageFor(response.statusCode, detail),
        detail: detail,
      );
    }

    if (decoded is! Map) {
      throw const ApiException(0, 'Réponse serveur invalide.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static String? _extractDetail(Object? decoded) {
    if (decoded is! Map) return null;
    final detail = decoded['detail'] ?? decoded['error'];
    if (detail is String && detail.isNotEmpty) return detail;
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] is String) {
        return first['msg'] as String;
      }
      return first.toString();
    }
    return null;
  }

  static String _messageFor(int statusCode, String? detail) {
    switch (statusCode) {
      case 400:
        return detail ?? 'Requête refusée.';
      case 401:
        return 'Session expirée. Reconnectez-vous.';
      case 403:
        return detail ?? 'Accès refusé à cette session.';
      case 404:
        return detail ?? 'Ressource introuvable.';
      case 409:
        return detail ?? 'Une opération d\'enregistrement est déjà en cours.';
      case 410:
        return detail ?? 'Ce lien ou cette ressource n\'est plus disponible.';
      case 422:
        return detail ?? 'Données invalides.';
      case 429:
        return detail ?? 'Trop de demandes envoyées. Veuillez réessayer plus tard.';
      case 502:
        return 'Le serveur multimédia n\'a pas pu exécuter l\'opération.';
      case 503:
        return 'Service d\'authentification indisponible côté serveur.';
      default:
        return detail ?? 'Erreur API ($statusCode).';
    }
  }
}

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message, {this.detail});

  final int statusCode;
  final String message;
  final String? detail;

  bool get isUnauthorized => statusCode == 401;

  bool get isForbidden => statusCode == 403;

  bool get isNotFound => statusCode == 404;

  bool get isConflict => statusCode == 409;

  bool get isGone => statusCode == 410;

  bool get isUnprocessable => statusCode == 422;

  bool get isTooManyRequests => statusCode == 429;

  @override
  String toString() => message;
}
