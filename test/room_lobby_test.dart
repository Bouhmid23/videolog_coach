import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videolog_coach/core/api_service.dart';
import 'package:videolog_coach/core/auth_service.dart';
import 'package:videolog_coach/data/room_lobby.dart';
import 'package:videolog_coach/presentation/widgets/room_lobby_card.dart';

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
  group('RoomLobby & LobbyParticipant models', () {
    test('parse lobby JSON, sorts connected/owner first and builds namesByUid', () {
      final lobby = RoomLobby.fromJson({
        'room_name': 'club-piste-42',
        'title': 'Séance VMA',
        'org_name': 'VC Lyon',
        'duration_s': 3600,
        'active_count': 2,
        'finished': false,
        'accessible': true,
        'reason': null,
        'invited_participants': [
          {
            'uid': 'uid-athlete-2',
            'name': 'Zoe Bernard',
            'is_owner': false,
            'connected': false,
          },
          {
            'uid': 'uid-athlete-1',
            'name': 'Alice Moreau',
            'is_owner': false,
            'connected': true,
          },
          {
            'uid': 'uid-coach-1',
            'name': 'Marc Martin',
            'is_owner': true,
            'connected': true,
          },
          {
            'uid': 'uid-raw-only',
            'name': 'uid-raw-only',
            'is_owner': false,
            'connected': false,
          },
        ],
      });

      expect(lobby.displayTitle, 'Séance VMA');
      expect(lobby.orgName, 'VC Lyon');
      expect(lobby.connectedCount, 2);
      expect(lobby.accessible, isTrue);

      // Ordre attendu : connectés (owner en premier), puis non connectés par nom.
      expect(
        lobby.invitedParticipants.map((p) => p.uid).toList(),
        ['uid-coach-1', 'uid-athlete-1', 'uid-raw-only', 'uid-athlete-2'],
      );
      expect(lobby.invitedParticipants.first.initials, 'MM');

      // namesByUid exclut les entrées dont name == uid brut.
      expect(lobby.namesByUid, {
        'uid-coach-1': 'Marc Martin',
        'uid-athlete-1': 'Alice Moreau',
        'uid-athlete-2': 'Zoe Bernard',
      });
    });
  });

  group('ApiService.fetchRoomLobby', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('calls GET /rooms/{room_name}/lobby and parses invited_participants', () async {
      final auth = AuthService.forTesting(
        secureStore: _InMemoryStore(),
        tokenProvider: ({required bool forceRefresh}) async => 'jwt-token',
      );
      Uri? capturedUri;
      final api = ApiService(
        authService: auth,
        baseUrl: 'http://127.0.0.1:8001',
        httpClient: MockClient((request) async {
          capturedUri = request.url;
          expect(request.method, 'GET');
          return http.Response(
            jsonEncode({
              'room_name': 'session-1',
              'title': 'Sortie seuil',
              'org_name': 'Club Athlé',
              'active_count': 1,
              'accessible': true,
              'invited_participants': [
                {
                  'uid': 'u-coach',
                  'name': 'Marc Martin',
                  'is_owner': true,
                  'connected': true,
                },
                {
                  'uid': 'u-ath',
                  'name': 'Alice Moreau',
                  'is_owner': false,
                  'connected': false,
                },
              ],
            }),
            200,
          );
        }),
      );

      final lobby = await api.fetchRoomLobby('session-1');

      expect(capturedUri?.path, '/rooms/session-1/lobby');
      expect(lobby.displayTitle, 'Sortie seuil');
      expect(lobby.orgName, 'Club Athlé');
      expect(lobby.invitedParticipants, hasLength(2));
      expect(lobby.invitedParticipants.first.name, 'Marc Martin');
      expect(lobby.invitedParticipants.first.connected, isTrue);
    });
  });

  group('RoomLobbyCard widget', () {
    testWidgets('displays connected/invited participants, badges and handles refresh', (
      tester,
    ) async {
      var refreshTapped = 0;
      const lobby = RoomLobby(
        roomName: 'session-1',
        title: 'Sortie seuil',
        orgName: 'Club Athlé',
        activeCount: 1,
        accessible: true,
        invitedParticipants: [
          LobbyParticipant(
            uid: 'u-coach',
            name: 'Marc Martin',
            isOwner: true,
            connected: true,
          ),
          LobbyParticipant(
            uid: 'u-me',
            name: 'Alice Moreau',
            isOwner: false,
            connected: false,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomLobbyCard(
              lobby: lobby,
              loading: false,
              currentUid: 'u-me',
              onRefresh: () => refreshTapped++,
            ),
          ),
        ),
      );

      expect(find.text('Participants de la séance'), findsOneWidget);
      expect(find.text('1/2 en ligne'), findsOneWidget);
      expect(find.text('Marc Martin'), findsOneWidget);
      expect(find.text('Alice Moreau (Vous)'), findsOneWidget);
      expect(find.text('Coach'), findsOneWidget);
      expect(find.text('En ligne'), findsOneWidget);
      expect(find.text('Invité'), findsOneWidget);

      await tester.tap(find.byTooltip('Actualiser les participants'));
      expect(refreshTapped, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('displays warning banner when session is not accessible', (
      tester,
    ) async {
      const lobby = RoomLobby(
        roomName: 'session-old',
        title: 'Ancienne séance',
        accessible: false,
        reason: 'Session terminée.',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RoomLobbyCard(
              lobby: lobby,
              loading: false,
            ),
          ),
        ),
      );

      expect(find.text('Session terminée.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
