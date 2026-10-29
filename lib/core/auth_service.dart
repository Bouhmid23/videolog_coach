import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Abstraction de stockage chiffré (Keystore Android / Keychain iOS) injectable en test.
abstract class SecureTokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureTokenStore implements SecureTokenStore {
  const FlutterSecureTokenStore([
    this._storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    ),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Encapsule Firebase Authentication, l'identité utilisateur courante et le
/// stockage sécurisé du JWT (Keystore Android / Keychain iOS).
///
/// Le mot de passe n'est jamais transmis à l'API Videolog : seule la
/// connexion Firebase le reçoit. Les appels API utilisent ensuite un ID token
/// Firebase en `Authorization: Bearer`.
class AuthService extends ChangeNotifier {
  AuthService._()
    : _secureStore = const FlutterSecureTokenStore(),
      _tokenProviderOverride = null {
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        unawaited(clearSecureTokens());
      }
      notifyListeners();
    });
  }

  /// Constructeur dédié aux tests unitaires (sans dépendance à Firebase natif).
  @visibleForTesting
  AuthService.forTesting({
    required SecureTokenStore secureStore,
    Future<String?> Function({required bool forceRefresh})? tokenProvider,
  }) : _secureStore = secureStore,
       _tokenProviderOverride = tokenProvider;

  static final AuthService instance = AuthService._();

  static const String kJwtKey = 'auth_id_token_jwt';
  static const String kRememberMeKey = 'auth_remember_me';
  static const List<String> _legacyPlaintextTokenKeys = <String>[
    'jwt',
    'id_token',
    'auth_token',
    'token',
  ];
  static const String _legacyRememberMeKey = 'remember_me';

  final SecureTokenStore _secureStore;
  final Future<String?> Function({required bool forceRefresh})?
  _tokenProviderOverride;

  FirebaseAuth get _auth => FirebaseAuth.instance;

  User? get user => _auth.currentUser;

  bool get isSignedIn => user != null;

  String get uid => user?.uid ?? '';

  String? get email => user?.email;

  /// Nom affiché localement. L'identité LiveKit reste l'UID Firebase géré
  /// par le serveur ; ce nom ne sert qu'à l'interface.
  String get displayName {
    final current = user;
    if (current == null) return '';
    final name = current.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final address = current.email;
    if (address != null && address.contains('@')) {
      return address.split('@').first;
    }
    return current.uid;
  }

  /// Migre tout éventuel JWT ou réglage d'authentification stocké en clair
  /// dans `SharedPreferences` vers `FlutterSecureStorage` puis purge le clair.
  Future<void> migrateFromSharedPreferences([SharedPreferences? prefs]) async {
    final sharedPrefs = prefs ?? await SharedPreferences.getInstance();

    for (final legacyKey in _legacyPlaintextTokenKeys) {
      final legacyToken = sharedPrefs.getString(legacyKey);
      if (legacyToken != null && legacyToken.isNotEmpty) {
        final existingSecure = await _secureStore.read(kJwtKey);
        if (existingSecure == null || existingSecure.isEmpty) {
          await _secureStore.write(kJwtKey, legacyToken);
        }
        await sharedPrefs.remove(legacyKey);
      }
    }

    if (sharedPrefs.containsKey(_legacyRememberMeKey)) {
      final remember = sharedPrefs.getBool(_legacyRememberMeKey) ?? true;
      await _secureStore.write(kRememberMeKey, remember ? 'true' : 'false');
      await sharedPrefs.remove(_legacyRememberMeKey);
    }
  }

  /// Enregistre la préférence « Se souvenir de moi » dans le stockage sécurisé.
  Future<void> setRememberMe(bool rememberMe) async {
    await _secureStore.write(kRememberMeKey, rememberMe ? 'true' : 'false');
  }

  /// Lit la préférence « Se souvenir de moi » depuis le stockage sécurisé (par défaut `true`).
  Future<bool> getRememberMe() async {
    final raw = await _secureStore.read(kRememberMeKey);
    if (raw == null) return true;
    return raw == 'true';
  }

  /// Applique la politique « Se souvenir de moi » au démarrage de l'application
  /// après avoir migré d'éventuelles données de `SharedPreferences`.
  Future<void> enforceRememberMePolicyOnStartup() async {
    try {
      await migrateFromSharedPreferences();
    } catch (e, st) {
      debugPrint('Migration SharedPreferences ignorée: $e\n$st');
    }
    final remember = await getRememberMe();
    if (!remember) {
      await signOut();
    }
  }

  /// Lit le dernier JWT stocké dans le Keystore / Keychain.
  Future<String?> readSecureJwt() => _secureStore.read(kJwtKey);

  /// Efface le JWT du Keystore / Keychain.
  Future<void> clearSecureTokens() => _secureStore.delete(kJwtKey);

  /// Connexion email / mot de passe directement auprès de Firebase, suivie de
  /// la mise en coffre-fort (`FlutterSecureStorage`) du JWT.
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final token = await credential.user?.getIdToken();
    if (token != null && token.isNotEmpty) {
      await _secureStore.write(kJwtKey, token);
    }
  }

  Future<void> signOut() async {
    await clearSecureTokens();
    if (_tokenProviderOverride == null) {
      await _auth.signOut();
    }
  }

  /// Retourne l'ID token courant, en le persistant dans `FlutterSecureStorage`
  /// (Keystore Android / Keychain iOS).
  Future<String> requireIdToken({bool forceRefresh = false}) async {
    final override = _tokenProviderOverride;
    if (override != null) {
      final token = await override(forceRefresh: forceRefresh);
      if (token != null && token.isNotEmpty) {
        await _secureStore.write(kJwtKey, token);
        return token;
      }
      final cached = await _secureStore.read(kJwtKey);
      if (!forceRefresh && cached != null && cached.isNotEmpty) {
        return cached;
      }
      throw const AuthException('Impossible de récupérer le jeton Firebase.');
    }

    final current = _auth.currentUser;
    if (current == null) {
      await clearSecureTokens();
      throw const AuthException('Utilisateur Firebase non connecté.');
    }
    final token = await current.getIdToken(forceRefresh);
    if (token == null || token.isEmpty) {
      throw const AuthException('Impossible de récupérer le jeton Firebase.');
    }
    await _secureStore.write(kJwtKey, token);
    return token;
  }

  /// Message lisible pour les erreurs d'authentification.
  static String messageFor(Object error) {
    if (error is AuthException) return error.message;
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-credential':
        case 'wrong-password':
        case 'user-not-found':
          return 'Email ou mot de passe incorrect.';
        case 'invalid-email':
          return 'Adresse email invalide.';
        case 'user-disabled':
          return 'Ce compte a été désactivé.';
        case 'too-many-requests':
          return 'Trop de tentatives. Réessayez dans quelques minutes.';
        case 'network-request-failed':
          return 'Réseau indisponible. Vérifiez votre connexion.';
        case 'operation-not-allowed':
          return 'La connexion email / mot de passe n\'est pas activée.';
        case 'weak-password':
          return 'Mot de passe trop faible.';
        case 'email-already-in-use':
          return 'Un compte existe déjà pour cet email.';
        default:
          return 'Connexion impossible (${error.code}).';
      }
    }
    return 'Connexion impossible. Réessayez.';
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
