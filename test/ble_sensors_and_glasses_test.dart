import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videolog_coach/core/ble_sensor_service.dart';
import 'package:videolog_coach/core/ble_telemetry_service.dart';
import 'package:videolog_coach/data/athlete_profile.dart';
import 'package:videolog_coach/viewmodels/room/room_telemetry_coordinator.dart';

Position _pos({
  required double lat,
  required double lng,
  double accuracy = 5.0,
  double speed = 0.0,
  required DateTime timestamp,
}) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: timestamp,
    accuracy: accuracy,
    altitude: 100.0,
    altitudeAccuracy: 3.0,
    heading: 0.0,
    headingAccuracy: 1.0,
    speed: speed,
    speedAccuracy: 0.5,
  );
}

void main() {
  group('BleHeartRateSensor (0x180D / 0x2A37)', () {
    test('décode une fréquence cardiaque UINT8 et UINT16 et émet sur heartRateStream', () async {
      final sensor = BleHeartRateSensor();
      final emitted = <int>[];
      final sub = sensor.heartRateStream.listen(emitted.add);

      // Flag 0x00 -> UINT8 (148 bpm)
      expect(sensor.handleMeasurementBytes([0x00, 148]), 148);
      // Flag 0x01 -> UINT16 LE (260 bpm = 0x0104 -> [0x04, 0x01])
      expect(sensor.handleMeasurementBytes([0x01, 0x04, 0x01]), 260);
      // Trame trop courte ignorée
      expect(sensor.handleMeasurementBytes([0x01, 0x04]), isNull);

      await Future<void>.delayed(Duration.zero);
      expect(emitted, [148, 260]);
      expect(sensor.lastHeartRate, 260);

      await sub.cancel();
      await sensor.dispose();
    });
  });

  group('BleCadenceSpeedSensor (0x1816 / 0x2A5B)', () {
    test('calcule la cadence en RPM à partir des deltas de pédalier et gère le débordement 16 bits', () async {
      final sensor = BleCadenceSpeedSensor();
      final emitted = <int>[];
      final sub = sensor.cadenceStream.listen(emitted.add);

      // Flag 0x02 = Crank Revolution Data present
      // 1re mesure : rev=100, time=1024 (1,0 s) -> amorçage (retourne null)
      expect(
        sensor.handleMeasurementBytes([0x02, 100, 0x00, 0x00, 0x04]),
        isNull,
      );

      // 2e mesure : rev=101 (+1 tour), time=1707 (+683/1024 s ≈ 0,667 s) -> ~90 RPM
      final rpm1 = sensor.handleMeasurementBytes([0x02, 101, 0x00, 0xAB, 0x06]);
      expect(rpm1, 90);

      // Test rollover 16 bits : rev=65535, time=65000 puis rev=0 (+1 tour), time=488 (+1024 ticks = 1,0 s) -> 60 RPM
      sensor.resetCrankState();
      expect(
        sensor.handleMeasurementBytes([0x02, 0xFF, 0xFF, 0xE8, 0xFD]),
        isNull,
      );
      final rpmRollover = sensor.handleMeasurementBytes([
        0x02,
        0x00,
        0x00,
        0xE8,
        0x01,
      ]);
      expect(rpmRollover, 60);

      await Future<void>.delayed(Duration.zero);
      expect(emitted, [90, 60]);

      await sub.cancel();
      await sensor.dispose();
    });
  });

  group('EngoGlassesDisplayService', () {
    test('décode une trame TX de batterie ActiveLook (0x05) et émet SportMetrics', () async {
      final service = EngoGlassesDisplayService(
        gattWriter: (_, _) async {},
      );
      final batteries = <int?>[];
      final sub = service.metricsStream.listen((m) => batteries.add(m.battery));

      // Trame ActiveLook [0xFF, cmd=0x05, fmt=0x00, len=0x06, battery=82, 0xAA]
      service.handleTxFrameBytes([0xFF, 0x05, 0x00, 0x06, 82, 0xAA]);
      await Future<void>.delayed(Duration.zero);

      expect(batteries, [82]);

      await sub.cancel();
      await service.dispose();
    });
  });

  group('Filtrage GPS anti-dérive & assainissement de vitesse', () {
    final t0 = DateTime.utc(2026, 5, 1, 10, 0, 0);

    test('sanitizeSpeedKmh filtre les vitesses négatives, le bruit stationnaire et les fixes imprécis', () {
      // Fix imprécis (> 25 m) -> null
      expect(
        RoomTelemetryCoordinator.sanitizeSpeedKmh(
          _pos(lat: 48.8566, lng: 2.3522, accuracy: 40.0, speed: 3.0, timestamp: t0),
        ),
        isNull,
      );

      // Vitesse négative (indisponible sur Android/iOS) -> 0.0 km/h
      expect(
        RoomTelemetryCoordinator.sanitizeSpeedKmh(
          _pos(lat: 48.8566, lng: 2.3522, speed: -1.0, timestamp: t0),
        ),
        0.0,
      );

      // Dérive stationnaire (< 1,0 km/h soit 0,2 m/s = 0,72 km/h) -> 0.0 km/h
      expect(
        RoomTelemetryCoordinator.sanitizeSpeedKmh(
          _pos(lat: 48.8566, lng: 2.3522, speed: 0.2, timestamp: t0),
        ),
        0.0,
      );

      // Vitesse course normale (4.0 m/s = 14.4 km/h) -> 14.4
      expect(
        RoomTelemetryCoordinator.sanitizeSpeedKmh(
          _pos(lat: 48.8566, lng: 2.3522, speed: 4.0, timestamp: t0),
        ),
        14.4,
      );

      // Saut GPS aberrant (30 m/s = 108 km/h > 75 km/h) -> null
      expect(
        RoomTelemetryCoordinator.sanitizeSpeedKmh(
          _pos(lat: 48.8566, lng: 2.3522, speed: 30.0, timestamp: t0),
        ),
        isNull,
      );
    });

    test('processPositionUpdate rejette le bruit < 3m, les fixes > 25m et les téléportations > 75 km/h', () {
      var updates = 0;
      final coordinator = RoomTelemetryCoordinator(
        bleService: EngoGlassesDisplayService(gattWriter: (_, _) async {}),
        sensorService: BleSensorService(),
        onTelemetryUpdated: () => updates++,
      );

      // 1. Premier point de référence valide
      final p0 = _pos(lat: 48.856600, lng: 2.352200, accuracy: 5.0, timestamp: t0);
      expect(coordinator.processPositionUpdate(p0), isTrue);
      expect(coordinator.totalDistanceKm, 0.0);
      expect(updates, 1);

      // 2. Bruit stationnaire (~1,1 m : +0.00001° lat) -> accepté mais distance = 0
      final pJitter = _pos(
        lat: 48.856610,
        lng: 2.352200,
        accuracy: 5.0,
        timestamp: t0.add(const Duration(seconds: 2)),
      );
      expect(coordinator.processPositionUpdate(pJitter), isTrue);
      expect(coordinator.totalDistanceKm, 0.0);

      // 3. Fix imprécis (accuracy = 45 m) -> rejeté
      final pBadAcc = _pos(
        lat: 48.857000,
        lng: 2.352200,
        accuracy: 45.0,
        timestamp: t0.add(const Duration(seconds: 4)),
      );
      expect(coordinator.processPositionUpdate(pBadAcc), isFalse);
      expect(coordinator.totalDistanceKm, 0.0);

      // 4. Téléportation GPS (~1,1 km en 1 seconde -> ~4000 km/h) -> rejeté
      final pTeleport = _pos(
        lat: 48.866600,
        lng: 2.352200,
        accuracy: 5.0,
        timestamp: t0.add(const Duration(seconds: 5)),
      );
      expect(coordinator.processPositionUpdate(pTeleport), isFalse);
      expect(coordinator.totalDistanceKm, 0.0);

      // 5. Déplacement réel (~22,2 m en 6 s -> ~13,3 km/h) -> distance cumulée > 0
      final pValidMove = _pos(
        lat: 48.856800,
        lng: 2.352200,
        accuracy: 5.0,
        speed: 3.7,
        timestamp: t0.add(const Duration(seconds: 6)),
      );
      expect(coordinator.processPositionUpdate(pValidMove), isTrue);
      expect(coordinator.totalDistanceKm, closeTo(0.0222, 0.002));
    });
  });

  group('AthleteProfile lié au uid utilisateur', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('AthleteProfile persiste poids/âge/genre/FCmax et ajuste le calcul de calories', () async {
      final prefs = await SharedPreferences.getInstance();
      final defaultProfile = await AthleteProfile.load(prefs, 'user_1');
      expect(defaultProfile.weightKg, 70.0);
      expect(defaultProfile.ageYears, 30);
      expect(defaultProfile.isMale, isTrue);
      expect(defaultProfile.maxHeartRate, 190); // 220 - 30

      const custom = AthleteProfile(
        weightKg: 62.5,
        ageYears: 28,
        isMale: false,
        customMaxHeartRate: 195,
      );
      await custom.save(prefs, 'user_1');

      final reloaded = await AthleteProfile.load(prefs, 'user_1');
      expect(reloaded.weightKg, 62.5);
      expect(reloaded.ageYears, 28);
      expect(reloaded.isMale, isFalse);
      expect(reloaded.maxHeartRate, 195);

      // Vérifie que SportMetrics.estimateKcal différencie les profils
      final kcalDefault = SportMetrics.estimateKcal(
        bpm: 155,
        durationSeconds: 1800,
        weightKg: defaultProfile.weightKg,
        ageYears: defaultProfile.ageYears,
        isMale: defaultProfile.isMale,
      );
      final kcalCustom = SportMetrics.estimateKcal(
        bpm: 155,
        durationSeconds: 1800,
        weightKg: reloaded.weightKg,
        ageYears: reloaded.ageYears,
        isMale: reloaded.isMale,
      );
      expect(kcalDefault, isNot(equals(kcalCustom)));
      expect(kcalCustom, greaterThan(0));
    });

    test('AthleteProfile isole les données entre deux comptes utilisateurs distincts (uid)', () async {
      final prefs = await SharedPreferences.getInstance();

      const profileA = AthleteProfile(
        weightKg: 58.0,
        ageYears: 24,
        isMale: false,
        customMaxHeartRate: 198,
      );
      const profileB = AthleteProfile(
        weightKg: 84.0,
        ageYears: 42,
        isMale: true,
      );

      await profileA.save(prefs, 'uid_alice');
      await profileB.save(prefs, 'uid_bob');

      final loadedA = await AthleteProfile.load(prefs, 'uid_alice');
      final loadedB = await AthleteProfile.load(prefs, 'uid_bob');
      final loadedUnknown = await AthleteProfile.load(prefs, 'uid_charlie');

      expect(loadedA.weightKg, 58.0);
      expect(loadedA.ageYears, 24);
      expect(loadedA.isMale, isFalse);
      expect(loadedA.maxHeartRate, 198);

      expect(loadedB.weightKg, 84.0);
      expect(loadedB.ageYears, 42);
      expect(loadedB.isMale, isTrue);
      expect(loadedB.maxHeartRate, 178); // 220 - 42

      // Un nouvel utilisateur sur le même appareil obtient les valeurs par défaut
      expect(loadedUnknown.weightKg, AthleteProfile.defaultWeightKg);
      expect(loadedUnknown.ageYears, AthleteProfile.defaultAgeYears);
    });
  });
}
