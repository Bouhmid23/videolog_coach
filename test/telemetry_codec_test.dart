import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/data/remote_telemetry.dart';
import 'package:videolog_coach/data/telemetry_codec.dart';
import 'package:videolog_coach/presentation/widgets/data_hud.dart';

void main() {
  group('TelemetryCodec v3 (25 octets)', () {
    test('encode et décode un paquet v3 complet avec bearing > 254 et puissance', () {
      const tsMs = 1763295000123;
      final bytes = TelemetryCodec.encode(
        role: 'trainee',
        speed: 34.56,
        heartRate: 164,
        cadence: 92,
        lat: 45.764043,
        lng: 4.835659,
        altitude: 175.42,
        bearing: 315,
        powerWatts: 285,
        timestampMs: tsMs,
      );

      expect(bytes.length, 25);
      final bd = ByteData.sublistView(bytes);
      expect(bd.getUint8(0), 3); // version
      expect(bd.getUint8(1), 1); // trainee
      expect(bd.getUint16(2, Endian.big), 3456);
      expect(bd.getUint8(4), 164);
      expect(bd.getUint8(5), 92);
      expect(bd.getInt16(14, Endian.big), 17542);
      expect(bd.getUint16(16, Endian.big), 315);
      expect(bd.getUint16(18, Endian.big), 285);
      expect(bd.getUint32(20, Endian.big), tsMs & 0xFFFFFFFF);
      expect(bd.getUint8(24), 0); // flags

      final decoded = TelemetryCodec.decode(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.role, 'trainee');
      expect(decoded.speed, closeTo(34.56, 0.01));
      expect(decoded.heartRate, 164);
      expect(decoded.cadence, 92);
      expect(decoded.lat!, closeTo(45.764043, 1e-6));
      expect(decoded.lng!, closeTo(4.835659, 1e-6));
      expect(decoded.altitude!, closeTo(175.42, 0.01));
      expect(decoded.bearing, 315);
      expect(decoded.powerWatts, 285);
    });

    test('encode et décode correctement les champs nuls et bearing négatif', () {
      final bytes = TelemetryCodec.encode(
        role: 'coach',
        speed: null,
        heartRate: null,
        cadence: null,
        lat: null,
        lng: null,
        altitude: null,
        bearing: -1.0, // Geolocator heading indisponible
        powerWatts: null,
        timestampMs: 1000,
      );

      expect(bytes.length, 25);
      final decoded = TelemetryCodec.decode(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.role, 'coach');
      expect(decoded.speed, isNull);
      expect(decoded.heartRate, isNull);
      expect(decoded.cadence, isNull);
      expect(decoded.lat, isNull);
      expect(decoded.lng, isNull);
      expect(decoded.altitude, isNull);
      expect(decoded.bearing, isNull);
      expect(decoded.powerWatts, isNull);
      expect(decoded.hasData, isFalse);
    });

    test('décode de manière rétrocompatible un paquet v2 de 21 octets', () {
      final v2 = Uint8List(21);
      final bd = ByteData.sublistView(v2);
      bd.setUint8(0, 2); // v2
      bd.setUint8(1, 1); // trainee
      bd.setUint16(2, 2850, Endian.big); // 28.50 km/h
      bd.setUint8(4, 152); // bpm
      bd.setUint8(5, 86); // rpm
      bd.setInt32(6, 457640000, Endian.big);
      bd.setInt32(10, 48356000, Endian.big);
      bd.setInt16(14, 15000, Endian.big); // 150.00 m
      bd.setUint8(16, 180); // bearing
      bd.setUint32(17, 5000, Endian.big);

      final decoded = TelemetryCodec.decode(v2);
      expect(decoded, isNotNull);
      expect(decoded!.role, 'trainee');
      expect(decoded.speed, closeTo(28.5, 0.01));
      expect(decoded.heartRate, 152);
      expect(decoded.cadence, 86);
      expect(decoded.bearing, 180);
      expect(decoded.powerWatts, isNull);
    });

    test('rejette les paquets de taille ou version invalide', () {
      expect(TelemetryCodec.decode([]), isNull);
      expect(TelemetryCodec.decode(Uint8List(20)), isNull);
      expect(TelemetryCodec.decode(Uint8List(25)), isNull); // version 0
    });
  });

  group('RemoteTelemetry & DataHud puissance', () {
    test('parse power_w JSON et compare equalValues', () {
      final a = RemoteTelemetry.fromJson({
        'heart_rate': 160,
        'power_w': 270,
        'role': 'trainee',
      });
      final b = RemoteTelemetry.fromJson({
        'heart_rate': 160,
        'power_w': 270,
        'role': 'trainee',
      });
      final c = RemoteTelemetry.fromJson({
        'heart_rate': 160,
        'power_w': 295,
        'role': 'trainee',
      });

      expect(a.powerWatts, 270);
      expect(a.hasData, isTrue);
      expect(a.equalValues(b), isTrue);
      expect(a.equalValues(c), isFalse);
    });

    testWidgets('DataHud affiche la puissance en watts', (tester) async {
      final telemetry = RemoteTelemetry(
        heartRate: 155,
        powerWatts: 285,
        receivedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataHud(telemetry: telemetry),
          ),
        ),
      );

      expect(find.text('155 bpm'), findsOneWidget);
      expect(find.text('285 W'), findsOneWidget);
    });
  });
}
