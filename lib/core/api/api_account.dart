part of '../api_service.dart';

/// Domaine API : Compte utilisateur (/v1/me), Onboarding, Profil athlète,
/// Consentement santé, Invitations et Notifications.
mixin _ApiAccountMixin on _ApiClientBase {
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

  // ── Invitations (/v1/invitations & /v1/me/invitations) ─────────────────────

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
}
