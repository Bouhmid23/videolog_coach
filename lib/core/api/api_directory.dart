part of '../api_service.dart';

/// Domaine API : Organisations, Groupes, Membres, Référentiel des sports,
/// Annuaire public des clubs/coachs et Demandes d'adhésion.
mixin _ApiDirectoryMixin on _ApiClientBase {
  // ── Organisations, Groupes & Membres (/v1/orgs/{org_id}) ───────────────────

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
}
