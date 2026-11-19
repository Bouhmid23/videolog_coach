import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videolog_coach/core/account_controller.dart';
import 'package:videolog_coach/core/api_service.dart';
import 'package:videolog_coach/core/auth_service.dart';
import 'package:videolog_coach/data/training_models.dart';
import 'package:videolog_coach/presentation/screens/calendar_screen.dart';
import 'package:videolog_coach/presentation/widgets/planned_workout_sheet.dart';
import 'package:videolog_coach/presentation/widgets/wellness_checkin_sheet.dart';

class _InMemoryStore implements SecureTokenStore {
  final Map<String, String> _data = {};

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;
}

class _FakeAuth extends AuthService {
  _FakeAuth()
    : super.forTesting(
        secureStore: _InMemoryStore(),
        tokenProvider: ({required bool forceRefresh}) async => 'jwt-1',
      );

  @override
  bool get isSignedIn => true;

  @override
  bool get isEmailVerified => true;

  @override
  String get uid => 'u-1';
}

void main() {
  group('Training models & RGPD wellness serialization', () {
    test('parse CalendarResponse complet avec blocks, steps, goals et totals', () {
      final cal = CalendarResponse.fromJson({
        'planned_workouts': [
          {
            'id': 'w-1',
            'title': 'Seuil 3x10min',
            'sport': 'cyclisme',
            'date': '2026-11-16',
            'start_time': '08:30',
            'coach_note': 'Bien s\'hydrater avant la séance',
            'estimated_duration_s': 4500,
            'estimated_tss': 78,
            'status': 'planned',
            'compliance': {'score': 92.5, 'color': 'green'},
            'blocks': [
              {'label': 'Échauffement', 'zone': 'Z2', 'duration_s': 900, 'intensity_pct': 60},
              {'label': 'Seuil', 'zone': 'Z4', 'duration_s': 1800, 'intensity_pct': 95},
            ],
            'steps': [
              {
                'name': 'Échauffement progressif',
                'duration_s': 900,
                'target_type': 'ftp_pct',
                'target_low': 55,
                'target_high': 65,
              },
              {
                'name': 'Bloc seuil',
                'duration_s': 600,
                'target_type': 'power',
                'target_low': 250,
                'target_high': 270,
              },
            ],
          },
        ],
        'activities': [
          {
            'id': 'act-1',
            'title': 'Sortie route',
            'sport': 'cyclisme',
            'started_at': '2026-11-16T08:00:00Z',
            'duration_s': 3600,
            'distance_m': 32000,
            'tss': 65,
          },
        ],
        'goals': [
          {
            'id': 'g-1',
            'title': 'Cyclosportive Mont Ventoux',
            'date': '2026-12-01',
            'priority': 'A',
          },
        ],
        'weekly_totals': [
          {
            'week_start': '2026-11-16',
            'duration_s': 10800,
            'distance_m': 95000,
            'tss': 195,
            'planned_tss': 240,
            'sessions_count': 4,
          },
        ],
      });

      expect(cal.plannedWorkouts, hasLength(1));
      final w = cal.plannedWorkouts.first;
      expect(w.startTime, '08:30');
      expect(w.coachNote, 'Bien s\'hydrater avant la séance');
      expect(w.blocks, hasLength(2));
      expect(w.steps, hasLength(2));
      expect(w.steps.first.displayTarget, '55–65 % FTP');
      expect(w.steps[1].displayTarget, '250–270 W');
      expect(w.compliance?.score, 92.5);
      expect(cal.workoutsForDay(DateTime(2026, 11, 16)), hasLength(1));
      expect(cal.activitiesForDay(DateTime(2026, 11, 16)), hasLength(1));
      expect(cal.goals.first.priority, 'A');
      expect(cal.weeklyTotals.first.plannedTss, 240);
    });

    test('WellnessEntry omet les champs santé quand healthConsent == false', () {
      const entry = WellnessEntry(
        date: '2026-11-16',
        sleepH: 7.5,
        sleepQuality: 4,
        fatigue: 2,
        soreness: 2,
        stress: 2,
        mood: 4,
        hrvMs: 72,
        restingHr: 46,
        weightKg: 70.2,
      );

      final withoutConsent = entry.toJson(includeHealthData: false);
      expect(withoutConsent.containsKey('hrv_ms'), isFalse);
      expect(withoutConsent.containsKey('resting_hr'), isFalse);
      expect(withoutConsent.containsKey('weight_kg'), isFalse);
      expect(withoutConsent['sleep_h'], 7.5);

      final withConsent = entry.toJson(includeHealthData: true);
      expect(withConsent['hrv_ms'], 72);
      expect(withConsent['resting_hr'], 46);
      expect(withConsent['weight_kg'], 70.2);
    });
  });

  group('ApiService P1 routes (HTTP mock)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('fetchCalendar et exportPlannedWorkout appellent les bonnes routes', () async {
      final auth = AuthService.forTesting(
        secureStore: _InMemoryStore(),
        tokenProvider: ({required bool forceRefresh}) async => 'jwt-1',
      );
      final api = ApiService(
        authService: auth,
        httpClient: MockClient((req) async {
          if (req.url.path == '/v1/orgs/org-1/calendar') {
            expect(req.url.queryParameters['from'], '2026-11-16');
            expect(req.url.queryParameters['to'], '2026-11-22');
            expect(req.url.queryParameters['uid'], 'u-1');
            return http.Response(
              jsonEncode({
                'planned_workouts': [
                  {
                    'id': 'w-1',
                    'title': 'Endurance Z2',
                    'date': '2026-11-16',
                    'estimated_duration_s': 3600,
                  },
                ],
                'activities': [],
                'goals': [],
                'weekly_totals': [],
              }),
              200,
            );
          }
          if (req.url.path == '/v1/orgs/org-1/workouts/planned/w-1/export') {
            expect(req.url.queryParameters['format'], 'zwo');
            return http.Response.bytes([60, 119, 111, 62], 200);
          }
          return http.Response('{}', 404);
        }),
      );

      final cal = await api.fetchCalendar(
        'org-1',
        from: '2026-11-16',
        to: '2026-11-22',
        uid: 'u-1',
      );
      expect(cal.plannedWorkouts.single.title, 'Endurance Z2');

      final zwo = await api.exportPlannedWorkout('org-1', 'w-1', format: 'zwo');
      expect(zwo, Uint8List.fromList([60, 119, 111, 62]));
    });

    testWidgets('WellnessCheckinSheet masque les métriques santé sans consentement et envoie le POST', (tester) async {
      Map<String, dynamic>? sentBody;
      final auth = AuthService.forTesting(
        secureStore: _InMemoryStore(),
        tokenProvider: ({required bool forceRefresh}) async => 'jwt-1',
      );
      final api = ApiService(
        authService: auth,
        httpClient: MockClient((req) async {
          expect(req.method, 'POST');
          expect(req.url.path, '/v1/orgs/org-1/wellness');
          expect(req.url.queryParameters['uid'], 'u-1');
          sentBody = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'ok': true}), 201);
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WellnessCheckinSheet(
              orgId: 'org-1',
              uid: 'u-1',
              hasHealthConsent: false,
              apiService: api,
            ),
          ),
        ),
      );

      expect(find.text('VFC (ms)'), findsNothing);
      expect(find.textContaining('consentement santé RGPD'), findsOneWidget);

      await tester.ensureVisible(find.text('Valider ma forme du jour'));
      await tester.tap(find.text('Valider ma forme du jour'));
      await tester.pumpAndSettle();

      expect(sentBody, isNotNull);
      expect(sentBody!.containsKey('hrv_ms'), isFalse);
      expect(sentBody!.containsKey('resting_hr'), isFalse);
      expect(sentBody!.containsKey('weight_kg'), isFalse);
      expect(sentBody!['sleep_quality'], 4);
    });

    testWidgets('PlannedWorkoutSheet affiche la barre d intensité, les étapes et exporte', (tester) async {
      String? sharedFile;
      final auth = AuthService.forTesting(
        secureStore: _InMemoryStore(),
        tokenProvider: ({required bool forceRefresh}) async => 'jwt-1',
      );
      final api = ApiService(
        authService: auth,
        httpClient: MockClient((req) async {
          if (req.url.path == '/v1/orgs/org-1/workouts/planned/w-1/comments') {
            return http.Response(jsonEncode({'items': []}), 200);
          }
          expect(req.url.path, '/v1/orgs/org-1/workouts/planned/w-1/export');
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );

      const workout = PlannedWorkout(
        id: 'w-1',
        title: 'PMA 30/30',
        sport: 'cyclisme',
        estimatedDurationS: 3600,
        estimatedTss: 82,
        blocks: [
          WorkoutBlock(label: 'Warmup', zone: 'Z2', durationS: 600, intensityPct: 60),
          WorkoutBlock(label: 'PMA', zone: 'Z5', durationS: 900, intensityPct: 115),
        ],
        steps: [
          WorkoutStep(
            name: '10x 30/30',
            durationS: 600,
            targetType: 'power',
            targetLow: 330,
            targetHigh: 360,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlannedWorkoutSheet(
              orgId: 'org-1',
              workout: workout,
              apiService: api,
              onShareFile: (filePath, title) async {
                sharedFile = filePath;
              },
            ),
          ),
        ),
      );

      expect(find.text('PMA 30/30'), findsOneWidget);
      expect(find.byType(WorkoutIntensityBar), findsOneWidget);
      expect(find.text('10x 30/30'), findsOneWidget);
      expect(find.textContaining('330–360 W'), findsOneWidget);

      await tester.ensureVisible(find.text('.FIT'));
      await tester.tap(find.text('.FIT'));
      await tester.pumpAndSettle();

      expect(sharedFile, 'pma_30_30.fit');
    });

    testWidgets('CalendarScreen simplifié affiche Séance du jour sans grille multi-semaines', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final auth = _FakeAuth();
      final fixedToday = DateTime(2026, 11, 17);

      final api = ApiService(
        authService: auth,
        baseUrl: 'https://api.videolog.app',
        httpClient: MockClient((req) async {
          if (req.url.path == '/v1/me') {
            return http.Response(
              jsonEncode({
                'uid': 'u-1',
                'email': 'a@b.c',
                'email_verified': true,
                'needs_onboarding': false,
                'user': {'uid': 'u-1', 'health_consent': {'granted': true}},
                'memberships': [
                  {
                    'org_id': 'org-1',
                    'role': 'athlete',
                    'organization': {'id': 'org-1', 'name': 'VC Lyon'},
                  },
                ],
              }),
              200,
            );
          }
          if (req.url.path == '/v1/orgs/org-1/calendar') {
            expect(req.url.queryParameters['from'], '2026-11-17');
            expect(req.url.queryParameters['to'], '2026-11-18');
            return http.Response(
              jsonEncode({
                'planned_workouts': [
                  {
                    'id': 'w-today',
                    'title': 'Fractionné 30/30',
                    'sport': 'cyclisme',
                    'date': '2026-11-17',
                    'start_time': '08:30',
                    'coach_note': 'Cadence 95 rpm sur les blocs',
                    'estimated_duration_s': 3600,
                    'estimated_tss': 75,
                    'steps': [
                      {
                        'name': 'Échauffement Z2',
                        'duration_s': 900,
                        'target_type': 'ftp_pct',
                        'target_low': 60,
                        'target_high': 70,
                      },
                    ],
                  },
                ],
                'activities': [],
                'goals': [],
                'weekly_totals': [],
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );

      final account = AccountController.forTesting(
        authService: auth,
        apiService: api,
      );
      await tester.runAsync(() => account.refresh(syncAthleteProfile: false));

      await tester.pumpWidget(
        MaterialApp(
          home: CalendarScreen(
            apiService: api,
            accountController: account,
            now: fixedToday,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SÉANCE DU JOUR'), findsOneWidget);
      expect(find.text('08:30'), findsOneWidget);
      expect(find.text('Fractionné 30/30'), findsOneWidget);
      expect(find.text('Cadence 95 rpm sur les blocs'), findsOneWidget);
      expect(find.text('Échauffement Z2'), findsOneWidget);
      expect(find.text('60–70 % FTP'), findsOneWidget);
      expect(find.text('Programme de la semaine'), findsNothing);
      expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    });
  });
}
