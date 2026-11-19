import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/account_models.dart';
import '../data/athlete_profile.dart';
import 'api_service.dart';
import 'auth_service.dart';

/// Gère l'état du compte Videolog (`/v1/me`), l'organisation active,
/// les droits par rôle et la synchronisation du profil athlète.
class AccountController extends ChangeNotifier {
  AccountController._({
    AuthService? authService,
    ApiService? apiService,
  }) : _auth = authService ?? AuthService.instance,
       _api = apiService ?? ApiService.instance {
    _auth.addListener(_onAuthChanged);
  }

  @visibleForTesting
  AccountController.forTesting({
    required AuthService authService,
    required ApiService apiService,
  }) : _auth = authService,
       _api = apiService;

  static final AccountController instance = AccountController._();

  static const String _activeOrgKeyPrefix = 'active_org_id_';

  final AuthService _auth;
  final ApiService _api;

  AccountMe? _me;
  String? _activeOrgId;
  String? _pendingInviteToken;
  bool _loading = false;
  String? _error;
  String? _loadedForUid;
  Future<void>? _inFlight;

  AccountMe? get me => _me;
  bool get loading => _loading;
  String? get error => _error;
  String? get pendingInviteToken => _pendingInviteToken;

  List<OrgMembership> get memberships => _me?.memberships ?? const [];

  bool get hasLoaded => _me != null && _loadedForUid == _auth.uid;

  bool get needsOnboarding => _me?.needsOnboarding ?? false;

  bool get isEmailVerified =>
      _auth.isEmailVerified || (_me?.emailVerified ?? false);

  OrgMembership? get activeMembership {
    final list = memberships;
    if (list.isEmpty) return null;
    if (_activeOrgId != null) {
      for (final m in list) {
        if (m.orgId == _activeOrgId) return m;
      }
    }
    return list.first;
  }

  String get uid {
    final serverUid = _me?.uid.trim();
    if (serverUid != null && serverUid.isNotEmpty) return serverUid;
    return _auth.uid;
  }

  bool get hasHealthConsent => _me?.user?.healthConsent?.granted == true;

  String? get activeOrgId => activeMembership?.orgId;

  String get activeRole => activeMembership?.role ?? 'athlete';

  bool get canManageSessions => activeMembership?.canManageSessions ?? false;

  bool get canManageMarkers => activeMembership?.canManageMarkers ?? false;

  String get displayName {
    final full = _me?.user?.fullName.trim();
    if (full != null && full.isNotEmpty) return full;
    return _auth.displayName;
  }

  void _onAuthChanged() {
    if (!_auth.isSignedIn) {
      clear();
      return;
    }
    if (_loadedForUid != _auth.uid && _inFlight == null) {
      unawaited(refresh());
    }
  }

  /// Extrait un token d'invitation depuis un lien (`https://.../invite/<token>`,
  /// `videolog://invite/<token>`, `?token=<token>`) ou une chaîne brute.
  static String? extractInviteToken(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      if (uri.host == 'invite' && uri.pathSegments.isNotEmpty) {
        final token = uri.pathSegments.first.trim();
        return token.isEmpty ? null : token;
      }
      if (uri.pathSegments.isNotEmpty) {
        final idx = uri.pathSegments.indexOf('invite');
        if (idx != -1 && idx + 1 < uri.pathSegments.length) {
          final token = uri.pathSegments[idx + 1].trim();
          return token.isEmpty ? null : token;
        }
      }
      final queryToken = uri.queryParameters['token']?.trim();
      if (queryToken != null && queryToken.isNotEmpty) {
        return queryToken;
      }
    }
    if (!trimmed.contains('/') && !trimmed.contains(' ')) {
      return trimmed;
    }
    return null;
  }

  void setPendingInviteToken(String? token) {
    final normalized = token?.trim();
    _pendingInviteToken =
        (normalized == null || normalized.isEmpty) ? null : normalized;
    notifyListeners();
  }

  Future<void> selectOrganization(String orgId) async {
    if (!memberships.any((m) => m.orgId == orgId)) return;
    _activeOrgId = orgId;
    final uid = _auth.uid;
    if (uid.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_activeOrgKeyPrefix$uid', orgId);
    }
    notifyListeners();
  }

  Future<void> refresh({bool syncAthleteProfile = true}) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _doRefresh(syncAthleteProfile: syncAthleteProfile);
    _inFlight = future.whenComplete(() => _inFlight = null);
    return _inFlight!;
  }

  Future<void> _doRefresh({required bool syncAthleteProfile}) async {
    // Diffère d'une microtask afin de ne jamais déclencher notifyListeners()
    // synchronement pendant initState(), build() ou LayoutBuilder.
    await Future<void>.microtask(() {});
    if (!_auth.isSignedIn) {
      clear();
      return;
    }
    final currentUid = _auth.uid;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final fetched = await _api.fetchMe();
      _me = fetched;
      _loadedForUid = currentUid;
      _error = null;

      if (currentUid.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final savedOrgId = prefs.getString('$_activeOrgKeyPrefix$currentUid');
        if (savedOrgId != null &&
            fetched.memberships.any((m) => m.orgId == savedOrgId)) {
          _activeOrgId = savedOrgId;
        } else if (fetched.memberships.isNotEmpty) {
          _activeOrgId = fetched.memberships.first.orgId;
        } else {
          _activeOrgId = null;
        }

        if (syncAthleteProfile) {
          await _syncLocalAthleteProfile(prefs, currentUid, fetched.user);
        }
      }
    } on ApiException catch (e) {
      _error = e.message;
      if (e.isUnauthorized) {
        await _auth.signOut();
      }
    } catch (_) {
      _error = 'Impossible de récupérer votre profil Videolog.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _syncLocalAthleteProfile(
    SharedPreferences prefs,
    String uid,
    AppUser? user,
  ) async {
    if (user == null) return;
    final local = await AthleteProfile.load(prefs, uid);
    final merged = AthleteProfile.fromServer(
      serverProfile: user.athleteProfile,
      healthConsent: user.healthConsent,
      fallback: local,
    );
    await merged.save(prefs, uid);
  }

  void clear() {
    _me = null;
    _activeOrgId = null;
    _loadedForUid = null;
    _error = null;
    _loading = false;
    notifyListeners();
  }
}
