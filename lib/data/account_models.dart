/// Modèles des comptes, organisations, invitations et profils v1.
const List<String> kSupportedSports = <String>[
  'cyclisme',
  'course à pied',
  'triathlon',
  'natation',
  'aviron',
  'football',
  'rugby',
  'autre',
];

const List<String> kSupportedLevels = <String>[
  'loisir',
  'compétition régionale',
  'nationale',
  'élite',
];

const int kMinAgeYears = 15;

int computeAgeYears(DateTime birthDate, [DateTime? today]) {
  final ref = today ?? DateTime.now();
  var years = ref.year - birthDate.year;
  if (ref.month < birthDate.month ||
      (ref.month == birthDate.month && ref.day < birthDate.day)) {
    years -= 1;
  }
  return years;
}

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

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

class OrganizationSummary {
  const OrganizationSummary({
    required this.id,
    required this.type,
    required this.name,
    this.sports = const [],
    this.city,
    this.country = 'FR',
    this.ownerUid,
    this.status = 'active',
  });

  final String id;
  final String type; // 'club' | 'solo_coach'
  final String name;
  final List<String> sports;
  final String? city;
  final String country;
  final String? ownerUid;
  final String status;

  bool get isSoloCoach => type == 'solo_coach';

  factory OrganizationSummary.fromJson(Map<String, dynamic> json) {
    return OrganizationSummary(
      id: (json['id'] as String?) ?? '',
      type: (json['type'] as String?) ?? 'club',
      name: (json['name'] as String?) ?? 'Organisation',
      sports: (json['sports'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      city: json['city'] as String?,
      country: (json['country'] as String?) ?? 'FR',
      ownerUid: json['owner_uid'] as String?,
      status: (json['status'] as String?) ?? 'active',
    );
  }
}

class OrgMembership {
  const OrgMembership({
    required this.orgId,
    required this.role,
    this.groupIds = const [],
    this.organization,
    this.coaches = const [],
  });

  final String orgId;
  final String role; // 'owner' | 'admin' | 'coach' | 'athlete'
  final List<String> groupIds;
  final OrganizationSummary? organization;
  final List<OrgCoachSummary> coaches;

  bool get isOwner => role == 'owner';
  bool get isAdmin => role == 'admin';
  bool get isCoach => role == 'coach';
  bool get isAthlete => role == 'athlete';

  bool get canManageSessions =>
      role == 'owner' || role == 'admin' || role == 'coach';

  bool get canManageMarkers => canManageSessions;

  String get displayOrgName => organization?.name ?? orgId;

  String get roleLabel {
    switch (role) {
      case 'owner':
        return 'Propriétaire';
      case 'admin':
        return 'Admin';
      case 'coach':
        return 'Coach';
      case 'athlete':
        return 'Athlète';
      default:
        return role;
    }
  }

  factory OrgMembership.fromJson(Map<String, dynamic> json) {
    final rawOrg = json['organization'];
    final rawCoaches = json['coaches'] as List<dynamic>? ?? const [];
    return OrgMembership(
      orgId: (json['org_id'] as String?) ?? '',
      role: (json['role'] as String?) ?? 'athlete',
      groupIds: (json['group_ids'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      organization: rawOrg is Map
          ? OrganizationSummary.fromJson(Map<String, dynamic>.from(rawOrg))
          : null,
      coaches: rawCoaches
          .whereType<Map>()
          .map((c) => OrgCoachSummary.fromJson(Map<String, dynamic>.from(c)))
          .where((c) => c.uid.isNotEmpty)
          .toList(),
    );
  }
}

class HealthConsent {
  const HealthConsent({
    required this.granted,
    this.version,
    this.grantedAt,
  });

  final bool granted;
  final String? version;
  final DateTime? grantedAt;

  factory HealthConsent.fromJson(Map<String, dynamic> json) {
    return HealthConsent(
      granted: json['granted'] == true,
      version: json['version'] as String?,
      grantedAt: _parseIsoDate(json['granted_at']),
    );
  }
}

class ServerAthleteProfile {
  const ServerAthleteProfile({
    required this.sport,
    required this.level,
    this.birthDate,
    this.heightCm,
    this.weightKg,
    this.hrMax,
    this.hrRest,
  });

  final String sport;
  final String level;
  final DateTime? birthDate;
  final int? heightCm;
  final double? weightKg;
  final int? hrMax;
  final int? hrRest;

  factory ServerAthleteProfile.fromJson(Map<String, dynamic> json) {
    return ServerAthleteProfile(
      sport: (json['sport'] as String?) ?? 'autre',
      level: (json['level'] as String?) ?? 'loisir',
      birthDate: _parseIsoDate(json['birth_date']),
      heightCm: _asInt(json['height_cm']),
      weightKg: _asDouble(json['weight_kg']),
      hrMax: _asInt(json['hr_max']),
      hrRest: _asInt(json['hr_rest']),
    );
  }
}

class AppUser {
  const AppUser({
    required this.uid,
    this.email,
    this.emailVerified = false,
    this.firstName,
    this.lastName,
    this.phone,
    this.locale = 'fr',
    this.athleteProfile,
    this.healthConsent,
  });

  final String uid;
  final String? email;
  final bool emailVerified;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String locale;
  final ServerAthleteProfile? athleteProfile;
  final HealthConsent? healthConsent;

  String get fullName {
    final parts = [
      firstName?.trim() ?? '',
      lastName?.trim() ?? '',
    ].where((p) => p.isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.join(' ');
    return email ?? uid;
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final rawProfile = json['athlete_profile'];
    final rawConsent = json['health_consent'];
    return AppUser(
      uid: (json['uid'] as String?) ?? '',
      email: json['email'] as String?,
      emailVerified: json['email_verified'] == true,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      phone: json['phone'] as String?,
      locale: (json['locale'] as String?) ?? 'fr',
      athleteProfile: rawProfile is Map
          ? ServerAthleteProfile.fromJson(Map<String, dynamic>.from(rawProfile))
          : null,
      healthConsent: rawConsent is Map
          ? HealthConsent.fromJson(Map<String, dynamic>.from(rawConsent))
          : null,
    );
  }
}

class AccountMe {
  const AccountMe({
    required this.uid,
    this.email,
    this.emailVerified = false,
    this.platformAdmin = false,
    this.needsOnboarding = false,
    this.user,
    this.memberships = const [],
  });

  final String uid;
  final String? email;
  final bool emailVerified;
  final bool platformAdmin;
  final bool needsOnboarding;
  final AppUser? user;
  final List<OrgMembership> memberships;

  factory AccountMe.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    final rawMemberships = json['memberships'] as List<dynamic>? ?? const [];
    final memberships = rawMemberships
        .whereType<Map>()
        .map((m) => OrgMembership.fromJson(Map<String, dynamic>.from(m)))
        .where((m) => m.orgId.isNotEmpty)
        .toList();
    final needsOnboarding = json.containsKey('needs_onboarding')
        ? json['needs_onboarding'] == true
        : memberships.isEmpty && json['platform_admin'] != true;
    return AccountMe(
      uid: (json['uid'] as String?) ?? '',
      email: json['email'] as String?,
      emailVerified: json['email_verified'] == true,
      platformAdmin: json['platform_admin'] == true,
      needsOnboarding: needsOnboarding,
      user: rawUser is Map
          ? AppUser.fromJson(Map<String, dynamic>.from(rawUser))
          : null,
      memberships: memberships,
    );
  }
}

class InvitationPreview {
  const InvitationPreview({
    required this.orgName,
    required this.orgType,
    required this.role,
    required this.maskedEmail,
    this.expiresAt,
  });

  final String orgName;
  final String orgType;
  final String role;
  final String maskedEmail;
  final DateTime? expiresAt;

  String get roleLabel => switch (role) {
    'coach' => 'Coach',
    'athlete' => 'Athlète',
    'admin' => 'Administrateur',
    _ => role,
  };

  factory InvitationPreview.fromJson(Map<String, dynamic> json) {
    return InvitationPreview(
      orgName: (json['org_name'] as String?) ?? 'Organisation',
      orgType: (json['org_type'] as String?) ?? 'club',
      role: (json['role'] as String?) ?? 'athlete',
      maskedEmail: (json['masked_email'] as String?) ?? '',
      expiresAt: _parseIsoDate(json['expires_at']),
    );
  }
}

class OrgGroup {
  const OrgGroup({
    required this.id,
    required this.orgId,
    required this.name,
    this.sport = 'autre',
    this.coachUids = const [],
  });

  final String id;
  final String orgId;
  final String name;
  final String sport;
  final List<String> coachUids;

  factory OrgGroup.fromJson(Map<String, dynamic> json) {
    return OrgGroup(
      id: (json['id'] as String?) ?? '',
      orgId: (json['org_id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      sport: (json['sport'] as String?) ?? 'autre',
      coachUids: (json['coach_uids'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class OrgMemberSummary {
  const OrgMemberSummary({
    required this.uid,
    required this.role,
    this.groupIds = const [],
    this.email,
    this.firstName,
    this.lastName,
    this.hasAthleteProfile = false,
    this.sport,
    this.level,
  });

  final String uid;
  final String role;
  final List<String> groupIds;
  final String? email;
  final String? firstName;
  final String? lastName;
  final bool hasAthleteProfile;
  final String? sport;
  final String? level;

  String get displayName {
    final full = [
      firstName?.trim() ?? '',
      lastName?.trim() ?? '',
    ].where((p) => p.isNotEmpty).join(' ');
    if (full.isNotEmpty) return full;
    if (email != null && email!.isNotEmpty) return email!;
    return uid;
  }

  factory OrgMemberSummary.fromJson(Map<String, dynamic> json) {
    return OrgMemberSummary(
      uid: (json['uid'] as String?) ?? '',
      role: (json['role'] as String?) ?? 'athlete',
      groupIds: (json['group_ids'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      email: json['email'] as String?,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      hasAthleteProfile: json['has_athlete_profile'] == true,
      sport: json['sport'] as String?,
      level: json['level'] as String?,
    );
  }
}

class CoachSportEntry {
  const CoachSportEntry({
    required this.sport,
    this.level = 'loisir',
    this.yearsExperience,
  });

  final String sport;
  final String level;
  final int? yearsExperience;

  factory CoachSportEntry.fromJson(Map<String, dynamic> json) {
    return CoachSportEntry(
      sport: (json['sport'] as String?) ?? 'autre',
      level: (json['level'] as String?) ?? 'loisir',
      yearsExperience: _asInt(json['years_experience']),
    );
  }
}

class CoachProfile {
  const CoachProfile({
    this.sports = const [],
    this.certifications,
    this.bio,
  });

  final List<CoachSportEntry> sports;
  final String? certifications;
  final String? bio;

  bool get isEmpty =>
      sports.isEmpty &&
      (certifications == null || certifications!.trim().isEmpty) &&
      (bio == null || bio!.trim().isEmpty);

  factory CoachProfile.fromJson(Map<String, dynamic> json) {
    final rawSports = json['sports'] as List<dynamic>? ?? const [];
    return CoachProfile(
      sports: rawSports
          .whereType<Map>()
          .map((s) => CoachSportEntry.fromJson(Map<String, dynamic>.from(s)))
          .toList(),
      certifications: (json['certifications'] as String?)?.trim(),
      bio: (json['bio'] as String?)?.trim(),
    );
  }
}

class OrgCoachSummary {
  const OrgCoachSummary({
    required this.uid,
    required this.name,
    this.role = 'coach',
    this.coachProfile,
  });

  final String uid;
  final String name;
  final String role;
  final CoachProfile? coachProfile;

  String get roleLabel => switch (role) {
    'owner' => 'Coach propriétaire',
    'admin' => 'Administrateur',
    'coach' => 'Coach',
    _ => role,
  };

  factory OrgCoachSummary.fromJson(Map<String, dynamic> json) {
    final rawProfile = json['coach_profile'];
    return OrgCoachSummary(
      uid: (json['uid'] as String?) ?? '',
      name: (json['name'] as String?) ?? (json['uid'] as String? ?? 'Coach'),
      role: (json['role'] as String?) ?? 'coach',
      coachProfile: rawProfile is Map
          ? CoachProfile.fromJson(Map<String, dynamic>.from(rawProfile))
          : null,
    );
  }
}

class InAppInvitation {
  const InAppInvitation({
    required this.id,
    required this.orgId,
    required this.orgName,
    this.orgType = 'club',
    this.role = 'athlete',
    this.inviterName,
    this.email,
    this.status = 'pending',
    this.expiresAt,
    this.createdAt,
  });

  final String id;
  final String orgId;
  final String orgName;
  final String orgType;
  final String role;
  final String? inviterName;
  final String? email;
  final String status;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  bool get isSoloCoach => orgType == 'solo_coach';

  String get orgTypeLabel => isSoloCoach ? 'Coach privé' : 'Club';

  String get roleLabel => switch (role) {
    'coach' => 'Coach',
    'athlete' => 'Athlète',
    'admin' => 'Administrateur',
    _ => role,
  };

  factory InAppInvitation.fromJson(Map<String, dynamic> json) {
    return InAppInvitation(
      id: (json['id'] as String?) ?? '',
      orgId: (json['org_id'] as String?) ?? '',
      orgName: (json['org_name'] as String?) ?? 'Organisation',
      orgType: (json['org_type'] as String?) ?? 'club',
      role: (json['role'] as String?) ?? 'athlete',
      inviterName: (json['inviter_name'] as String?)?.trim(),
      email: json['email'] as String?,
      status: (json['status'] as String?) ?? 'pending',
      expiresAt: _parseIsoDate(json['expires_at']),
      createdAt: _parseIsoDate(json['created_at']),
    );
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    this.type = 'info',
    this.body = '',
    this.link,
    this.orgId,
    this.read = false,
    this.createdAt,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final String? link;
  final String? orgId;
  final bool read;
  final DateTime? createdAt;

  AppNotification copyWith({bool? read}) {
    return AppNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      link: link,
      orgId: orgId,
      read: read ?? this.read,
      createdAt: createdAt,
    );
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? 'info').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      link: json['link']?.toString(),
      orgId: json['org_id']?.toString(),
      read: json['read'] == true,
      createdAt: _parseIsoDate(json['created_at']),
    );
  }
}

class NotificationsResponse {
  const NotificationsResponse({
    this.items = const [],
    this.unreadCount = 0,
  });

  final List<AppNotification> items;
  final int unreadCount;

  factory NotificationsResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    final items = rawItems
        .whereType<Map>()
        .map((n) => AppNotification.fromJson(Map<String, dynamic>.from(n)))
        .where((n) => n.id.isNotEmpty)
        .toList();
    final parsedUnread = _asInt(json['unread_count']);
    return NotificationsResponse(
      items: items,
      unreadCount: parsedUnread ?? items.where((n) => !n.read).length,
    );
  }
}
