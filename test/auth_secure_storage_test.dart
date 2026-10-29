import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videolog_coach/core/auth_service.dart';

class _InMemorySecureTokenStore implements SecureTokenStore {
  final Map<String, String> _data = <String, String>{};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }
}

void main() {
  group('AuthService SecureTokenStore (Keystore / Keychain)', () {
    test(
      'migre un JWT et remember_me depuis SharedPreferences (clair) vers SecureTokenStore puis purge SharedPreferences',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'jwt': 'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.legacy.signature',
          'remember_me': false,
        });
        final prefs = await SharedPreferences.getInstance();
        final secureStore = _InMemorySecureTokenStore();
        final auth = AuthService.forTesting(secureStore: secureStore);

        await auth.migrateFromSharedPreferences(prefs);

        // Le JWT et remember_me sont désormais chiffrés dans SecureTokenStore
        expect(
          await auth.readSecureJwt(),
          'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.legacy.signature',
        );
        expect(await auth.getRememberMe(), isFalse);

        // Plus aucune trace en clair dans SharedPreferences
        expect(prefs.getString('jwt'), isNull);
        expect(prefs.containsKey('remember_me'), isFalse);
      },
    );

    test(
      'requireIdToken persiste le JWT dans SecureTokenStore et signOut l\'efface',
      () async {
        final secureStore = _InMemorySecureTokenStore();
        final auth = AuthService.forTesting(
          secureStore: secureStore,
          tokenProvider: ({required bool forceRefresh}) async =>
              forceRefresh ? 'fresh-jwt-token' : 'initial-jwt-token',
        );

        final token = await auth.requireIdToken();
        expect(token, 'initial-jwt-token');
        expect(await auth.readSecureJwt(), 'initial-jwt-token');

        final refreshed = await auth.requireIdToken(forceRefresh: true);
        expect(refreshed, 'fresh-jwt-token');
        expect(await auth.readSecureJwt(), 'fresh-jwt-token');

        await auth.signOut();
        expect(await auth.readSecureJwt(), isNull);
      },
    );
  });
}
