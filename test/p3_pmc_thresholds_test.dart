import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videolog_coach/core/account_controller.dart';
import 'package:videolog_coach/core/api_service.dart';
import 'package:videolog_coach/core/auth_service.dart';
import 'package:videolog_coach/data/pmc_models.dart';
import 'package:videolog_coach/presentation/screens/athlete_home_screen.dart';
import 'package:videolog_coach/presentation/widgets/thresholds_sheet.dart';

class _InMemoryStore implements SecureTokenStore {
  final Map<String, String> _data = {};

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;
}

class _FakeAuthService extends AuthService {
  _FakeAuthService()
    : super.forTesting(
        secureStore: _InMemoryStore(),
        tokenProvider: ({required bool forceRefresh}) async => 'jwt-test',
      );

  @override
  bool get isSignedIn => true;

  @override
  bool get isEmailVerified => true;

  @override
  String get uid => 'u-1';

  @override
  String? get email => 'athlete@videolog.app';

  @override
  String get displayName => 'Alice Martin';
}

Future<(AuthService, ApiService, AccountController)> _buildAuthenticatedHarness(
  Future<http.Response> Function(http.Request) handler,
) async {
  SharedPreferences.setMockInitialValues({});
  final auth = _FakeAuthService();

  final api = ApiService(
    authService: auth,
    baseUrl: 'https://api.videolog.app',
    httpClient: MockClient((req) async {
      if (req.url.path == '/v1/me') {
        return http.Response(
          jsonEncode({
            'uid': 'u-1',
            'email': 'athlete@videolog.app',
            'email_verified': true,
            'needs_onboarding': false,
            'user': {
              'uid': 'u-1',
              'email': 'athlete@videolog.app',
              'email_verified': true,
              'first_name': 'Alice',
              'last_name': 'Martin',
              'health_consent': {'granted': true},
              'athlete_profile': {
                'sport': 'cyclisme',
                'level': 'intermediaire',
                'hr_max': 190,
                'hr_rest': 50,
              },
            },
            'memberships': [
              {
                'org_id': 'org-1',
                'role': 'athlete',
                'organization': {'id': 'org-1', 'type': 'club', 'name': 'VC Lyon'},
              },
            ],
          }),
          200,
        );
      }
      return handler(req);
    }),
  );

  final account = AccountController.forTesting(
    authService: auth,
    apiService: api,
  );
  await account.refresh(syncAthleteProfile: false);
  return (auth, api, account);
}

void main() {
  group('P3 Models (PMC & Thresholds)', () {
    test('PmcResponse parse series, current, goals et todayOrLatest', () {
      final pmc = PmcResponse.fromJson({
        'series': [
          {'date': '2026-11-15', 'ctl': 58.2, 'atl': 66.0, 'tsb': -7.8},
          {
            'date': '2026-11-16',
            'ctl': 60.5,
            'atl': 63.0,
            'tsb': -2.5,
            'ramp_rate': 3.4,
          },
          {
            'date': '2026-11-17',
            'ctl': 61.0,
            'atl': 58.0,
            'tsb': 3.0,
            'projected': true,
          },
        ],
        'goals': [
          {
            'id': 'g-1',
            'title': 'Gran Fondo',
            'date': '2026-12-01',
            'priority': 'A',
            'sport': 'cyclisme',
          },
        ],
      });

      final today = pmc.todayOrLatest(DateTime(2026, 11, 16));
      expect(today, isNotNull);
      expect(today!.ctl, 60.5);
      expect(today.atl, 63.0);
      expect(today.tsb, -2.5);
      expect(today.rampRate, 3.4);
      expect(PmcResponse.tsbStatusLabel(today.tsb), 'Optimal');
      expect(pmc.series.last.projected, isTrue);
      expect(pmc.goals.single.title, 'Gran Fondo');
    });

    test('AthleteThreshold calcule les zones Coggan et Friel et parse plusieurs formats', () {
      final parsed = AthleteThreshold.parseList({
        'thresholds': [
          {
            'sport': 'cyclisme',
            'effective_from': '2026-11-16',
            'ftp_w': 265,
            'lthr_bpm': 172,
          },
        ],
      });

      expect(parsed, hasLength(1));
      final t = parsed.first;
      expect(t.sport, 'cyclisme');
      expect(t.ftpW, 265);
      expect(t.lthrBpm, 172);
      expect(t.effectivePowerZones, hasLength(7));
      expect(t.effectivePowerZones[3].code, 'Z4');
      expect(t.effectiveHrZones, hasLength(5));
      expect(t.effectiveHrZones[3].code, 'Z4');
    });
  });

  group('ApiService P3 routes (HTTP mock)', () {
    test('fetchPmc, fetchMyThresholds et updateAthleteThresholds appellent les bonnes routes', () async {
      final auth = AuthService.forTesting(
        secureStore: _InMemoryStore(),
        tokenProvider: ({required bool forceRefresh}) async => 'jwt-test',
      );

      Map<String, dynamic>? capturedPut;
      final api = ApiService(
        authService: auth,
        baseUrl: 'https://api.videolog.app',
        httpClient: MockClient((req) async {
          if (req.method == 'GET' && req.url.path == '/v1/orgs/org-1/analytics/pmc') {
            expect(req.url.queryParameters['uid'], 'u-1');
            expect(req.url.queryParameters['from'], '2026-10-17');
            expect(req.url.queryParameters['include_projected'], 'true');
            return http.Response(
              jsonEncode({
                'series': [
                  {'date': '2026-11-16', 'ctl': 64.0, 'atl': 60.0, 'tsb': 4.0},
                ],
                'goals': [],
              }),
              200,
            );
          }
          if (req.method == 'GET' && req.url.path == '/v1/me/thresholds') {
            return http.Response(
              jsonEncode([
                {'sport': 'cyclisme', 'ftp_w': 260, 'lthr_bpm': 170},
              ]),
              200,
            );
          }
          if (req.method == 'PUT' &&
              req.url.path == '/v1/orgs/org-1/athletes/u-1/thresholds') {
            capturedPut = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(jsonEncode(capturedPut), 200);
          }
          return http.Response('{}', 404);
        }),
      );

      final pmc = await api.fetchPmc('org-1', uid: 'u-1', from: '2026-10-17');
      expect(pmc.todayOrLatest(DateTime(2026, 11, 16))?.ctl, 64.0);

      final thresholds = await api.fetchMyThresholds();
      expect(thresholds.single.ftpW, 260);

      final updated = await api.updateAthleteThresholds(
        'org-1',
        'u-1',
        sport: 'cyclisme',
        effectiveFrom: '2026-11-16',
        ftpW: 265,
        lthrBpm: 172,
      );
      expect(updated.ftpW, 265);
      expect(capturedPut?['recalculate_activities'], isTrue);
      expect(capturedPut?['ftp_w'], 265);
      expect(capturedPut?['lthr_bpm'], 172);
    });
  });

  group('P3 Widgets (AthleteHomeScreen & ThresholdsSheet)', () {
    testWidgets('AthleteHomeScreen affiche forme du jour, profil RGPD, séance du jour et objectifs sans PMC', (tester) async {
      final fixedNow = DateTime(2026, 11, 16);
      final (_, api, account) = (await tester.runAsync(
        () => _buildAuthenticatedHarness((req) async {
          if (req.url.path == '/v1/orgs/org-1/calendar') {
            return http.Response(
              jsonEncode({
                'planned_workouts': [
                  {
                    'id': 'w-1',
                    'title': 'Tempo 2x20min',
                    'sport': 'cyclisme',
                    'date': '2026-11-16',
                    'estimated_duration_s': 3600,
                    'estimated_tss': 75,
                  },
                ],
                'activities': [],
                'goals': [
                  {
                    'id': 'g-1',
                    'title': 'Étape du Tour',
                    'date': '2026-12-01',
                    'priority': 'A',
                    'sport': 'cyclisme',
                  },
                ],
                'weekly_totals': [],
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      ))!;

      await tester.pumpWidget(
        MaterialApp(
          home: AthleteHomeScreen(
            apiService: api,
            accountController: account,
            now: fixedNow,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Forme du jour (10 s)'), findsOneWidget);
      expect(find.text('Profil sportif & RGPD'), findsOneWidget);
      expect(find.text('Consentement santé actif'), findsOneWidget);
      expect(find.textContaining('cyclisme'), findsWidgets);

      expect(find.text('Courbe de charge (30 j + projeté)'), findsNothing);
      expect(find.text('Fitness (CTL)'), findsNothing);
      expect(find.text('Fatigue (ATL)'), findsNothing);
      expect(find.text('Fraîcheur (TSB)'), findsNothing);
      expect(find.text('Seuils & Zones'), findsNothing);

      final listScrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Tempo 2x20min'),
        250,
        scrollable: listScrollable,
      );
      expect(find.text('Tempo 2x20min'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Étape du Tour'),
        250,
        scrollable: listScrollable,
      );
      expect(find.text('Étape du Tour'), findsOneWidget);
      expect(find.text('J-15'), findsOneWidget);
    });

    testWidgets('ThresholdsSheet charge /v1/me/thresholds, calcule les zones et envoie PUT', (tester) async {
      final auth = AuthService.forTesting(
        secureStore: _InMemoryStore(),
        tokenProvider: ({required bool forceRefresh}) async => 'jwt-test',
      );

      Map<String, dynamic>? sentBody;
      final api = ApiService(
        authService: auth,
        baseUrl: 'https://api.videolog.app',
        httpClient: MockClient((req) async {
          if (req.method == 'GET' && req.url.path == '/v1/me/thresholds') {
            return http.Response(
              jsonEncode([
                {'sport': 'cyclisme', 'ftp_w': 250, 'lthr_bpm': 168},
              ]),
              200,
            );
          }
          if (req.method == 'PUT' &&
              req.url.path == '/v1/orgs/org-1/athletes/u-1/thresholds') {
            sentBody = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(jsonEncode(sentBody), 200);
          }
          return http.Response('{}', 404);
        }),
      );

      AthleteThreshold? poppedResult;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  poppedResult = await showThresholdsSheet(
                    ctx,
                    orgId: 'org-1',
                    uid: 'u-1',
                    apiService: api,
                  );
                },
                child: const Text('Ouvrir seuils'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ouvrir seuils'));
      await tester.pumpAndSettle();

      expect(find.text('Zones de puissance (FTP)'), findsOneWidget);
      expect(find.text('Zones cardiaques (LTHR)'), findsOneWidget);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '270');
      await tester.enterText(fields.at(1), '174');
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Enregistrer les seuils'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Enregistrer les seuils'));
      await tester.pumpAndSettle();

      expect(sentBody, isNotNull);
      expect(sentBody!['sport'], 'cyclisme');
      expect(sentBody!['ftp_w'], 270);
      expect(sentBody!['lthr_bpm'], 174);
      expect(sentBody!['recalculate_activities'], isTrue);
      expect(poppedResult?.ftpW, 270);
    });
  });
}
