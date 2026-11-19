import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videolog_coach/core/api_service.dart';
import 'package:videolog_coach/core/auth_service.dart';
import 'package:videolog_coach/data/activity_models.dart';
import 'package:videolog_coach/presentation/screens/activity_detail_screen.dart';

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
  group('Activity models', () {
    test('parse ActivityDetail avec laps, video_assets et ActivityStreams orientés colonnes ou lignes', () {
      final detail = ActivityDetail.fromJson({
        'id': 'act-1',
        'title': 'Sortie Vercors',
        'sport': 'cyclisme',
        'started_at': '2026-11-16T08:30:00Z',
        'duration_s': 5400,
        'distance_m': 48500,
        'tss': 112,
        'normalized_power': 248,
        'intensity_factor': 0.86,
        'avg_hr': 154,
        'elevation_gain_m': 890,
        'planned_workout_id': 'w-1',
        'rpe': 7,
        'feeling': 4,
        'laps': [
          {'index': 1, 'name': 'Montée', 'duration_s': 1200, 'avg_power': 275, 'avg_hr': 168},
        ],
        'video_assets': [
          {'room_name': 'room-1', 'title': 'Caméra coach'},
        ],
      });

      expect(detail.summary.isMatched, isTrue);
      expect(detail.summary.normalizedPower, 248);
      expect(detail.laps, hasLength(1));
      expect(detail.videoAssets.single.roomName, 'room-1');

      final colStreams = ActivityStreams.fromJson({
        'time_s': [0, 5, 10],
        'hr': [120, 135, 148],
        'power': [180, 240, 260],
        'speed_kmh': [25.0, 30.5, 32.1],
      });
      expect(colStreams.points, hasLength(3));
      expect(colStreams.hasHr, isTrue);
      expect(colStreams.hasPower, isTrue);
      expect(colStreams.points[1].hr, 135);

      final rowStreams = ActivityStreams.fromJson({
        'points': [
          {'time_s': 0, 'hr': 118, 'altitude_m': 210},
          {'time_s': 5, 'hr': 124, 'altitude_m': 212},
        ],
      });
      expect(rowStreams.points, hasLength(2));
      expect(rowStreams.hasAltitude, isTrue);
      expect(rowStreams.points[1].altitudeM, 212);
    });
  });

  group('ApiService P2 routes & ActivityDetailScreen', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('fetchActivities, uploadActivityFile (409), feedback PATCH et comments', () async {
      final auth = AuthService.forTesting(
        secureStore: _InMemoryStore(),
        tokenProvider: ({required bool forceRefresh}) async => 'jwt-1',
      );
      var uploadCount = 0;
      final api = ApiService(
        authService: auth,
        httpClient: MockClient((req) async {
          if (req.method == 'GET' && req.url.path == '/v1/orgs/org-1/activities') {
            return http.Response(
              jsonEncode([
                {'id': 'act-1', 'title': 'Sortie 1', 'sport': 'cyclisme'},
              ]),
              200,
            );
          }
          if (req.method == 'POST' && req.url.path == '/v1/orgs/org-1/activities/upload') {
            uploadCount++;
            if (uploadCount == 1) {
              return http.Response(jsonEncode({'id': 'act-2'}), 201);
            }
            return http.Response(jsonEncode({'detail': 'Doublon FIT'}), 409);
          }
          if (req.method == 'PATCH' && req.url.path == '/v1/orgs/org-1/activities/act-1') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['rpe'], 8);
            expect(body['feeling'], 4);
            return http.Response(
              jsonEncode({'id': 'act-1', 'title': 'Sortie 1', 'rpe': 8, 'feeling': 4}),
              200,
            );
          }
          if (req.method == 'POST' && req.url.path == '/v1/orgs/org-1/activities/act-1/comments') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['body'], 'Bonne relance');
            return http.Response(
              jsonEncode({'id': 'c-1', 'body': 'Bonne relance', 'author_name': 'Coach'}),
              201,
            );
          }
          return http.Response('{}', 404);
        }),
      );

      final list = await api.fetchActivities('org-1');
      expect(list.single.id, 'act-1');

      final uploaded = await api.uploadActivityFile(
        'org-1',
        fileBytes: Uint8List.fromList([1, 2, 3]),
        filename: 'test.fit',
      );
      expect(uploaded['id'], 'act-2');

      await expectLater(
        () => api.uploadActivityFile(
          'org-1',
          fileBytes: Uint8List.fromList([1, 2, 3]),
          filename: 'test.fit',
        ),
        throwsA(isA<ApiException>().having((e) => e.isConflict, 'isConflict', isTrue)),
      );

      final patched = await api.updateActivityFeedback('org-1', 'act-1', rpe: 8, feeling: 4);
      expect(patched.rpe, 8);

      final comment = await api.postActivityComment('org-1', 'act-1', 'Bonne relance');
      expect(comment.body, 'Bonne relance');
    });

    testWidgets('ActivityDetailScreen affiche KPIs, courbe fl_chart, RPE et commentaires', (tester) async {
      final auth = AuthService.forTesting(
        secureStore: _InMemoryStore(),
        tokenProvider: ({required bool forceRefresh}) async => 'jwt-1',
      );
      final api = ApiService(
        authService: auth,
        httpClient: MockClient((req) async {
          if (req.url.path == '/v1/orgs/org-1/activities/act-1') {
            if (req.method == 'PATCH') {
              return http.Response(
                jsonEncode({'id': 'act-1', 'title': 'Intervalle PMA', 'rpe': 8, 'feeling': 4}),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'id': 'act-1',
                'title': 'Intervalle PMA',
                'sport': 'cyclisme',
                'duration_s': 3600,
                'distance_m': 35000,
                'tss': 95,
                'normalized_power': 260,
                'intensity_factor': 0.91,
                'avg_hr': 162,
                'elevation_gain_m': 420,
                'rpe': 8,
                'feeling': 4,
                'laps': [
                  {'index': 1, 'name': 'Bloc 1', 'duration_s': 300, 'avg_power': 310},
                ],
              }),
              200,
            );
          }
          if (req.url.path == '/v1/orgs/org-1/activities/act-1/streams') {
            expect(req.url.queryParameters['downsample'], '5');
            return http.Response(
              jsonEncode({
                'time_s': [0, 60, 120, 180],
                'hr': [130, 155, 170, 165],
                'power': [200, 310, 330, 290],
              }),
              200,
            );
          }
          if (req.url.path == '/v1/orgs/org-1/activities/act-1/comments') {
            if (req.method == 'POST') {
              return http.Response(
                jsonEncode({'id': 'c-2', 'body': 'Top !', 'author_name': 'Marc'}),
                201,
              );
            }
            return http.Response(
              jsonEncode([
                {'id': 'c-1', 'body': 'Bien géré', 'author_name': 'Coach'},
              ]),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ActivityDetailScreen(
            orgId: 'org-1',
            activityId: 'act-1',
            apiService: api,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Intervalle PMA'), findsOneWidget);
      expect(find.text('95'), findsOneWidget);
      expect(find.text('162 bpm'), findsOneWidget);
      expect(find.text('Courbes de séance'), findsOneWidget);

      final listScrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Bloc 1'),
        250,
        scrollable: listScrollable,
      );
      expect(find.text('Bloc 1'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Bien géré'),
        250,
        scrollable: listScrollable,
      );
      expect(find.text('Bien géré'), findsOneWidget);

      // Ajouter un commentaire
      await tester.scrollUntilVisible(
        find.text('Ajouter un commentaire'),
        250,
        scrollable: listScrollable,
      );
      await tester.enterText(find.byType(TextField), 'Top !');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Top !'), findsOneWidget);
    });
  });
}
