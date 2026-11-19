import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videolog_coach/core/account_controller.dart';
import 'package:videolog_coach/core/api_service.dart';
import 'package:videolog_coach/core/auth_service.dart';
import 'package:videolog_coach/data/account_models.dart';
import 'package:videolog_coach/data/activity_models.dart';
import 'package:videolog_coach/data/training_models.dart';
import 'package:videolog_coach/presentation/screens/activity_detail_screen.dart';
import 'package:videolog_coach/presentation/screens/athlete_home_screen.dart';
import 'package:videolog_coach/presentation/widgets/notifications_sheet.dart';
import 'package:videolog_coach/presentation/widgets/planned_workout_sheet.dart';

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
  String get uid => 'u-athlete-1';

  @override
  String? get email => 'athlete@videolog.app';

  @override
  String get displayName => 'Alice Martin';
}

Future<(AuthService, ApiService, AccountController)> _buildMultiOrgAccount(
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
            'uid': 'u-athlete-1',
            'email': 'athlete@videolog.app',
            'email_verified': true,
            'needs_onboarding': false,
            'user': {
              'uid': 'u-athlete-1',
              'first_name': 'Alice',
              'last_name': 'Martin',
              'health_consent': {'granted': true},
            },
            'memberships': [
              {
                'org_id': 'org-1',
                'role': 'athlete',
                'organization': {'id': 'org-1', 'type': 'club', 'name': 'VC Lyon'},
              },
              {
                'org_id': 'org-2',
                'role': 'athlete',
                'organization': {'id': 'org-2', 'type': 'club', 'name': 'Team Alpes'},
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
  group('Lot 2 Models (Notifications, Sharing & PlannedWorkout expiry)', () {
    test('NotificationsResponse parse items et unread_count', () {
      final resp = NotificationsResponse.fromJson({
        'unread_count': 1,
        'items': [
          {
            'id': 'n-1',
            'type': 'activity_comment',
            'title': 'Nouveau commentaire',
            'body': 'Coach Jean : Bien joué !',
            'link': '/app/activities/act-42',
            'org_id': 'org-1',
            'read': false,
            'created_at': '2026-11-17T10:15:00Z',
          },
          {
            'id': 'n-2',
            'type': 'workout_comment',
            'title': 'Message séance',
            'body': 'Pense au capteur cardio',
            'link': '/app/calendar',
            'org_id': 'org-2',
            'read': true,
          },
        ],
      });

      expect(resp.unreadCount, 1);
      expect(resp.items, hasLength(2));
      expect(resp.items.first.type, 'activity_comment');
      expect(resp.items.first.read, isFalse);
      expect(resp.items.first.copyWith(read: true).read, isTrue);
    });

    test('ActivitySummary parse org_id, uid et shared_org_ids', () {
      final s = ActivitySummary.fromJson({
        'id': 'act-1',
        'title': 'Sortie col',
        'org_id': 'org-1',
        'uid': 'u-athlete-1',
        'shared_org_ids': ['org-2', 'org-3'],
      });

      expect(s.orgId, 'org-1');
      expect(s.uid, 'u-athlete-1');
      expect(s.sharedOrgIds, ['org-2', 'org-3']);
    });

    test('PlannedWorkout.isExpiredAt détecte les séances passées et actives', () {
      final pastDay = PlannedWorkout(
        id: 'w-past',
        title: 'Hier',
        date: DateTime(2026, 11, 16),
      );
      final futureDay = PlannedWorkout(
        id: 'w-future',
        title: 'Demain',
        date: DateTime(2026, 11, 18),
      );
      final todayEnded = PlannedWorkout(
        id: 'w-ended',
        title: 'Matin fini',
        date: DateTime(2026, 11, 17),
        startTime: '08:00',
        estimatedDurationS: 3600,
      );
      final todayOngoing = PlannedWorkout(
        id: 'w-ongoing',
        title: 'Soir à venir',
        date: DateTime(2026, 11, 17),
        startTime: '18:00',
        estimatedDurationS: 3600,
      );

      final now = DateTime.utc(2026, 11, 17, 12, 0);
      expect(pastDay.isExpiredAt(now), isTrue);
      expect(futureDay.isExpiredAt(now), isFalse);
      expect(todayEnded.isExpiredAt(now), isTrue);
      expect(todayOngoing.isExpiredAt(now), isFalse);
    });
  });

  group('ApiService Lot 2 routes (HTTP mock)', () {
    test('notifications, planned workout comments (wrapped + 400) et sharing PATCH', () async {
      final auth = _FakeAuthService();
      var markedAll = false;
      var markedOne = false;
      List<dynamic>? sentSharedOrgs;

      final api = ApiService(
        authService: auth,
        baseUrl: 'https://api.videolog.app',
        httpClient: MockClient((req) async {
          if (req.method == 'GET' && req.url.path == '/v1/me/notifications') {
            return http.Response(
              jsonEncode({
                'unread_count': 1,
                'items': [
                  {'id': 'n-1', 'title': 'Alerte', 'read': false},
                ],
              }),
              200,
            );
          }
          if (req.method == 'POST' &&
              req.url.path == '/v1/me/notifications/read-all') {
            markedAll = true;
            return http.Response(jsonEncode({'ok': true}), 200);
          }
          if (req.method == 'POST' &&
              req.url.path == '/v1/me/notifications/n-1/read') {
            markedOne = true;
            return http.Response(jsonEncode({'ok': true}), 200);
          }
          if (req.method == 'GET' &&
              req.url.path == '/v1/orgs/org-1/workouts/planned/w-1/comments') {
            return http.Response(
              jsonEncode({
                'items': [
                  {'id': 'c-1', 'body': 'Prêt ?', 'author_name': 'Coach'},
                ],
              }),
              200,
            );
          }
          if (req.method == 'POST' &&
              req.url.path == '/v1/orgs/org-1/workouts/planned/w-1/comments') {
            return http.Response(
              jsonEncode({
                'comment': {
                  'id': 'c-2',
                  'body': 'Oui prêt !',
                  'author_name': 'Alice',
                },
              }),
              201,
            );
          }
          if (req.method == 'POST' &&
              req.url.path == '/v1/orgs/org-1/workouts/planned/w-old/comments') {
            return http.Response(
              jsonEncode({
                'detail': 'Impossible d\'envoyer un message sur une séance déjà passée.',
              }),
              400,
            );
          }
          if (req.method == 'PATCH' &&
              req.url.path == '/v1/orgs/org-1/activities/act-1/sharing') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            sentSharedOrgs = body['shared_org_ids'] as List<dynamic>;
            return http.Response(
              jsonEncode({
                'activity': {
                  'id': 'act-1',
                  'title': 'Sortie test',
                  'org_id': 'org-1',
                  'shared_org_ids': sentSharedOrgs,
                },
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );

      final notifs = await api.fetchNotifications();
      expect(notifs.unreadCount, 1);
      expect(notifs.items.single.id, 'n-1');

      await api.markNotificationRead('n-1');
      await api.markAllNotificationsRead();
      expect(markedOne, isTrue);
      expect(markedAll, isTrue);

      final comments = await api.fetchPlannedWorkoutComments('org-1', 'w-1');
      expect(comments.single.body, 'Prêt ?');

      final posted = await api.postPlannedWorkoutComment('org-1', 'w-1', 'Oui prêt !');
      expect(posted.body, 'Oui prêt !');

      await expectLater(
        () => api.postPlannedWorkoutComment('org-1', 'w-old', 'Trop tard'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );

      final updated = await api.updateActivitySharing('org-1', 'act-1', ['org-2']);
      expect(sentSharedOrgs, ['org-2']);
      expect(updated.sharedOrgIds, ['org-2']);
    });
  });

  group('Lot 2 Widgets', () {
    testWidgets('NotificationsSheet affiche la liste, marque une notif et Tout lire', (tester) async {
      final auth = _FakeAuthService();
      var unreadReported = -1;
      var markedAll = false;
      var markedOne = false;
      AppNotification? tappedNotif;

      final api = ApiService(
        authService: auth,
        baseUrl: 'https://api.videolog.app',
        httpClient: MockClient((req) async {
          if (req.method == 'GET' && req.url.path == '/v1/me/notifications') {
            return http.Response(
              jsonEncode({
                'unread_count': 2,
                'items': [
                  {
                    'id': 'n-1',
                    'type': 'activity_comment',
                    'title': 'Nouveau commentaire activité',
                    'body': 'Super séance',
                    'link': '/app/activities/act-1',
                    'org_id': 'org-1',
                    'read': false,
                  },
                  {
                    'id': 'n-2',
                    'type': 'workout_comment',
                    'title': 'Message séance du jour',
                    'body': 'Hydrate-toi bien',
                    'link': '/app/calendar',
                    'org_id': 'org-1',
                    'read': false,
                  },
                ],
              }),
              200,
            );
          }
          if (req.method == 'POST' && req.url.path == '/v1/me/notifications/n-1/read') {
            markedOne = true;
            return http.Response('{}', 200);
          }
          if (req.method == 'POST' && req.url.path == '/v1/me/notifications/read-all') {
            markedAll = true;
            return http.Response('{}', 200);
          }
          return http.Response('{}', 404);
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotificationsSheet(
              apiService: api,
              onUnreadCountChanged: (c) => unreadReported = c,
              onNotificationTap: (n) => tappedNotif = n,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(unreadReported, 2);
      expect(find.text('Nouveau commentaire activité'), findsOneWidget);
      expect(find.text('Message séance du jour'), findsOneWidget);

      await tester.tap(find.text('Nouveau commentaire activité'));
      await tester.pumpAndSettle();
      expect(markedOne, isTrue);
      expect(unreadReported, 1);
      expect(tappedNotif?.id, 'n-1');

      await tester.tap(find.text('Tout lire'));
      await tester.pumpAndSettle();
      expect(markedAll, isTrue);
      expect(unreadReported, 0);
    });

    testWidgets('PlannedWorkoutSheet gère la discussion active et la lecture seule sur séance passée', (tester) async {
      final auth = _FakeAuthService();
      final api = ApiService(
        authService: auth,
        baseUrl: 'https://api.videolog.app',
        httpClient: MockClient((req) async {
          if (req.method == 'GET' &&
              req.url.path.endsWith('/comments')) {
            return http.Response(
              jsonEncode({
                'items': [
                  {'id': 'c-1', 'body': 'Objectif Z2', 'author_name': 'Coach'},
                ],
              }),
              200,
            );
          }
          if (req.method == 'POST' &&
              req.url.path == '/v1/orgs/org-1/workouts/planned/w-active/comments') {
            return http.Response(
              jsonEncode({
                'comment': {
                  'id': 'c-2',
                  'body': 'Compris coach',
                  'author_name': 'Alice',
                },
              }),
              201,
            );
          }
          return http.Response('{}', 404);
        }),
      );

      final activeWorkout = PlannedWorkout(
        id: 'w-active',
        title: 'Sortie Endurance',
        sport: 'cyclisme',
        date: DateTime(2026, 11, 18),
        estimatedDurationS: 3600,
        estimatedTss: 82,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlannedWorkoutSheet(
              orgId: 'org-1',
              workout: activeWorkout,
              apiService: api,
              now: DateTime(2026, 11, 17, 10, 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Effort estimé'), findsOneWidget);
      expect(find.text('82 pts'), findsOneWidget);
      expect(find.text('Objectif Z2'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Message au coach'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), 'Compris coach');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Compris coach'), findsOneWidget);

      // Séance passée -> lecture seule
      final pastWorkout = PlannedWorkout(
        id: 'w-past',
        title: 'Séance d hier',
        sport: 'cyclisme',
        date: DateTime(2026, 11, 16),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlannedWorkoutSheet(
              orgId: 'org-1',
              workout: pastWorkout,
              apiService: api,
              now: DateTime(2026, 11, 17, 10, 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Séance passée : discussion en lecture seule'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('ActivityDetailScreen affiche Partage multi-clubs et envoie PATCH /sharing', (tester) async {
      List<dynamic>? sentSharedOrgIds;
      final (_, api, account) = (await tester.runAsync(
        () => _buildMultiOrgAccount((req) async {
          if (req.method == 'GET' && req.url.path == '/v1/orgs/org-1/activities/act-1') {
            return http.Response(
              jsonEncode({
                'id': 'act-1',
                'title': 'Sortie Monts d Or',
                'org_id': 'org-1',
                'uid': 'u-athlete-1',
                'sport': 'cyclisme',
                'duration_s': 3600,
                'tss': 90,
                'shared_org_ids': [],
              }),
              200,
            );
          }
          if (req.method == 'GET' && req.url.path == '/v1/orgs/org-1/activities/act-1/streams') {
            return http.Response(jsonEncode({'time_s': []}), 200);
          }
          if (req.method == 'GET' && req.url.path == '/v1/orgs/org-1/activities/act-1/comments') {
            return http.Response(jsonEncode([]), 200);
          }
          if (req.method == 'PATCH' && req.url.path == '/v1/orgs/org-1/activities/act-1/sharing') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            sentSharedOrgIds = body['shared_org_ids'] as List<dynamic>;
            return http.Response(
              jsonEncode({
                'activity': {
                  'id': 'act-1',
                  'title': 'Sortie Monts d Or',
                  'org_id': 'org-1',
                  'uid': 'u-athlete-1',
                  'shared_org_ids': sentSharedOrgIds,
                },
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      ))!;

      await tester.pumpWidget(
        MaterialApp(
          home: ActivityDetailScreen(
            orgId: 'org-1',
            activityId: 'act-1',
            apiService: api,
            accountController: account,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pts d\'effort'), findsOneWidget);

      final listScrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Enregistrer le partage'),
        250,
        scrollable: listScrollable,
      );
      await tester.ensureVisible(find.text('Team Alpes'));
      await tester.pumpAndSettle();
      expect(find.text('Partage multi-clubs'), findsOneWidget);
      expect(find.text('Team Alpes'), findsOneWidget);

      await tester.tap(find.text('Team Alpes'));
      await tester.pump();
      await tester.ensureVisible(find.text('Enregistrer le partage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer le partage'));
      await tester.pumpAndSettle();

      expect(sentSharedOrgIds, ['org-2']);
    });

    testWidgets('AthleteHomeScreen affiche le badge de notifications non lues et pts d effort', (tester) async {
      final fixedNow = DateTime(2026, 11, 17);
      final (_, api, account) = (await tester.runAsync(
        () => _buildMultiOrgAccount((req) async {
          if (req.url.path == '/v1/orgs/org-1/calendar') {
            return http.Response(
              jsonEncode({
                'planned_workouts': [
                  {
                    'id': 'w-1',
                    'title': 'Endurance active',
                    'sport': 'cyclisme',
                    'date': '2026-11-17',
                    'estimated_duration_s': 3600,
                    'estimated_tss': 68,
                  },
                ],
                'activities': [],
                'goals': [],
                'weekly_totals': [],
              }),
              200,
            );
          }
          if (req.url.path == '/v1/me/notifications') {
            return http.Response(
              jsonEncode({
                'unread_count': 3,
                'items': [],
              }),
              200,
            );
          }
          if (req.url.path == '/v1/me/invitations') {
            return http.Response(jsonEncode({'invitations': []}), 200);
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

      expect(find.text('3'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Endurance active'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('68 pts d\'effort'), findsOneWidget);
    });
  });
}
