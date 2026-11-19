import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videolog_coach/core/account_controller.dart';
import 'package:videolog_coach/core/api_service.dart';
import 'package:videolog_coach/core/auth_service.dart';
import 'package:videolog_coach/data/directory_models.dart';
import 'package:videolog_coach/presentation/screens/directory_screen.dart';
import 'package:videolog_coach/presentation/widgets/join_request_sheet.dart';
import 'package:videolog_coach/presentation/widgets/notifications_sheet.dart';

class _InMemoryStore implements SecureTokenStore {
  final Map<String, String> _data = {};

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<String?> write(String key, String value) async {
    _data[key] = value;
    return value;
  }
}

class _FakeAuthService extends AuthService {
  _FakeAuthService({this.verified = true})
    : super.forTesting(
        secureStore: _InMemoryStore(),
        tokenProvider: ({required bool forceRefresh}) async => 'jwt-test',
      );

  final bool verified;
  int verificationEmailsSent = 0;

  @override
  bool get isSignedIn => true;

  @override
  bool get isEmailVerified => verified;

  @override
  String get uid => 'u-athlete-1';

  @override
  String? get email => 'athlete@videolog.app';

  @override
  String get displayName => 'Alice Durand';

  @override
  Future<void> sendEmailVerification() async {
    verificationEmailsSent += 1;
  }
}

Map<String, dynamic> _sampleOrgJson({
  String id = 'org-1',
  String type = 'club',
  String name = 'VC Lyon Endurance',
  String? pendingRequestId,
  bool isMember = false,
  bool acceptingJoinRequests = true,
}) {
  return {
    'id': id,
    'type': type,
    'name': name,
    'description': 'Club route & home-trainer connecté à Lyon.',
    'city': 'Lyon',
    'country': 'FR',
    'logo_url': null,
    'accepting_join_requests': acceptingJoinRequests,
    'sports': ['cyclisme', 'home_trainer'],
    'has_indoor_sports': true,
    'sports_details': [
      {
        'code': 'home_trainer',
        'label': 'Home-trainer / Cyclisme indoor',
        'is_indoor': true,
        'category': 'ergo',
        'cadence_unit': 'rpm',
        'cadence_max': 120,
        'supports_power': true,
        'supports_gps': false,
        'supports_reps': false,
        'supports_pace_km': false,
        'supports_pace_500m': false,
        'supports_css': false,
        'levels': ['compétition régionale', 'élite'],
        'max_years_experience': 9,
        'groups': [
          {
            'id': 'grp-1',
            'name': 'Groupe Home-Trainer Hiver',
            'sport': 'home_trainer',
            'coach_uids': ['coach-uid-1'],
          },
        ],
        'coaches': [
          {
            'uid': 'coach-uid-1',
            'name': 'Marc Martin',
            'level': 'élite',
            'years_experience': 9,
          },
        ],
      },
    ],
    'coaches': [
      {
        'uid': 'coach-uid-1',
        'name': 'Marc Martin',
        'role': 'owner',
        'photo_url': null,
        'certifications': 'DEJEPS Cyclisme',
        'bio': 'Préparation puissance et contre-la-montre.',
        'sports': [
          {
            'code': 'home_trainer',
            'label': 'Home-trainer / Cyclisme indoor',
            'is_indoor': true,
            'category': 'ergo',
            'level': 'élite',
            'years_experience': 9,
          },
        ],
      },
    ],
    'groups': [
      {
        'id': 'grp-1',
        'name': 'Groupe Home-Trainer Hiver',
        'sport': 'home_trainer',
        'sport_label': 'Home-trainer / Cyclisme indoor',
        'is_indoor': true,
        'category': 'ergo',
        'coach_uids': ['coach-uid-1'],
      },
    ],
    'counts': {'athletes': 24, 'coaches': 2, 'groups': 3},
    'is_member': isMember,
    'my_role': isMember ? 'athlete' : null,
    'pending_request_id': pendingRequestId,
    'created_at': '2026-11-10T09:00:00+00:00',
  };
}

void main() {
  group('Directory & Join Request Models', () {
    test('SportMeta & OrgSportDetail parsent métriques, niveaux, groupes et coachs', () {
      final org = DirectoryOrganization.fromJson(_sampleOrgJson());
      expect(org.id, 'org-1');
      expect(org.isSoloCoach, isFalse);
      expect(org.hasIndoorSports, isTrue);
      expect(org.athletesCount, 24);
      expect(org.sportsDetails, hasLength(1));

      final sport = org.sportsDetails.first;
      expect(sport.code, 'home_trainer');
      expect(sport.isIndoor, isTrue);
      expect(sport.supportsPower, isTrue);
      expect(sport.supportedMetricLabels, contains('Puissance (W)'));
      expect(sport.supportedMetricLabels, contains('Cadence (rpm)'));
      expect(sport.levels, ['compétition régionale', 'élite']);
      expect(sport.maxYearsExperience, 9);
      expect(sport.groups.first.name, 'Groupe Home-Trainer Hiver');
      expect(sport.coaches.first.name, 'Marc Martin');
    });

    test('DirectoryOrganizationDetail parse organization et my_join_request', () {
      final detail = DirectoryOrganizationDetail.fromJson({
        'organization': _sampleOrgJson(pendingRequestId: 'req-1'),
        'my_join_request': {
          'id': 'req-1',
          'status': 'pending',
          'requested_sports': ['home_trainer'],
          'requested_group_id': 'grp-1',
          'target_coach_uid': 'coach-uid-1',
          'message': 'Bonjour, suivi home-trainer.',
          'created_at': '2026-11-19T10:30:00+00:00',
        },
      });

      expect(detail.organization.hasPendingRequest, isTrue);
      expect(detail.myJoinRequest, isNotNull);
      expect(detail.myJoinRequest!.orgId, 'org-1');
      expect(detail.myJoinRequest!.isPending, isTrue);
      expect(detail.myJoinRequest!.statusLabel, 'En attente');
    });
  });

  group('ApiService Directory & Join Request endpoints', () {
    test('fetchSports appelle GET /v1/sports sans en-tête Authorization', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({
            'sports': [
              {
                'code': 'aviron_indoor',
                'label': 'Aviron indoor',
                'is_indoor': true,
                'category': 'ergo',
                'cadence_unit': 'spm',
                'cadence_max': 45,
                'supports_power': true,
                'supports_pace_500m': true,
              },
            ],
            'count': 1,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiService(
        httpClient: client,
        authService: _FakeAuthService(),
        baseUrl: 'https://api.videolog.test',
      );

      final sports = await api.fetchSports(isIndoor: true, category: 'ergo');
      expect(captured.method, 'GET');
      expect(captured.url.path, '/v1/sports');
      expect(captured.url.queryParameters['is_indoor'], 'true');
      expect(captured.url.queryParameters['category'], 'ergo');
      expect(captured.headers.containsKey('Authorization'), isFalse);
      expect(sports, hasLength(1));
      expect(sports.first.supportedMetricLabels, contains('Allure /500m'));
    });

    test('searchDirectoryOrganizations transmet les filtres et la pagination', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({
            'organizations': [_sampleOrgJson()],
            'total': 25,
            'limit': 20,
            'offset': 0,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiService(
        httpClient: client,
        authService: _FakeAuthService(),
        baseUrl: 'https://api.videolog.test',
      );

      final page = await api.searchDirectoryOrganizations(
        type: 'club',
        sport: 'home_trainer',
        indoorOnly: true,
        city: 'Lyon',
        q: 'endurance',
        acceptingOnly: true,
      );

      expect(captured.url.path, '/v1/directory/organizations');
      expect(captured.headers['Authorization'], 'Bearer jwt-test');
      expect(captured.url.queryParameters['type'], 'club');
      expect(captured.url.queryParameters['sport'], 'home_trainer');
      expect(captured.url.queryParameters['indoor_only'], 'true');
      expect(captured.url.queryParameters['city'], 'Lyon');
      expect(captured.url.queryParameters['q'], 'endurance');
      expect(captured.url.queryParameters['accepting_only'], 'true');
      expect(page.hasMore, isTrue);
      expect(page.organizations, hasLength(1));
    });

    test('submitJoinRequest & cancelJoinRequest gèrent succès et 429', () async {
      var callCount = 0;
      final client = MockClient((req) async {
        callCount += 1;
        if (req.method == 'POST' && req.url.path == '/v1/orgs/org-1/join-requests') {
          if (callCount == 1) {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['requested_sports'], ['home_trainer']);
            expect(body['age_confirmed'], isTrue);
            return http.Response(
              jsonEncode({
                'join_request': {
                  'id': 'req-42',
                  'org_id': 'org-1',
                  'org_name': 'VC Lyon Endurance',
                  'org_type': 'club',
                  'requested_sports': ['home_trainer'],
                  'status': 'pending',
                },
              }),
              201,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({'detail': 'Trop de demandes cette heure.'}),
            429,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.method == 'DELETE' && req.url.path == '/v1/me/join-requests/req-42') {
          return http.Response(
            jsonEncode({'status': 'cancelled', 'id': 'req-42'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      });

      final api = ApiService(
        httpClient: client,
        authService: _FakeAuthService(),
        baseUrl: 'https://api.videolog.test',
      );

      final created = await api.submitJoinRequest(
        orgId: 'org-1',
        requestedSports: ['home_trainer'],
        message: 'Motivé !',
      );
      expect(created.id, 'req-42');
      expect(created.isPending, isTrue);

      await api.cancelJoinRequest('req-42');

      await expectLater(
        () => api.submitJoinRequest(orgId: 'org-1'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isTooManyRequests, 'isTooManyRequests', isTrue)
              .having((e) => e.message, 'message', 'Trop de demandes cette heure.'),
        ),
      );
    });
  });

  group('Directory & Join Request Widgets', () {
    testWidgets(
      'DirectoryScreen affiche les clubs, filtre, soumet puis annule une demande',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        String? pendingId;
        var cancelCalled = false;
        final requests = <Map<String, dynamic>>[];

        final auth = _FakeAuthService(verified: true);
        final client = MockClient((req) async {
          if (req.url.path == '/v1/me') {
            return http.Response(
              jsonEncode({
                'uid': 'u-athlete-1',
                'email': 'athlete@videolog.app',
                'email_verified': true,
                'needs_onboarding': true,
                'user': {
                  'first_name': 'Alice',
                  'last_name': 'Durand',
                  'athlete_profile': {
                    'sport': 'home_trainer',
                    'birth_date': '1998-05-10',
                  },
                },
                'memberships': [],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.url.path == '/v1/sports') {
            return http.Response(
              jsonEncode({
                'sports': [
                  {
                    'code': 'home_trainer',
                    'label': 'Home-trainer / Cyclisme indoor',
                    'is_indoor': true,
                    'category': 'ergo',
                    'cadence_unit': 'rpm',
                    'cadence_max': 120,
                    'supports_power': true,
                  },
                ],
                'count': 1,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.url.path == '/v1/directory/organizations') {
            return http.Response(
              jsonEncode({
                'organizations': [
                  _sampleOrgJson(pendingRequestId: pendingId),
                ],
                'total': 1,
                'limit': 20,
                'offset': 0,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.url.path == '/v1/directory/organizations/org-1') {
            return http.Response(
              jsonEncode({
                'organization': _sampleOrgJson(pendingRequestId: pendingId),
                'my_join_request': pendingId == null
                    ? null
                    : {
                        'id': pendingId,
                        'status': 'pending',
                        'requested_sports': ['home_trainer'],
                      },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.method == 'POST' &&
              req.url.path == '/v1/orgs/org-1/join-requests') {
            pendingId = 'req-new-1';
            final created = {
              'id': pendingId,
              'org_id': 'org-1',
              'org_name': 'VC Lyon Endurance',
              'org_type': 'club',
              'org_city': 'Lyon',
              'requested_sports': ['home_trainer'],
              'status': 'pending',
            };
            requests
              ..clear()
              ..add(created);
            return http.Response(
              jsonEncode({'join_request': created}),
              201,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.method == 'DELETE' &&
              req.url.path == '/v1/me/join-requests/req-new-1') {
            cancelCalled = true;
            pendingId = null;
            requests.clear();
            return http.Response(
              jsonEncode({'status': 'cancelled', 'id': 'req-new-1'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.url.path == '/v1/me/join-requests') {
            return http.Response(
              jsonEncode({'join_requests': requests, 'count': requests.length}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 200);
        });

        final api = ApiService(
          httpClient: client,
          authService: auth,
          baseUrl: 'https://api.videolog.test',
        );
        final account = AccountController.forTesting(
          authService: auth,
          apiService: api,
        );
        await account.refresh();

        await tester.pumpWidget(
          MaterialApp(
            home: DirectoryScreen(
              apiService: api,
              accountController: account,
              authService: auth,
              emailVerifiedOverride: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('VC Lyon Endurance'), findsOneWidget);
        expect(find.text('Home-trainer / Cyclisme indoor'), findsOneWidget);

        // Ouvre la fiche détaillée
        await tester.tap(find.text('VC Lyon Endurance'));
        await tester.pumpAndSettle();

        expect(find.text('Sports pratiqués & encadrés'), findsOneWidget);
        expect(find.text('Puissance (W)'), findsOneWidget);
        expect(find.text('Demander l\'adhésion'), findsOneWidget);

        await tester.scrollUntilVisible(
          find.text('DEJEPS Cyclisme'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('DEJEPS Cyclisme'), findsOneWidget);

        // Ouvre le BottomSheet et soumet la demande
        await tester.tap(find.text('Demander l\'adhésion'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Envoyer la demande d\'adhésion'));
        await tester.pumpAndSettle();

        // Passe immédiatement à l'état En attente -> bouton Annuler ma demande
        expect(find.text('Annuler ma demande'), findsOneWidget);

        // Annule la demande
        await tester.tap(find.text('Annuler ma demande'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Annuler la demande'));
        await tester.pumpAndSettle();

        expect(cancelCalled, isTrue);
        expect(find.text('Demander l\'adhésion'), findsOneWidget);
      },
    );

    testWidgets(
      'JoinRequestSheet affiche le bandeau de vérification e-mail sur 403',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final auth = _FakeAuthService(verified: false);
        final client = MockClient((req) async {
          if (req.url.path == '/v1/me') {
            return http.Response(
              jsonEncode({
                'uid': 'u-athlete-1',
                'email': 'athlete@videolog.app',
                'email_verified': false,
                'needs_onboarding': true,
                'user': {
                  'first_name': 'Alice',
                  'last_name': 'Durand',
                  'athlete_profile': {'birth_date': '1998-05-10'},
                },
                'memberships': [],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.method == 'POST') {
            return http.Response(
              jsonEncode({
                'detail': 'Veuillez vérifier votre adresse e-mail avant de demander une adhésion.',
              }),
              403,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 200);
        });

        final api = ApiService(
          httpClient: client,
          authService: auth,
          baseUrl: 'https://api.videolog.test',
        );
        final account = AccountController.forTesting(
          authService: auth,
          apiService: api,
        );
        await account.refresh();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: JoinRequestSheet(
                organization: DirectoryOrganization.fromJson(_sampleOrgJson()),
                apiService: api,
                accountController: account,
                authService: auth,
                emailVerifiedOverride: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Vérification d\'e-mail requise'), findsOneWidget);
        await tester.tap(find.text('Renvoyer l\'e-mail de vérification'));
        await tester.pumpAndSettle();
        expect(auth.verificationEmailsSent, 1);
      },
    );

    testWidgets(
      'NotificationsSheet rafraîchit /v1/me et sélectionne l org sur join_request_approved',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        var meCalls = 0;
        final auth = _FakeAuthService();
        final client = MockClient((req) async {
          if (req.url.path == '/v1/me') {
            meCalls += 1;
            return http.Response(
              jsonEncode({
                'uid': 'u-athlete-1',
                'email': 'athlete@videolog.app',
                'email_verified': true,
                'needs_onboarding': meCalls == 1,
                'memberships': meCalls == 1
                    ? []
                    : [
                        {
                          'org_id': 'org-1',
                          'role': 'athlete',
                          'organization': {
                            'id': 'org-1',
                            'type': 'club',
                            'name': 'VC Lyon Endurance',
                          },
                        },
                      ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.url.path == '/v1/me/notifications') {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': 'n-1',
                    'type': 'join_request_approved',
                    'title': 'Demande acceptée',
                    'body': 'Bienvenue au VC Lyon !',
                    'org_id': 'org-1',
                    'read': false,
                  },
                ],
                'unread_count': 1,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.method == 'POST' &&
              req.url.path == '/v1/me/notifications/n-1/read') {
            return http.Response(
              jsonEncode({'ok': true}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 200);
        });

        final api = ApiService(
          httpClient: client,
          authService: auth,
          baseUrl: 'https://api.videolog.test',
        );
        final account = AccountController.forTesting(
          authService: auth,
          apiService: api,
        );
        await account.refresh();
        expect(account.memberships, isEmpty);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NotificationsSheet(
                apiService: api,
                accountController: account,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Demande acceptée'));
        await tester.pumpAndSettle();

        expect(meCalls, greaterThanOrEqualTo(2));
        expect(account.activeOrgId, 'org-1');
      },
    );

    testWidgets(
      'DirectoryScreen ne déborde pas en hauteur réduite et ferme le dialogue Ville sans erreur de controller',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        String? lastCityQuery;
        final auth = _FakeAuthService();
        final client = MockClient((req) async {
          if (req.url.path == '/v1/me') {
            return http.Response(
              jsonEncode({
                'uid': 'u-athlete-1',
                'email': 'athlete@videolog.app',
                'email_verified': true,
                'needs_onboarding': true,
                'memberships': [],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.url.path == '/v1/sports') {
            return http.Response(
              jsonEncode({'sports': [], 'count': 0}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.url.path == '/v1/directory/organizations') {
            lastCityQuery = req.url.queryParameters['city'];
            return http.Response(
              jsonEncode({
                'organizations': [_sampleOrgJson()],
                'total': 1,
                'limit': 20,
                'offset': 0,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.url.path == '/v1/me/join-requests') {
            return http.Response(
              jsonEncode({'join_requests': [], 'count': 0}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 200);
        });

        final api = ApiService(
          httpClient: client,
          authService: auth,
          baseUrl: 'https://api.videolog.test',
        );
        final account = AccountController.forTesting(
          authService: auth,
          apiService: api,
        );
        await account.refresh();

        // Simule un écran paysage avec clavier virtuel ouvert (hauteur très réduite)
        tester.view.physicalSize = const Size(1006, 290);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: DirectoryScreen(
              apiService: api,
              accountController: account,
              authService: auth,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Ouvre le filtre Ville, saisit "Lyon" et ferme le dialogue pendant la transition
        await tester.tap(find.text('Ville'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Ville'),
          'Lyon',
        );
        await tester.tap(find.text('Appliquer'));
        // Pump plusieurs frames pendant l'animation de fermeture du dialogue
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        expect(lastCityQuery, 'Lyon');
        expect(tester.takeException(), isNull);
      },
    );
  });
}
