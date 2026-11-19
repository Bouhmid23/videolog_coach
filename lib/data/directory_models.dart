// Modèles de l'annuaire des clubs/coachs, du référentiel des sports
// (`/v1/sports`) et des demandes d'adhésion (`/v1/orgs/{org_id}/join-requests`,
// `/v1/me/join-requests`).

DateTime? _parseIsoDate(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value.trim());
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

List<String> _asStringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((e) => e?.toString().trim() ?? '')
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Métadonnées d'un sport issu de `GET /v1/sports`.
class SportMeta {
  const SportMeta({
    required this.code,
    required this.label,
    required this.isIndoor,
    required this.category,
    required this.cadenceUnit,
    required this.cadenceMax,
    required this.supportsPower,
    required this.supportsGps,
    required this.supportsReps,
    required this.supportsPaceKm,
    required this.supportsPace500m,
    required this.supportsCss,
  });

  final String code;
  final String label;
  final bool isIndoor;
  final String category; // ergo | strength | skill | outdoor
  final String cadenceUnit; // rpm | spm | reps/min
  final int cadenceMax;
  final bool supportsPower;
  final bool supportsGps;
  final bool supportsReps;
  final bool supportsPaceKm;
  final bool supportsPace500m;
  final bool supportsCss;

  String get categoryLabel {
    switch (category) {
      case 'ergo':
        return 'Ergomètre';
      case 'strength':
        return 'Force & Prépa';
      case 'skill':
        return 'Technique';
      case 'outdoor':
        return 'Extérieur';
      default:
        return category;
    }
  }

  /// Liste des libellés de métriques / capteurs pris en charge par ce sport.
  List<String> get supportedMetricLabels {
    final metrics = <String>[
      if (supportsPower) 'Puissance (W)',
      if (supportsPaceKm) 'Allure /km',
      if (supportsPace500m) 'Allure /500m',
      if (supportsCss) 'CSS /100m',
      if (supportsReps) 'Répétitions',
      if (supportsGps) 'GPS',
      if (cadenceUnit.trim().isNotEmpty) 'Cadence ($cadenceUnit)',
    ];
    return metrics;
  }

  factory SportMeta.fromJson(Map<String, dynamic> j) {
    final code = (j['code'] ?? '').toString().trim();
    final label = (j['label'] ?? code).toString().trim();
    return SportMeta(
      code: code,
      label: label.isNotEmpty ? label : code,
      isIndoor: j['is_indoor'] == true,
      category: (j['category'] ?? 'outdoor').toString().trim(),
      cadenceUnit: (j['cadence_unit'] ?? 'rpm').toString().trim(),
      cadenceMax: _asInt(j['cadence_max']) ?? 120,
      supportsPower: j['supports_power'] == true,
      supportsGps: j['supports_gps'] == true,
      supportsReps: j['supports_reps'] == true,
      supportsPaceKm: j['supports_pace_km'] == true,
      supportsPace500m: j['supports_pace_500m'] == true,
      supportsCss: j['supports_css'] == true,
    );
  }
}

class SportCoachSummary {
  const SportCoachSummary({
    required this.uid,
    required this.name,
    this.level,
    this.yearsExperience,
  });

  final String uid;
  final String name;
  final String? level;
  final int? yearsExperience;

  factory SportCoachSummary.fromJson(Map<String, dynamic> j) =>
      SportCoachSummary(
        uid: (j['uid'] ?? '').toString().trim(),
        name: (j['name'] ?? 'Coach').toString().trim(),
        level: j['level']?.toString().trim(),
        yearsExperience: _asInt(j['years_experience']),
      );
}

class DirectoryGroup {
  const DirectoryGroup({
    required this.id,
    required this.name,
    required this.sport,
    this.sportLabel,
    this.isIndoor = false,
    this.category,
    this.coachUids = const [],
  });

  final String id;
  final String name;
  final String sport;
  final String? sportLabel;
  final bool isIndoor;
  final String? category;
  final List<String> coachUids;

  factory DirectoryGroup.fromJson(Map<String, dynamic> j) => DirectoryGroup(
        id: (j['id'] ?? '').toString().trim(),
        name: (j['name'] ?? '').toString().trim(),
        sport: (j['sport'] ?? '').toString().trim(),
        sportLabel: j['sport_label']?.toString().trim(),
        isIndoor: j['is_indoor'] == true,
        category: j['category']?.toString().trim(),
        coachUids: _asStringList(j['coach_uids']),
      );
}

class OrgSportDetail extends SportMeta {
  const OrgSportDetail({
    required super.code,
    required super.label,
    required super.isIndoor,
    required super.category,
    required super.cadenceUnit,
    required super.cadenceMax,
    required super.supportsPower,
    required super.supportsGps,
    required super.supportsReps,
    required super.supportsPaceKm,
    required super.supportsPace500m,
    required super.supportsCss,
    required this.levels,
    this.maxYearsExperience,
    required this.groups,
    required this.coaches,
  });

  final List<String> levels;
  final int? maxYearsExperience;
  final List<DirectoryGroup> groups;
  final List<SportCoachSummary> coaches;

  factory OrgSportDetail.fromJson(Map<String, dynamic> j) {
    final base = SportMeta.fromJson(j);
    final rawGroups = j['groups'];
    final rawCoaches = j['coaches'];
    return OrgSportDetail(
      code: base.code,
      label: base.label,
      isIndoor: base.isIndoor,
      category: base.category,
      cadenceUnit: base.cadenceUnit,
      cadenceMax: base.cadenceMax,
      supportsPower: base.supportsPower,
      supportsGps: base.supportsGps,
      supportsReps: base.supportsReps,
      supportsPaceKm: base.supportsPaceKm,
      supportsPace500m: base.supportsPace500m,
      supportsCss: base.supportsCss,
      levels: _asStringList(j['levels']),
      maxYearsExperience: _asInt(j['max_years_experience']),
      groups: rawGroups is List
          ? rawGroups
                .whereType<Map>()
                .map(
                  (e) => DirectoryGroup.fromJson(Map<String, dynamic>.from(e)),
                )
                .where((g) => g.id.isNotEmpty)
                .toList()
          : const [],
      coaches: rawCoaches is List
          ? rawCoaches
                .whereType<Map>()
                .map(
                  (e) =>
                      SportCoachSummary.fromJson(Map<String, dynamic>.from(e)),
                )
                .where((c) => c.uid.isNotEmpty)
                .toList()
          : const [],
    );
  }
}

class DirectoryCoachSport {
  const DirectoryCoachSport({
    required this.code,
    required this.label,
    required this.isIndoor,
    this.category,
    required this.level,
    this.yearsExperience,
  });

  final String code;
  final String label;
  final bool isIndoor;
  final String? category;
  final String level;
  final int? yearsExperience;

  factory DirectoryCoachSport.fromJson(Map<String, dynamic> j) {
    final code = (j['code'] ?? '').toString().trim();
    final label = (j['label'] ?? code).toString().trim();
    return DirectoryCoachSport(
      code: code,
      label: label.isNotEmpty ? label : code,
      isIndoor: j['is_indoor'] == true,
      category: j['category']?.toString().trim(),
      level: (j['level'] ?? 'loisir').toString().trim(),
      yearsExperience: _asInt(j['years_experience']),
    );
  }
}

class DirectoryCoach {
  const DirectoryCoach({
    required this.uid,
    required this.name,
    required this.role,
    this.photoUrl,
    this.certifications,
    this.bio,
    required this.sports,
  });

  final String uid;
  final String name;
  final String role;
  final String? photoUrl;
  final String? certifications;
  final String? bio;
  final List<DirectoryCoachSport> sports;

  String get roleLabel {
    switch (role) {
      case 'owner':
        return 'Responsable';
      case 'admin':
        return 'Administrateur';
      case 'coach':
      default:
        return 'Coach';
    }
  }

  factory DirectoryCoach.fromJson(Map<String, dynamic> j) {
    final rawSports = j['sports'];
    return DirectoryCoach(
      uid: (j['uid'] ?? '').toString().trim(),
      name: (j['name'] ?? 'Coach').toString().trim(),
      role: (j['role'] ?? 'coach').toString().trim(),
      photoUrl: j['photo_url']?.toString().trim(),
      certifications: j['certifications']?.toString().trim(),
      bio: j['bio']?.toString().trim(),
      sports: rawSports is List
          ? rawSports
                .whereType<Map>()
                .map(
                  (e) =>
                      DirectoryCoachSport.fromJson(Map<String, dynamic>.from(e)),
                )
                .where((s) => s.code.isNotEmpty)
                .toList()
          : const [],
    );
  }
}

class DirectoryOrganization {
  const DirectoryOrganization({
    required this.id,
    required this.type,
    required this.name,
    this.description,
    this.city,
    required this.country,
    this.logoUrl,
    required this.acceptingJoinRequests,
    required this.sports,
    required this.sportsDetails,
    required this.hasIndoorSports,
    required this.coaches,
    required this.groups,
    required this.athletesCount,
    required this.coachesCount,
    required this.groupsCount,
    required this.isMember,
    this.myRole,
    this.pendingRequestId,
    this.createdAt,
  });

  final String id;
  final String type; // club | solo_coach
  final String name;
  final String? description;
  final String? city;
  final String country;
  final String? logoUrl;
  final bool acceptingJoinRequests;
  final List<String> sports;
  final List<OrgSportDetail> sportsDetails;
  final bool hasIndoorSports;
  final List<DirectoryCoach> coaches;
  final List<DirectoryGroup> groups;
  final int athletesCount;
  final int coachesCount;
  final int groupsCount;
  final bool isMember;
  final String? myRole;
  final String? pendingRequestId;
  final DateTime? createdAt;

  bool get isSoloCoach => type == 'solo_coach';
  String get typeLabel => isSoloCoach ? 'Coach privé' : 'Club';
  bool get hasPendingRequest =>
      pendingRequestId != null && pendingRequestId!.trim().isNotEmpty;

  DirectoryOrganization copyWith({
    bool? isMember,
    String? myRole,
    String? pendingRequestId,
    bool clearPendingRequestId = false,
    bool? acceptingJoinRequests,
  }) {
    return DirectoryOrganization(
      id: id,
      type: type,
      name: name,
      description: description,
      city: city,
      country: country,
      logoUrl: logoUrl,
      acceptingJoinRequests:
          acceptingJoinRequests ?? this.acceptingJoinRequests,
      sports: sports,
      sportsDetails: sportsDetails,
      hasIndoorSports: hasIndoorSports,
      coaches: coaches,
      groups: groups,
      athletesCount: athletesCount,
      coachesCount: coachesCount,
      groupsCount: groupsCount,
      isMember: isMember ?? this.isMember,
      myRole: myRole ?? this.myRole,
      pendingRequestId: clearPendingRequestId
          ? null
          : (pendingRequestId ?? this.pendingRequestId),
      createdAt: createdAt,
    );
  }

  factory DirectoryOrganization.fromJson(Map<String, dynamic> j) {
    final counts = j['counts'] is Map
        ? Map<String, dynamic>.from(j['counts'] as Map)
        : const <String, dynamic>{};
    final rawDetails = j['sports_details'];
    final rawCoaches = j['coaches'];
    final rawGroups = j['groups'];
    final pendingRaw = j['pending_request_id']?.toString().trim();

    return DirectoryOrganization(
      id: (j['id'] ?? '').toString().trim(),
      type: (j['type'] ?? 'club').toString().trim(),
      name: (j['name'] ?? '').toString().trim(),
      description: j['description']?.toString().trim(),
      city: j['city']?.toString().trim(),
      country: (j['country'] ?? 'FR').toString().trim(),
      logoUrl: j['logo_url']?.toString().trim(),
      acceptingJoinRequests: j['accepting_join_requests'] != false,
      sports: _asStringList(j['sports']),
      sportsDetails: rawDetails is List
          ? rawDetails
                .whereType<Map>()
                .map(
                  (e) => OrgSportDetail.fromJson(Map<String, dynamic>.from(e)),
                )
                .where((s) => s.code.isNotEmpty)
                .toList()
          : const [],
      hasIndoorSports: j['has_indoor_sports'] == true,
      coaches: rawCoaches is List
          ? rawCoaches
                .whereType<Map>()
                .map(
                  (e) => DirectoryCoach.fromJson(Map<String, dynamic>.from(e)),
                )
                .where((c) => c.uid.isNotEmpty)
                .toList()
          : const [],
      groups: rawGroups is List
          ? rawGroups
                .whereType<Map>()
                .map(
                  (e) => DirectoryGroup.fromJson(Map<String, dynamic>.from(e)),
                )
                .where((g) => g.id.isNotEmpty)
                .toList()
          : const [],
      athletesCount: _asInt(counts['athletes']) ?? 0,
      coachesCount: _asInt(counts['coaches']) ?? 0,
      groupsCount: _asInt(counts['groups']) ?? 0,
      isMember: j['is_member'] == true,
      myRole: j['my_role']?.toString().trim(),
      pendingRequestId:
          (pendingRaw == null || pendingRaw.isEmpty) ? null : pendingRaw,
      createdAt: _parseIsoDate(j['created_at']),
    );
  }
}

class DirectoryPageResult {
  const DirectoryPageResult({
    required this.organizations,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<DirectoryOrganization> organizations;
  final int total;
  final int limit;
  final int offset;

  bool get hasMore => offset + organizations.length < total;
}

class DirectoryOrganizationDetail {
  const DirectoryOrganizationDetail({
    required this.organization,
    this.myJoinRequest,
  });

  final DirectoryOrganization organization;
  final MyJoinRequest? myJoinRequest;

  factory DirectoryOrganizationDetail.fromJson(Map<String, dynamic> j) {
    final orgJson = j['organization'] is Map
        ? Map<String, dynamic>.from(j['organization'] as Map)
        : j;
    final org = DirectoryOrganization.fromJson(orgJson);
    final rawReq = j['my_join_request'];
    final req = rawReq is Map
        ? MyJoinRequest.fromJson(
            Map<String, dynamic>.from(rawReq),
            fallbackOrgId: org.id,
            fallbackOrgName: org.name,
            fallbackOrgType: org.type,
            fallbackOrgCity: org.city,
          )
        : null;
    return DirectoryOrganizationDetail(
      organization: org,
      myJoinRequest: req,
    );
  }
}

class MyJoinRequest {
  const MyJoinRequest({
    required this.id,
    required this.orgId,
    required this.orgName,
    required this.orgType,
    this.orgCity,
    this.orgSportsDetails = const [],
    required this.requestedSports,
    this.requestedSportsDetails = const [],
    this.requestedGroupId,
    this.requestedGroupName,
    this.targetCoachUid,
    this.targetCoachName,
    this.message,
    required this.status,
    this.decisionNote,
    this.createdAt,
    this.decidedAt,
  });

  final String id;
  final String orgId;
  final String orgName;
  final String orgType;
  final String? orgCity;
  final List<SportMeta> orgSportsDetails;
  final List<String> requestedSports;
  final List<SportMeta> requestedSportsDetails;
  final String? requestedGroupId;
  final String? requestedGroupName;
  final String? targetCoachUid;
  final String? targetCoachName;
  final String? message;
  final String status; // pending | approved | rejected | cancelled
  final String? decisionNote;
  final DateTime? createdAt;
  final DateTime? decidedAt;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isCancelled => status == 'cancelled';
  bool get isSoloCoach => orgType == 'solo_coach';

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'En attente';
      case 'approved':
        return 'Acceptée';
      case 'rejected':
        return 'Refusée';
      case 'cancelled':
        return 'Annulée';
      default:
        return status;
    }
  }

  MyJoinRequest copyWith({String? status}) {
    return MyJoinRequest(
      id: id,
      orgId: orgId,
      orgName: orgName,
      orgType: orgType,
      orgCity: orgCity,
      orgSportsDetails: orgSportsDetails,
      requestedSports: requestedSports,
      requestedSportsDetails: requestedSportsDetails,
      requestedGroupId: requestedGroupId,
      requestedGroupName: requestedGroupName,
      targetCoachUid: targetCoachUid,
      targetCoachName: targetCoachName,
      message: message,
      status: status ?? this.status,
      decisionNote: decisionNote,
      createdAt: createdAt,
      decidedAt: decidedAt,
    );
  }

  factory MyJoinRequest.fromJson(
    Map<String, dynamic> j, {
    String? fallbackOrgId,
    String? fallbackOrgName,
    String? fallbackOrgType,
    String? fallbackOrgCity,
  }) {
    final rawOrgSports = j['org_sports_details'];
    final rawReqSports = j['requested_sports_details'];
    return MyJoinRequest(
      id: (j['id'] ?? '').toString().trim(),
      orgId: (j['org_id'] ?? fallbackOrgId ?? '').toString().trim(),
      orgName: (j['org_name'] ?? fallbackOrgName ?? 'Organisation')
          .toString()
          .trim(),
      orgType: (j['org_type'] ?? fallbackOrgType ?? 'club').toString().trim(),
      orgCity: (j['org_city'] ?? fallbackOrgCity)?.toString().trim(),
      orgSportsDetails: rawOrgSports is List
          ? rawOrgSports
                .whereType<Map>()
                .map((e) => SportMeta.fromJson(Map<String, dynamic>.from(e)))
                .where((s) => s.code.isNotEmpty)
                .toList()
          : const [],
      requestedSports: _asStringList(j['requested_sports']),
      requestedSportsDetails: rawReqSports is List
          ? rawReqSports
                .whereType<Map>()
                .map((e) => SportMeta.fromJson(Map<String, dynamic>.from(e)))
                .where((s) => s.code.isNotEmpty)
                .toList()
          : const [],
      requestedGroupId: j['requested_group_id']?.toString().trim(),
      requestedGroupName: j['requested_group_name']?.toString().trim(),
      targetCoachUid: j['target_coach_uid']?.toString().trim(),
      targetCoachName: j['target_coach_name']?.toString().trim(),
      message: j['message']?.toString().trim(),
      status: (j['status'] ?? 'pending').toString().trim(),
      decisionNote: j['decision_note']?.toString().trim(),
      createdAt: _parseIsoDate(j['created_at']),
      decidedAt: _parseIsoDate(j['decided_at']),
    );
  }
}
