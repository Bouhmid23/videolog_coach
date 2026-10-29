import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/core/ble_cadence_speed_sensor.dart';
import 'package:videolog_coach/core/ble_heart_rate_sensor.dart';
import 'package:videolog_coach/core/engo_glasses_display_service.dart';

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
}
