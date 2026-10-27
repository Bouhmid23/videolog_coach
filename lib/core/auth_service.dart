import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Encapsule Firebase Authentication et l'identité utilisateur courante.
///
/// Le mot de passe n'est jamais transmis à l'API Videolog : seule la
/// connexion Firebase le reçoit. Les appels API utilisent ensuite un ID token
/// Firebase en `Authorization: Bearer`.
class AuthService extends ChangeNotifier {
  AuthService._() {
    FirebaseAuth.instance.authStateChanges().listen((_) => notifyListeners());
  }

  static final AuthService instance = AuthService._();

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

  /// Connexion email / mot de passe directement auprès de Firebase.
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() => _auth.signOut();

  /// Retourne l'ID token courant, en forçant son renouvellement si demandé.
  Future<String> requireIdToken({bool forceRefresh = false}) async {
    final current = _auth.currentUser;
    if (current == null) {
      throw const AuthException('Utilisateur Firebase non connecté.');
    }
    final token = await current.getIdToken(forceRefresh);
    if (token == null || token.isEmpty) {
      throw const AuthException('Impossible de récupérer le jeton Firebase.');
    }
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
