import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videolog_coach/core/api_service.dart';
import 'package:videolog_coach/core/auth_service.dart';
import 'package:videolog_coach/core/recording_controller.dart';

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

    test(
      'ApiService rafraîchit le JWT sur 401 et réessaie une fois avant de réussir',
      () async {
        final secureStore = _InMemorySecureTokenStore();
        final forceRefreshCalls = <bool>[];
        final auth = AuthService.forTesting(
          secureStore: secureStore,
          tokenProvider: ({required bool forceRefresh}) async {
            forceRefreshCalls.add(forceRefresh);
            return forceRefresh ? 'fresh-token' : 'expired-token';
          },
        );

        final receivedAuthHeaders = <String?>[];
        final mockClient = MockClient((request) async {
          receivedAuthHeaders.add(request.headers['Authorization']);
          if (receivedAuthHeaders.length == 1) {
            return http.Response(
              jsonEncode({'detail': 'Token expired'}),
              401,
            );
          }
          return http.Response(
            jsonEncode({
              'rooms': [
                {'name': 'coaching-room', 'num_participants': 2},
              ],
            }),
            200,
          );
        });

        final api = ApiService(httpClient: mockClient, authService: auth);
        final rooms = await api.fetchRooms();

        expect(rooms.single.name, 'coaching-room');
        expect(forceRefreshCalls, equals(<bool>[false, true]));
        expect(
          receivedAuthHeaders,
          equals(<String?>['Bearer expired-token', 'Bearer fresh-token']),
        );
      },
    );

    test(
      'RecordingController injectable pilote load / start / stop via ApiService mocké',
      () async {
        final secureStore = _InMemorySecureTokenStore();
        final auth = AuthService.forTesting(
          secureStore: secureStore,
          tokenProvider: ({required bool forceRefresh}) async => 'valid-token',
        );

        final mockClient = MockClient((request) async {
          if (request.url.path.endsWith('/recording/start')) {
            return http.Response(
              jsonEncode({'status': 'recording', 'egress_id': 'EG_123'}),
              200,
            );
          }
          if (request.url.path.endsWith('/recording/stop')) {
            return http.Response(
              jsonEncode({'status': 'stopped', 'egress_id': 'EG_123'}),
              200,
            );
          }
          return http.Response(jsonEncode({'status': 'not_started'}), 200);
        });

        final api = ApiService(httpClient: mockClient, authService: auth);
        final controller = RecordingController(
          roomName: 'room-1',
          canControl: true,
          pollInterval: const Duration(hours: 1),
          apiService: api,
          authService: auth,
        );
        addTearDown(controller.dispose);

        await controller.load();
        expect(controller.canStart, isTrue);

        final started = await controller.start();
        expect(started, isTrue);
        expect(controller.isRecording, isTrue);

        final stopped = await controller.stop();
        expect(stopped, isTrue);
        expect(controller.isRecording, isFalse);
      },
    );
  });
}
