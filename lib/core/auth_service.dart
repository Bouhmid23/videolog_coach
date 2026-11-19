import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
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
  }) : _secureStore = secureStore, // ignore: prefer_initializing_formals
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

  static const String _googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );
  static const String _googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );

  final SecureTokenStore _secureStore;
  final Future<String?> Function({required bool forceRefresh})?
  _tokenProviderOverride;
  Future<void>? _googleInitFuture;
  bool _googleInitialized = false;

  FirebaseAuth get _auth => FirebaseAuth.instance;

  User? get user => _auth.currentUser;

  bool get isSignedIn => user != null;

  bool get isEmailVerified => user?.emailVerified ?? false;

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

  /// Création de compte email / mot de passe auprès de Firebase avec envoi
  /// de l'e-mail de vérification.
  Future<void> signUp({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final current = credential.user;
    if (current != null && !current.emailVerified) {
      await current.sendEmailVerification();
    }
    final token = await current?.getIdToken();
    if (token != null && token.isNotEmpty) {
      await _secureStore.write(kJwtKey, token);
    }
  }

  /// Connexion avec un compte Google via Credential Manager / Google Sign-In,
  /// suivie de la connexion Firebase (`signInWithCredential`) et du stockage
  /// sécurisé du JWT Firebase.
  Future<void> signInWithGoogle() async {
    await _ensureGoogleInitialized();
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw const AuthException(
        'La connexion Google n\'est pas supportée sur cette plateforme.',
      );
    }
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const AuthException(
        'Jeton d\'identité Google manquant. Vérifiez la configuration OAuth Firebase.',
      );
    }
    String? accessToken;
    try {
      final authz = await account.authorizationClient.authorizationForScopes(
        const <String>['email', 'profile'],
      );
      accessToken = authz?.accessToken;
    } catch (_) {
      // L'idToken suffit pour FirebaseAuth.
    }
    final credential = GoogleAuthProvider.credential(
      idToken: idToken,
      accessToken: accessToken,
    );
    final userCred = await _auth.signInWithCredential(credential);
    final token = await userCred.user?.getIdToken();
    if (token != null && token.isNotEmpty) {
      await _secureStore.write(kJwtKey, token);
    }
  }

  /// Connexion avec Apple (iOS / macOS) via Firebase Auth provider natif.
  Future<void> signInWithApple() async {
    if (kIsWeb || (!Platform.isIOS && !Platform.isMacOS)) {
      throw const AuthException(
        'La connexion avec Apple n\'est disponible que sur iOS et macOS.',
      );
    }
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    final userCred = await _auth.signInWithProvider(provider);
    final token = await userCred.user?.getIdToken();
    if (token != null && token.isNotEmpty) {
      await _secureStore.write(kJwtKey, token);
    }
  }

  /// Envoie un e-mail de réinitialisation de mot de passe via Firebase Auth.
  Future<void> sendPasswordResetEmail(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      throw const AuthException('Veuillez saisir votre adresse e-mail.');
    }
    await _auth.sendPasswordResetEmail(email: trimmed);
  }

  Future<void> _ensureGoogleInitialized() {
    if (_googleInitFuture != null) return _googleInitFuture!;
    final webId = _googleWebClientId.trim();
    final iosId = _googleIosClientId.trim();
    final future = GoogleSignIn.instance
        .initialize(
          clientId: !kIsWeb && Platform.isIOS && iosId.isNotEmpty
              ? iosId
              : null,
          serverClientId: webId.isNotEmpty ? webId : null,
        )
        .then((_) {
          _googleInitialized = true;
        })
        .catchError((Object err) {
          _googleInitFuture = null;
          throw err;
        });
    _googleInitFuture = future;
    return future;
  }

  /// Envoie (ou renvoie) l'e-mail de vérification Firebase.
  Future<void> sendEmailVerification() async {
    final current = _auth.currentUser;
    if (current == null) {
      throw const AuthException('Utilisateur Firebase non connecté.');
    }
    await current.sendEmailVerification();
  }

  /// Recharge l'utilisateur Firebase et force le rafraîchissement du JWT
  /// (nécessaire après validation du lien dans l'e-mail de vérification).
  Future<bool> reloadAndRefreshToken() async {
    final current = _auth.currentUser;
    if (current == null) return false;
    await current.reload();
    final refreshedUser = _auth.currentUser;
    if (refreshedUser == null) return false;
    final token = await refreshedUser.getIdToken(true);
    if (token != null && token.isNotEmpty) {
      await _secureStore.write(kJwtKey, token);
    }
    notifyListeners();
    return refreshedUser.emailVerified;
  }

  Future<void> signOut() async {
    await clearSecureTokens();
    if (_googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
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

  /// Indique si l'erreur correspond à une annulation volontaire par l'utilisateur.
  static bool isCancellation(Object error) {
    if (error is GoogleSignInException &&
        error.code == GoogleSignInExceptionCode.canceled) {
      return true;
    }
    if (error is FirebaseAuthException &&
        (error.code == 'canceled' || error.code == 'web-context-canceled')) {
      return true;
    }
    return false;
  }

  /// Message lisible pour les erreurs d'authentification.
  static String messageFor(Object error) {
    if (error is AuthException) return error.message;
    if (error is GoogleSignInException) {
      switch (error.code) {
        case GoogleSignInExceptionCode.canceled:
          return 'Connexion Google annulée.';
        case GoogleSignInExceptionCode.interrupted:
          return 'Connexion Google interrompue. Réessayez.';
        case GoogleSignInExceptionCode.clientConfigurationError:
          return 'Configuration OAuth Google incomplète (vérifiez SHA-1/google-services.json dans Firebase).';
        case GoogleSignInExceptionCode.providerConfigurationError:
        case GoogleSignInExceptionCode.uiUnavailable:
          return 'Service Google Sign-In indisponible sur cet appareil.';
        case GoogleSignInExceptionCode.userMismatch:
          return 'Le compte Google sélectionné ne correspond pas.';
        case GoogleSignInExceptionCode.unknownError:
          return error.description?.isNotEmpty == true
              ? 'Connexion Google impossible : ${error.description}'
              : 'Connexion Google impossible.';
      }
    }
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
          return 'Cette méthode de connexion n\'est pas activée dans Firebase.';
        case 'account-exists-with-different-credential':
          return 'Un compte existe déjà avec cet email via une autre méthode de connexion.';
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
