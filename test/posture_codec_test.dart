import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:videolog_coach/core/call_foreground_service.dart';
import 'package:videolog_coach/data/posture_codec.dart';
import 'package:videolog_coach/viewmodels/pose/pose_publisher.dart';
import 'package:videolog_coach/viewmodels/pose_detection_viewmodel.dart';
import 'package:videolog_coach/viewmodels/room/room_telemetry_coordinator.dart';
import 'package:videolog_coach/viewmodels/room_viewmodel.dart';

class _TrackingPoseDetectionViewModel extends PoseDetectionViewModel {
  int stopCalls = 0;

  @override
  void stop() {
    stopCalls++;
    super.stop();
  }
}

/// Décode x et y image (12 bits chacun, plage [-0.5, 1.5]) du point [index] d'un paquet v7.
({double x, double y}) _imagePoint(Uint8List p, int index) {
  final o = PostureCodec.headerSize + index * PostureCodec.pointSize;
  final qx = (p[o] << 4) | (p[o + 1] >> 4);
  final qy = ((p[o + 1] & 0xF) << 8) | p[o + 2];
  double dq(int q) => q / 4095 * 2 - 0.5;
  return (x: dq(qx), y: dq(qy));
}

List<PoseLandmark> _pose(double Function(int) x, double Function(int) y) => [
      for (final type in LandmarkType.values)
        PoseLandmark(type: type, x: x(type.value), y: y(type.value), visibility: 1),
    ];

Uint8List _encode(List<PoseLandmark> landmarks, Size size) => PostureCodec.encode(
      label: 'assis',
      confidence: 1,
      landmarks: landmarks,
      worldLandmarks: const [],
      frameSize: size,
      seq: 1,
      timestampMs: 0,
    );

void main() {
  const size = Size(240, 320);

  test('pose normalisée entièrement dans le cadre : points conservés', () {
    final p = _encode(_pose((i) => 0.2 + i * 0.01, (i) => 0.1 + i * 0.02), size);
    final nose = _imagePoint(p, 0);
    expect(nose.x, closeTo(0.2, 0.001));
    expect(nose.y, closeTo(0.1, 0.001));
  });

  test('sportif assis près du téléphone : chevilles et pieds hors cadre (y > 2) restent normalisés', () {
    // y de 0,5 (nez) à 2,54 (pieds) : régression, tout était divisé par 240 / 320 et écrasé au coin (0, 0).
    final p = _encode(_pose((i) => 0.3, (i) => i == 0 ? 0.51 : (i >= 27 ? 2.54 : 1.0)), size);
    final nose = _imagePoint(p, 0);
    expect(nose.x, closeTo(0.3, 0.001));
    expect(nose.y, closeTo(0.51, 0.001));
    // Les points très hors cadre sont bornés par la plage [-0.5, 1.5].
    expect(_imagePoint(p, 31).y, closeTo(1.5, 0.001));
  });

  test('pose en pixels (au moins un point au-delà du seuil) : divisée par la taille de l\'image', () {
    final p = _encode(_pose((i) => 120.0, (i) => 160.0), size);
    final nose = _imagePoint(p, 0);
    expect(nose.x, closeTo(0.5, 0.001));
    expect(nose.y, closeTo(0.5, 0.001));
  });

  test('isPixelSpace : un point hors cadre reste normalisé, des pixels sont reconnus', () {
    // Coude à x = 1,07, hanches à y = 1,36, chevilles à y = 2,5 : normalisé (régression du dessin).
    expect(PostureCodec.isPixelSpace(_pose((i) => i == 13 ? 1.07 : 0.4, (i) => i >= 23 ? 2.5 : 0.5)), isFalse);
    expect(PostureCodec.isPixelSpace(_pose((i) => 120.0, (i) => 160.0)), isTrue);
  });

  test('PosePublisher : liste vide suspend la publication (pas de broadcast involontaire)', () {
    final publisher = PosePublisher();
    expect(publisher.destinationIdentities, isNull);
    expect(publisher.canPublish, isTrue);

    publisher.setDestinationIdentities(const <String>[]);
    expect(publisher.destinationIdentities, isEmpty);
    expect(publisher.canPublish, isFalse);

    publisher.setDestinationIdentities(const <String>['coach-1']);
    expect(publisher.destinationIdentities, equals(const <String>['coach-1']));
    expect(publisher.canPublish, isTrue);

    publisher.setDestinationIdentities(null);
    expect(publisher.destinationIdentities, isNull);
    expect(publisher.canPublish, isTrue);
  });

  test('CallForegroundService : inclut camera, microphone, connectedDevice et location', () {
    final rawTypes = CallForegroundService.defaultServiceTypes
        .map((t) => t.rawValue)
        .toSet();
    expect(rawTypes.length, 4);
    expect(CallForegroundService.defaultNotificationInitialRoute, '/rooms');
  });

  test('RoomTelemetryCoordinator.buildLocationSettings configure AppleSettings en mode fitness sur iOS', () {
    final iosSettings = RoomTelemetryCoordinator.buildLocationSettings(
      platform: TargetPlatform.iOS,
    );
    expect(iosSettings, isA<AppleSettings>());
    final apple = iosSettings as AppleSettings;
    expect(apple.activityType, ActivityType.fitness);
    expect(apple.allowBackgroundLocationUpdates, isTrue);
    expect(apple.showBackgroundLocationIndicator, isTrue);
    expect(apple.pauseLocationUpdatesAutomatically, isFalse);

    final androidSettings = RoomTelemetryCoordinator.buildLocationSettings(
      platform: TargetPlatform.android,
    );
    expect(androidSettings, isNot(isA<AppleSettings>()));
    expect(androidSettings.accuracy, LocationAccuracy.high);
    expect(androidSettings.distanceFilter, 5);
  });

  test('RoomViewModel : posture désactivée au démarrage et pilotée par togglePosture', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final trackingPoseVm = _TrackingPoseDetectionViewModel();
    final vm = RoomViewModel(poseViewModel: trackingPoseVm);

    // Au démarrage de l'appel, l'affichage et la détection sont tous deux inactifs.
    expect(vm.showPosture, isFalse);
    expect(vm.showPostureListenable.value, isFalse);
    expect(trackingPoseVm.isBusy, isFalse);

    // Premier clic sur le bouton de posture -> active l'affichage.
    vm.togglePosture();
    expect(vm.showPosture, isTrue);
    expect(vm.showPostureListenable.value, isTrue);

    // Second clic -> coupe l'affichage et arrête la détection de posture.
    vm.togglePosture();
    expect(vm.showPosture, isFalse);
    expect(vm.showPostureListenable.value, isFalse);
    expect(trackingPoseVm.stopCalls, 1);
    expect(trackingPoseVm.isBusy, isFalse);
  });
}
