import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videolog_coach/core/account_controller.dart';
import 'package:videolog_coach/core/api_service.dart';
import 'package:videolog_coach/core/auth_service.dart';
import 'package:videolog_coach/data/account_models.dart';
import 'package:videolog_coach/data/athlete_profile.dart';
import 'package:videolog_coach/data/mobile_room.dart';
import 'package:videolog_coach/data/session_models.dart';

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
  group('AccountMe & OrgMembership', () {
    test('parse /v1/me avec organisation et droits par rôle', () {
      final me = AccountMe.fromJson({
        'uid': 'uid-coach-1',
        'email': 'coach@videolog.app',
        'email_verified': true,
        'platform_admin': false,
        'needs_onboarding': false,
        'user': {
          'uid': 'uid-coach-1',
          'email': 'coach@videolog.app',
          'email_verified': true,
          'first_name': 'Marc',
          'last_name': 'Dupont',
          'athlete_profile': {
            'sport': 'cyclisme',
            'level': 'compétition régionale',
            'birth_date': '1995-05-14',
            'height_cm': 178,
            'weight_kg': 72.5,
            'hr_max': 188,
            'hr_rest': 48,
          },
          'health_consent': {
            'granted': true,
            'version': '2026-11-v1',
            'granted_at': '2026-11-01T10:00:00+00:00',
          },
        },
        'memberships': [
          {
            'org_id': 'org-1',
            'role': 'coach',
            'group_ids': ['g-1'],
            'organization': {
              'id': 'org-1',
              'type': 'club',
              'name': 'VC Lyon',
              'sports': ['cyclisme'],
            },
          },
          {
            'org_id': 'org-2',
            'role': 'athlete',
            'group_ids': [],
            'organization': {
              'id': 'org-2',
              'type': 'club',
              'name': 'Tri Club',
            },
          },
        ],
      });

      expect(me.needsOnboarding, isFalse);
      expect(me.user?.fullName, 'Marc Dupont');
      expect(me.memberships, hasLength(2));
      expect(me.memberships[0].canManageSessions, isTrue);
      expect(me.memberships[0].canManageMarkers, isTrue);
      expect(me.memberships[1].isAthlete, isTrue);
      expect(me.memberships[1].canManageSessions, isFalse);
      expect(me.memberships[1].canManageMarkers, isFalse);
    });

    test('extrait correctement un token depuis un lien, deep link ou code brut', () {
      expect(
        AccountController.extractInviteToken(
          'https://app.videolog.app/invite/tok_abc123',
        ),
        'tok_abc123',
      );
      expect(
        AccountController.extractInviteToken('videolog://invite/tok_dl_1'),
        'tok_dl_1',
      );
      expect(
        AccountController.extractInviteToken('videolog://app/invite/tok_dl_2'),
        'tok_dl_2',
      );
      expect(
        AccountController.extractInviteToken('/invite?token=tok_query_3'),
        'tok_query_3',
      );
      expect(AccountController.extractInviteToken('tok_xyz789'), 'tok_xyz789');
      expect(AccountController.extractInviteToken('   '), isNull);
    });

    test('AuthService gère les erreurs et annulations Google Sign-In', () {
      const canceled = GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      );
      const misconfigured = GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
      );
      expect(AuthService.isCancellation(canceled), isTrue);
      expect(AuthService.isCancellation(misconfigured), isFalse);
      expect(AuthService.messageFor(canceled), contains('annulée'));
      expect(AuthService.messageFor(misconfigured), contains('SHA-1'));
    });
  });

  group('AthleteProfile validation 15 ans & RGPD', () {
    test('refuse un âge inférieur à 15 ans', () {
      final now = DateTime.now();
      final tooYoung = DateTime(now.year - 14, now.month, now.day);
      final err = AthleteProfile.validateForServer(
        sport: 'cyclisme',
        level: 'loisir',
        birthDate: tooYoung,
        healthConsentGranted: false,
      );
      expect(err, contains('15 ans'));
    });

    test('refuse des données de santé sans consentement RGPD explicite', () {
      final err = AthleteProfile.validateForServer(
        sport: 'cyclisme',
        level: 'loisir',
        birthDate: DateTime(2000, 1, 1),
        weightKg: 70.0,
        hrMax: 190,
        hrRest: 50,
        healthConsentGranted: false,
      );
      expect(err, contains('consentement'));
    });

    test('refuse hr_rest >= hr_max', () {
      final err = AthleteProfile.validateForServer(
        sport: 'cyclisme',
        level: 'loisir',
        birthDate: DateTime(2000, 1, 1),
        hrMax: 100,
        hrRest: 110,
        healthConsentGranted: true,
      );
      expect(err, contains('inférieure'));
    });

    test('fromServer purge les métriques santé quand consentement révoqué', () {
      final merged = AthleteProfile.fromServer(
        serverProfile: ServerAthleteProfile(
          sport: 'triathlon',
          level: 'nationale',
          birthDate: DateTime(1998, 4, 10),
          heightCm: 180,
          weightKg: 74,
          hrMax: 192,
          hrRest: 45,
        ),
        healthConsent: const HealthConsent(granted: false),
        fallback: const AthleteProfile(
          weightKg: 74,
          customMaxHeartRate: 192,
          hrRest: 45,
          healthConsentGranted: true,
        ),
      );

      expect(merged.healthConsentGranted, isFalse);
      expect(merged.customMaxHeartRate, isNull);
      expect(merged.hrRest, isNull);
      expect(merged.sport, 'triathlon');
      expect(merged.heightCm, 180);
    });
  });

  group('MobileRoom & Session models', () {
    test('parse title et org_id dans MobileRoom', () {
      final room = MobileRoom.fromJson({
        'room_name': 'vc-lyon-20261113-a1b2c3',
        'title': 'Sortie seuil',
        'org_id': 'org-1',
        'count': 1,
        'recording': false,
        'recording_status': 'not_started',
        'can_control_recording': true,
      });

      expect(room.displayTitle, 'Sortie seuil');
      expect(room.orgId, 'org-1');
    });

    test('parse SessionDetail, télémétrie, alertes et marqueurs', () {
      final detail = SessionDetail.fromJson({
        'room_name': 'vc-lyon-20261113-a1b2c3',
        'title': 'Fractionné',
        'org_id': 'org-1',
        'finished': true,
        'participants': [
          {
            'uid': 'u1',
            'identity': 'u1',
            'display_name': 'Alice Martin',
            'role': 'athlete',
          },
        ],
        'recordings': [
          {
            'egress_id': 'EG_1',
            'status': 'EGRESS_COMPLETE',
            'mp4_url': 'https://minio.videolog.app/recordings/test.mp4',
            'duration_s': 120.5,
          },
        ],
      });

      expect(detail.displayTitle, 'Fractionné');
      expect(detail.participants.single.displayName, 'Alice Martin');
      expect(detail.recordings.single.hasPlayableUrl, isTrue);

      final sample = SessionTelemetrySample.fromJson({
        'pts_ms': 12500.0,
        'server_ts': 1700000000.0,
        'participant': 'u1',
        'speed': 34.2,
        'heart_rate': 168,
        'cadence': 92,
      });
      expect(sample.speed, 34.2);
      expect(sample.heartRate, 168);

      final alert = SessionAlert.fromJson({
        'id': 'a1',
        'type': 'hr_high',
        'value': 195,
        'threshold': 188,
        'participant': 'u1',
        'pts_ms': 25000,
        'message': 'FC élevée',
        'ts': 1700000025.0,
      });
      expect(alert.threshold, 188);

      final marker = SessionMarker.fromJson({
        'id': 'm1',
        'room_name': 'vc-lyon-20261113-a1b2c3',
        'org_id': 'org-1',
        'pts_ms': 12500,
        'label': 'Relance côte',
        'category': 'technique',
        'author_name': 'Marc Dupont',
      });
      expect(marker.label, 'Relance côte');
      expect(marker.ptsMs, 12500);
    });
  });

  group('ApiService routes v1 (HTTP mock)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('remonte le message serveur 422 sur PUT /v1/me/athlete-profile', () async {
      final auth = AuthService.forTesting(
        secureStore: _InMemoryStore(),
        tokenProvider: ({required bool forceRefresh}) async => 'jwt-token',
      );
      final api = ApiService(
        authService: auth,
        httpClient: MockClient((req) async {
          expect(req.method, 'PUT');
          expect(req.url.path, '/v1/me/athlete-profile');
          expect(req.headers['Authorization'], 'Bearer jwt-token');
          return http.Response(
            jsonEncode({
              'detail':
                  'L\'accès à la plateforme est interdit aux personnes de moins de 15 ans.',
            }),
            422,
          );
        }),
      );

      await expectLater(
        () => api.updateAthleteProfile(
          sport: 'cyclisme',
          level: 'loisir',
          birthDateIso: '2015-01-01',
          healthConsent: false,
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having((e) => e.message, 'message', contains('15 ans')),
        ),
      );
    });

    test('crée et liste les marqueurs coach sur /v1/orgs/{id}/sessions/{room}/markers', () async {
      final auth = AuthService.forTesting(
        secureStore: _InMemoryStore(),
        tokenProvider: ({required bool forceRefresh}) async => 'jwt-coach',
      );
      final api = ApiService(
        authService: auth,
        httpClient: MockClient((req) async {
          if (req.method == 'POST' &&
              req.url.path == '/v1/orgs/org-1/sessions/room-a/markers') {
            return http.Response(
              jsonEncode({
                'id': 'm-1',
                'room_name': 'room-a',
                'org_id': 'org-1',
                'pts_ms': 12500,
                'label': 'Sprint',
                'category': 'technique',
              }),
              201,
            );
          }
          if (req.method == 'GET' &&
              req.url.path == '/v1/orgs/org-1/sessions/room-a/markers') {
            return http.Response(
              jsonEncode([
                {
                  'id': 'm-1',
                  'room_name': 'room-a',
                  'org_id': 'org-1',
                  'pts_ms': 12500,
                  'label': 'Sprint',
                  'category': 'technique',
                },
              ]),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );

      final created = await api.createSessionMarker(
        'org-1',
        'room-a',
        ptsMs: 12500,
        label: 'Sprint',
      );
      expect(created.id, 'm-1');

      final list = await api.fetchSessionMarkers('org-1', 'room-a');
      expect(list, hasLength(1));
      expect(list.first.label, 'Sprint');
    });

    test('getBytes télécharge un export binaire et réessaie sur 401', () async {
      var calls = 0;
      final auth = AuthService.forTesting(
        secureStore: _InMemoryStore(),
        tokenProvider: ({required bool forceRefresh}) async =>
            forceRefresh ? 'jwt-fresh' : 'jwt-old',
      );
      final api = ApiService(
        authService: auth,
        httpClient: MockClient((req) async {
          calls++;
          expect(req.url.path, '/v1/orgs/org-1/workouts/planned/w-1/export');
          expect(req.url.queryParameters['format'], 'fit');
          if (calls == 1) {
            expect(req.headers['Authorization'], 'Bearer jwt-old');
            return http.Response('{"detail":"expired"}', 401);
          }
          expect(req.headers['Authorization'], 'Bearer jwt-fresh');
          return http.Response.bytes([1, 2, 3, 4], 200);
        }),
      );

      final bytes = await api.getBytes(
        '/v1/orgs/org-1/workouts/planned/w-1/export',
        query: {'format': 'fit'},
      );
      expect(calls, 2);
      expect(bytes, Uint8List.fromList([1, 2, 3, 4]));
    });

    test('postMultipart envoie le fichier et propage 409 doublon', () async {
      final auth = AuthService.forTesting(
        secureStore: _InMemoryStore(),
        tokenProvider: ({required bool forceRefresh}) async => 'jwt-athlete',
      );
      var attempt = 0;
      final api = ApiService(
        authService: auth,
        httpClient: MockClient((req) async {
          attempt++;
          expect(req.method, 'POST');
          expect(req.url.path, '/v1/orgs/org-1/activities/upload');
          expect(req.headers['Authorization'], 'Bearer jwt-athlete');
          if (attempt == 1) {
            return http.Response(
              jsonEncode({'id': 'act-1', 'matched_workout_id': 'w-1'}),
              201,
            );
          }
          return http.Response(
            jsonEncode({'detail': 'Activité déjà importée.'}),
            409,
          );
        }),
      );

      final created = await api.postMultipart(
        '/v1/orgs/org-1/activities/upload',
        fileBytes: Uint8List.fromList([10, 20, 30]),
        filename: 'sortie.fit',
        fields: {'title': 'Sortie club'},
      );
      expect(created['id'], 'act-1');
      expect(created['matched_workout_id'], 'w-1');

      await expectLater(
        () => api.postMultipart(
          '/v1/orgs/org-1/activities/upload',
          fileBytes: Uint8List.fromList([10, 20, 30]),
          filename: 'sortie.fit',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isConflict, 'isConflict', isTrue)
              .having((e) => e.message, 'message', contains('déjà importée')),
        ),
      );
    });
  });
}
