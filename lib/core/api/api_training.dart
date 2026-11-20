part of '../api_service.dart';

/// Domaine API : Calendrier, Séances planifiées, Bien-être (Wellness),
/// Activités (FIT/GPX/TCX), Courbes, Commentaires, Partage, Analytics PMC & Seuils.
mixin _ApiTrainingMixin on _ApiClientBase {
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
}
