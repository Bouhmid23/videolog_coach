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
import 'package:videolog_coach/presentation/widgets/organization_hub_sheet.dart';
import 'package:videolog_coach/presentation/widgets/pending_invitations_card.dart';

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

void main() {
  group('Lot 1 Models (Coaches & InAppInvitation)', () {
    test('OrgMembership parse coaches et coach_profile depuis /v1/me', () {
      final me = AccountMe.fromJson({
        'uid': 'u-athlete-1',
        'email': 'athlete@videolog.app',
        'memberships': [
          {
            'org_id': 'org-1',
            'role': 'athlete',
            'organization': {
              'id': 'org-1',
              'type': 'club',
              'name': 'VC Lyon',
              'city': 'Lyon',
            },
            'coaches': [
              {
                'uid': 'u-coach-1',
                'name': 'Jean Dupont',
                'role': 'coach',
                'coach_profile': {
                  'sports': [
                    {
                      'sport': 'cyclisme',
                      'level': 'élite',
                      'years_experience': 8,
                    },
                  ],
                  'certifications': 'DEJEPS Cyclisme',
                  'bio': 'Spécialiste contre-la-montre et endurance.',
                },
              },
            ],
          },
        ],
      });

      expect(me.memberships, hasLength(1));
      final coaches = me.memberships.first.coaches;
      expect(coaches, hasLength(1));
      expect(coaches.first.name, 'Jean Dupont');
      expect(coaches.first.coachProfile?.certifications, 'DEJEPS Cyclisme');
      expect(coaches.first.coachProfile?.sports.single.sport, 'cyclisme');
      expect(coaches.first.coachProfile?.sports.single.yearsExperience, 8);
    });

    test('InAppInvitation parse les champs de /v1/me/invitations', () {
      final inv = InAppInvitation.fromJson({
        'id': 'inv-1',
        'org_id': 'org-2',
        'org_name': 'Coach Claire',
        'org_type': 'solo_coach',
        'role': 'athlete',
        'inviter_name': 'Claire Bernard',
        'status': 'pending',
      });

      expect(inv.id, 'inv-1');
      expect(inv.orgName, 'Coach Claire');
      expect(inv.isSoloCoach, isTrue);
      expect(inv.orgTypeLabel, 'Coach privé');
      expect(inv.roleLabel, 'Athlète');
      expect(inv.inviterName, 'Claire Bernard');
    });
  });

  group('Lot 1 ApiService routes', () {
    test('fetchLiveKitToken propage 410 Gone et 404 avec detail serveur', () async {
      final auth = _FakeAuthService();
      var attempt = 0;
      final api = ApiService(
        authService: auth,
        baseUrl: 'https://api.videolog.app',
        httpClient: MockClient((req) async {
          attempt++;
          if (req.url.path == '/token' && attempt == 1) {
            return http.Response(
              jsonEncode({
                'detail':
                    'L\'horaire de cette session est dépassé et aucun participant n\'est connecté.',
              }),
              410,
            );
          }
          return http.Response(
            jsonEncode({'detail': 'Session terminée.'}),
            404,
          );
        }),
      );

      await expectLater(
        () => api.fetchLiveKitToken('room-expired'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isGone, 'isGone', isTrue)
              .having((e) => e.detail, 'detail', contains('dépassé')),
        ),
      );

      await expectLater(
        () => api.fetchLiveKitToken('room-ended'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isNotFound, 'isNotFound', isTrue)
              .having((e) => e.detail, 'detail', 'Session terminée.'),
        ),
      );
    });

    test('fetchMyInvitations, accept/decline et leaveOrganization appellent les bonnes routes', () async {
      final auth = _FakeAuthService();
      final calls = <String>[];
      final api = ApiService(
        authService: auth,
        baseUrl: 'https://api.videolog.app',
        httpClient: MockClient((req) async {
          calls.add('${req.method} ${req.url.path}');
          if (req.method == 'GET' && req.url.path == '/v1/me/invitations') {
            return http.Response(
              jsonEncode({
                'invitations': [
                  {
                    'id': 'inv-42',
                    'org_id': 'org-2',
                    'org_name': 'Club Alpes',
                    'org_type': 'club',
                    'role': 'athlete',
                  },
                ],
              }),
              200,
            );
          }
          if (req.method == 'POST' &&
              req.url.path == '/v1/me/invitations/inv-42/accept') {
            return http.Response(
              jsonEncode({'status': 'accepted', 'org_id': 'org-2', 'role': 'athlete'}),
              200,
            );
          }
          if (req.method == 'POST' &&
              req.url.path == '/v1/me/invitations/inv-99/decline') {
            return http.Response(
              jsonEncode({'status': 'declined', 'id': 'inv-99'}),
              200,
            );
          }
          if (req.method == 'DELETE' &&
              req.url.path == '/v1/orgs/org-1/members/me') {
            return http.Response(
              jsonEncode({'status': 'removed', 'org_id': 'org-1'}),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );

      final invs = await api.fetchMyInvitations();
      expect(invs.single.id, 'inv-42');
      await api.acceptMyInvitation('inv-42');
      await api.declineMyInvitation('inv-99');
      await api.leaveOrganization('org-1');

      expect(calls, [
        'GET /v1/me/invitations',
        'POST /v1/me/invitations/inv-42/accept',
        'POST /v1/me/invitations/inv-99/decline',
        'DELETE /v1/orgs/org-1/members/me',
      ]);
    });
  });

  group('Lot 1 Widgets (PendingInvitationsCard & OrganizationHubSheet)', () {
    testWidgets('PendingInvitationsCard accepte et refuse une invitation en 1 clic', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final auth = _FakeAuthService();
      var acceptedCalled = false;
      var declinedCalled = false;

      final api = ApiService(
        authService: auth,
        baseUrl: 'https://api.videolog.app',
        httpClient: MockClient((req) async {
          if (req.method == 'POST' &&
              req.url.path == '/v1/me/invitations/inv-1/accept') {
            acceptedCalled = true;
            return http.Response(
              jsonEncode({'status': 'accepted', 'org_id': 'org-2'}),
              200,
            );
          }
          if (req.method == 'POST' &&
              req.url.path == '/v1/me/invitations/inv-2/decline') {
            declinedCalled = true;
            return http.Response(
              jsonEncode({'status': 'declined', 'id': 'inv-2'}),
              200,
            );
          }
          if (req.url.path == '/v1/me') {
            return http.Response(
              jsonEncode({
                'uid': 'u-athlete-1',
                'email': 'athlete@videolog.app',
                'memberships': [
                  {
                    'org_id': 'org-2',
                    'role': 'athlete',
                    'organization': {'id': 'org-2', 'type': 'club', 'name': 'Club B'},
                  },
                ],
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

      final handled = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PendingInvitationsCard(
              apiService: api,
              accountController: account,
              invitations: const [
                InAppInvitation(
                  id: 'inv-1',
                  orgId: 'org-2',
                  orgName: 'Club B',
                  orgType: 'club',
                  role: 'athlete',
                  inviterName: 'Coach Léa',
                ),
                InAppInvitation(
                  id: 'inv-2',
                  orgId: 'org-3',
                  orgName: 'Coach Solo',
                  orgType: 'solo_coach',
                  role: 'athlete',
                ),
              ],
              onInvitationHandled: ({required accepted, required invitation}) async {
                handled.add('${invitation.id}:$accepted');
              },
            ),
          ),
        ),
      );

      expect(find.text('2 invitations reçues'), findsOneWidget);
      expect(find.text('Club B'), findsOneWidget);
      expect(find.text('Invité par Coach Léa'), findsOneWidget);

      await tester.tap(find.text('Accepter').first);
      await tester.pumpAndSettle();
      expect(acceptedCalled, isTrue);
      expect(account.activeOrgId, 'org-2');

      await tester.tap(find.text('Refuser').last);
      await tester.pumpAndSettle();
      expect(declinedCalled, isTrue);
      expect(handled, ['inv-1:true', 'inv-2:false']);
    });

    testWidgets('OrganizationHubSheet affiche la fiche coach et permet de quitter un club', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final auth = _FakeAuthService();
      var leftOrg = false;

      final api = ApiService(
        authService: auth,
        baseUrl: 'https://api.videolog.app',
        httpClient: MockClient((req) async {
          if (req.url.path == '/v1/me') {
            return http.Response(
              jsonEncode({
                'uid': 'u-athlete-1',
                'email': 'athlete@videolog.app',
                'memberships': leftOrg
                    ? []
                    : [
                        {
                          'org_id': 'org-1',
                          'role': 'athlete',
                          'organization': {
                            'id': 'org-1',
                            'type': 'club',
                            'name': 'VC Lyon',
                            'city': 'Lyon',
                          },
                          'coaches': [
                            {
                              'uid': 'u-coach-1',
                              'name': 'Jean Dupont',
                              'role': 'coach',
                              'coach_profile': {
                                'sports': [
                                  {
                                    'sport': 'cyclisme',
                                    'level': 'élite',
                                    'years_experience': 8,
                                  },
                                ],
                                'certifications': 'DEJEPS Cyclisme',
                                'bio': 'Coach endurance.',
                              },
                            },
                          ],
                        },
                      ],
              }),
              200,
            );
          }
          if (req.url.path == '/v1/me/invitations') {
            return http.Response(jsonEncode({'invitations': []}), 200);
          }
          if (req.method == 'DELETE' &&
              req.url.path == '/v1/orgs/org-1/members/me') {
            leftOrg = true;
            return http.Response(jsonEncode({'status': 'removed'}), 200);
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
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showOrganizationHubSheet(
                  ctx,
                  apiService: api,
                  accountController: account,
                ),
                child: const Text('Ouvrir clubs'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Ouvrir clubs'));
      await tester.pumpAndSettle();

      expect(find.text('VC Lyon'), findsOneWidget);
      expect(find.text('Jean Dupont'), findsOneWidget);

      // Ouvrir la fiche coach
      await tester.tap(find.text('Jean Dupont'));
      await tester.pumpAndSettle();
      expect(find.text('DEJEPS Cyclisme'), findsOneWidget);
      expect(find.text('Coach endurance.'), findsOneWidget);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();

      // Quitter le club avec confirmation
      await tester.tap(find.text('Quitter ce club'));
      await tester.pumpAndSettle();
      expect(find.text('Quitter VC Lyon ?'), findsOneWidget);
      await tester.tap(find.text('Quitter'));
      await tester.pumpAndSettle();

      expect(leftOrg, isTrue);
      expect(account.memberships, isEmpty);
    });
  });
}
