import 'dart:convert';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videolog_coach/app_config.dart';
import 'package:videolog_coach/core/api_service.dart';
import 'package:videolog_coach/core/auth_service.dart';

class _InMemoryStore implements SecureTokenStore {
  final Map<String, String> _data = {};

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;
}

void main() {
  group('AppConfig', () {
    test('résout correctement local et prod selon APP_ENV et release mode', () {
      expect(AppConfig.resolveEnvironment('local'), AppEnvironment.local);
      expect(AppConfig.resolveEnvironment('DEV'), AppEnvironment.local);
      expect(AppConfig.resolveEnvironment('prod'), AppEnvironment.prod);
      expect(AppConfig.resolveEnvironment('production'), AppEnvironment.prod);
      expect(
        AppConfig.resolveEnvironment(''),
        AppConfig.defaultEnvironment,
      );
      expect(
        AppConfig.resolveEnvironment('', isReleaseMode: true),
        AppEnvironment.prod,
      );
      expect(
        AppConfig.resolveEnvironment('local', isReleaseMode: true),
        AppEnvironment.local,
      );
    });

    test('résout les URLs API par environnement et plateforme', () {
      expect(
        AppConfig.resolveApiBaseUrl(
          environment: AppEnvironment.prod,
          platform: TargetPlatform.android,
        ),
        'https://api.videolog.app',
      );
      expect(
        AppConfig.resolveApiBaseUrl(
          environment: AppEnvironment.local,
          platform: TargetPlatform.android,
        ),
        AppConfig.localAndroidApiBaseUrl,
      );
      expect(
        AppConfig.resolveApiBaseUrl(
          environment: AppEnvironment.local,
          platform: TargetPlatform.iOS,
        ),
        AppConfig.localIosApiBaseUrl,
      );
      expect(
        AppConfig.resolveApiBaseUrl(
          environment: AppEnvironment.local,
          platform: TargetPlatform.android,
          overrideUrl: 'http://192.168.1.42:8000///',
        ),
        'http://192.168.1.42:8000',
      );
    });
  });

  group('ApiService LiveKit token scheme', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('accepte ws:// en mode local', () async {
      final auth = AuthService.forTesting(
        secureStore: _InMemoryStore(),
        tokenProvider: ({required bool forceRefresh}) async => 'jwt-local',
      );
      final api = ApiService(
        authService: auth,
        baseUrl: 'http://10.0.2.2:8000',
        allowInsecureLiveKit: true,
        httpClient: MockClient((req) async {
          expect(req.url.toString(), 'http://10.0.2.2:8000/token');
          return http.Response(
            jsonEncode({
              'token': 'lk-jwt',
              'url': 'ws://10.0.2.2:7880',
              'room': 'test-room',
            }),
            200,
          );
        }),
      );

      final lk = await api.fetchLiveKitToken('test-room');
      final expectedUrl = AppConfig.isLocal &&
              AppConfig.localLiveKitUrlOverride.isNotEmpty
          ? AppConfig.localLiveKitUrlOverride
          : 'ws://10.0.2.2:7880';
      expect(lk.url, expectedUrl);
      expect(lk.token, 'lk-jwt');
    });

    test('refuse ws:// en mode prod', () async {
      final auth = AuthService.forTesting(
        secureStore: _InMemoryStore(),
        tokenProvider: ({required bool forceRefresh}) async => 'jwt-prod',
      );
      final api = ApiService(
        authService: auth,
        baseUrl: 'https://api.videolog.app',
        allowInsecureLiveKit: false,
        httpClient: MockClient((req) async {
          expect(req.url.toString(), 'https://api.videolog.app/token');
          return http.Response(
            jsonEncode({
              'token': 'lk-jwt',
              'url': 'ws://api.videolog.app:7880',
              'room': 'test-room',
            }),
            200,
          );
        }),
      );

      await expectLater(
        () => api.fetchLiveKitToken('test-room'),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
