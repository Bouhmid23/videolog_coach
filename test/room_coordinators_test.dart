import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:videolog_coach/data/ball_marker.dart';
import 'package:videolog_coach/data/remote_telemetry.dart';
import 'package:videolog_coach/viewmodels/marker_controller.dart';
import 'package:videolog_coach/viewmodels/room/participant_track_manager.dart';
import 'package:videolog_coach/viewmodels/room/room_telemetry_coordinator.dart';

Position _pos({
  required double lat,
  required double lng,
  double accuracy = 5.0,
  double speed = 3.0,
  double heading = 90.0,
  required DateTime timestamp,
}) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: timestamp,
    accuracy: accuracy,
    altitude: 100.0,
    altitudeAccuracy: 3.0,
    heading: heading,
    headingAccuracy: 5.0,
    speed: speed,
    speedAccuracy: 0.5,
  );
}

void main() {
  group('MarkerController (C2.3)', () {
    test('ajoute, remplace par id, plafonne à maxMarkers (5) et expire selon le TTL', () async {
      final controller = MarkerController();
      expect(controller.isEmpty, isTrue);

      // Ajout de 6 marqueurs -> seuls les 5 plus récents sont conservés
      for (int i = 1; i <= 6; i++) {
        controller.add(
          BallMarker(
            id: 'm$i',
            x: 0.1 * i,
            y: 0.1 * i,
            ttl: const Duration(seconds: 5),
            receivedAt: DateTime.now(),
          ),
        );
      }
      expect(controller.markers.length, equals(MarkerController.maxMarkers));
      expect(controller.markers.first.id, equals('m2'));
      expect(controller.markers.last.id, equals('m6'));

      // Mise à jour d'un marqueur existant (même id 'm3')
      controller.add(
        BallMarker(
          id: 'm3',
          x: 0.99,
          y: 0.88,
          ttl: const Duration(seconds: 5),
          receivedAt: DateTime.now(),
        ),
      );
      expect(controller.markers.length, equals(5));
      expect(controller.markers.last.id, equals('m3'));
      expect(controller.markers.last.x, closeTo(0.99, 1e-6));

      // Expiration automatique via TTL court
      controller.clear();
      expect(controller.isEmpty, isTrue);

      controller.add(
        BallMarker(
          id: 'short',
          x: 0.5,
          y: 0.5,
          ttl: const Duration(milliseconds: 40),
          receivedAt: DateTime.now(),
        ),
      );
      expect(controller.markers.length, equals(1));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(controller.isEmpty, isTrue);

      controller.dispose();
    });
  });

  group('ParticipantTrackManager (C2.1)', () {
    test('gère la sélection de participant, le side-sheet, la visibilité posture et les notifiers de télémétrie', () {
      int stateChangeCount = 0;
      final manager = ParticipantTrackManager(
        onStateChanged: () => stateChangeCount++,
      );

      expect(manager.showPosePip, isTrue);
      expect(manager.showPosture, isFalse);
      expect(manager.showSideSheet, isFalse);
      expect(manager.selectedParticipantIdentity, isNull);

      // Toggle PiP
      manager.togglePosePip();
      expect(manager.showPosePip, isFalse);
      expect(stateChangeCount, equals(1));

      // Sélection d'un participant -> ouvre le side-sheet
      manager.selectParticipant('athlete-1');
      expect(manager.selectedParticipantIdentity, equals('athlete-1'));
      expect(manager.showSideSheet, isTrue);

      // Re-sélection du même participant -> bascule (ferme) le side-sheet
      manager.selectParticipant('athlete-1');
      expect(manager.showSideSheet, isFalse);

      // Visibilité posture par participant
      expect(manager.isPostureVisible('athlete-1'), isTrue);
      int sortCount = 0;
      manager.togglePostureVisibility('athlete-1', () => sortCount++);
      expect(manager.isPostureVisible('athlete-1'), isFalse);
      expect(sortCount, equals(1));

      // Télémétrie par participant via ValueListenable
      final listenable = manager.telemetryListenableFor('athlete-1');
      expect(listenable.value, isNull);

      final tel = RemoteTelemetry(
        heartRate: 152,
        cadence: 88,
        speed: 28.5,
        role: 'trainee',
        receivedAt: DateTime.now(),
      );
      manager.updateRemoteTelemetry('athlete-1', tel);
      expect(listenable.value?.heartRate, equals(152));
      expect(manager.remoteTelemetryMap['athlete-1']?.cadence, equals(88));

      // Suppression du participant nettoie ses états
      manager.removeParticipant('athlete-1');
      expect(manager.remoteTelemetryMap.containsKey('athlete-1'), isFalse);

      manager.dispose();
    });
  });

  group('RoomTelemetryCoordinator GPS & Location фильтрация (C2.2)', () {
    test('sanitizeSpeedKmh filtre l\'imprécision, la dérive stationnaire et les vitesses aberrantes', () {
      final t0 = DateTime.now();

      // Fix imprécis (> 25m) -> null
      expect(
        RoomTelemetryCoordinator.sanitizeSpeedKmh(
          _pos(lat: 48.85, lng: 2.35, accuracy: 40.0, speed: 5.0, timestamp: t0),
        ),
        isNull,
      );

      // Dérive à l'arrêt (< 1.0 km/h, soit speed = 0.1 m/s = 0.36 km/h) -> 0.0
      expect(
        RoomTelemetryCoordinator.sanitizeSpeedKmh(
          _pos(lat: 48.85, lng: 2.35, accuracy: 4.0, speed: 0.1, timestamp: t0),
        ),
        equals(0.0),
      );

      // Vitesse normale (5.0 m/s = 18.0 km/h) -> 18.0
      expect(
        RoomTelemetryCoordinator.sanitizeSpeedKmh(
          _pos(lat: 48.85, lng: 2.35, accuracy: 4.0, speed: 5.0, timestamp: t0),
        ),
        equals(18.0),
      );

      // Vitesse aberrante (> 75 km/h, ex: 30 m/s = 108 km/h) -> null
      expect(
        RoomTelemetryCoordinator.sanitizeSpeedKmh(
          _pos(lat: 48.85, lng: 2.35, accuracy: 4.0, speed: 30.0, timestamp: t0),
        ),
        isNull,
      );
    });

    test('computeFilteredDistanceDeltaMiles rejette le bruit sur place (< 3m) et les sauts GPS (> 75 km/h)', () {
      final t0 = DateTime(2026, 5, 1, 10, 0, 0);
      final p0 = _pos(lat: 48.8566, lng: 2.3522, timestamp: t0);

      // Premier point sans ancre précédente -> 0.0
      expect(
        RoomTelemetryCoordinator.computeFilteredDistanceDeltaMiles(null, p0),
        equals(0.0),
      );

      // Micro-déplacement (< 3m) -> 0.0
      final pMicro = _pos(
        lat: 48.856605,
        lng: 2.3522,
        timestamp: t0.add(const Duration(seconds: 2)),
      );
      expect(
        RoomTelemetryCoordinator.computeFilteredDistanceDeltaMiles(p0, pMicro),
        equals(0.0),
      );

      // Déplacement réaliste (~55m en 10s = ~20 km/h) -> > 0 miles
      final pValid = _pos(
        lat: 48.8571,
        lng: 2.3522,
        timestamp: t0.add(const Duration(seconds: 10)),
      );
      final validMiles = RoomTelemetryCoordinator.computeFilteredDistanceDeltaMiles(p0, pValid);
      expect(validMiles, isNotNull);
      expect(validMiles!, greaterThan(0.02));

      // Saut GPS aberrant (~1.1 km en 1s > 75 km/h) -> null
      final pJump = _pos(
        lat: 48.8666,
        lng: 2.3522,
        timestamp: t0.add(const Duration(seconds: 1)),
      );
      expect(
        RoomTelemetryCoordinator.computeFilteredDistanceDeltaMiles(p0, pJump),
        isNull,
      );
    });

    test('buildLocationSettings retourne AppleSettings fitness sur iOS et LocationSettings standard sur Android', () {
      final iosSettings = RoomTelemetryCoordinator.buildLocationSettings(
        platform: TargetPlatform.iOS,
      );
      expect(iosSettings, isA<AppleSettings>());

      final androidSettings = RoomTelemetryCoordinator.buildLocationSettings(
        platform: TargetPlatform.android,
      );
      expect(androidSettings.distanceFilter, equals(5));
    });
  });
}
