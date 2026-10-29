import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/data/heart_rate_zones.dart';
import 'package:videolog_coach/presentation/widgets/heart_rate_gauge.dart';

void main() {
  group('HeartRateZone', () {
    test('calculates correct zones based on bpm (default maxHr=190)', () {
      // Z1: < 60% of 190 (< 114 bpm)
      expect(HeartRateZone.fromBpm(0).level, HeartRateZoneLevel.z1);
      expect(HeartRateZone.fromBpm(100).level, HeartRateZoneLevel.z1);
      expect(HeartRateZone.fromBpm(100).code, 'Z1');
      expect(HeartRateZone.fromBpm(100).name, 'Récupération');

      // Z2: 60-70% of 190 (114 - 132 bpm)
      expect(HeartRateZone.fromBpm(114).level, HeartRateZoneLevel.z2);
      expect(HeartRateZone.fromBpm(125).level, HeartRateZoneLevel.z2);
      expect(HeartRateZone.fromBpm(125).code, 'Z2');
      expect(HeartRateZone.fromBpm(125).name, 'Endurance');

      // Z3: 70-80% of 190 (133 - 151 bpm)
      expect(HeartRateZone.fromBpm(133).level, HeartRateZoneLevel.z3);
      expect(HeartRateZone.fromBpm(145).level, HeartRateZoneLevel.z3);
      expect(HeartRateZone.fromBpm(145).code, 'Z3');
      expect(HeartRateZone.fromBpm(145).name, 'Tempo');

      // Z4: 80-90% of 190 (152 - 170 bpm)
      expect(HeartRateZone.fromBpm(152).level, HeartRateZoneLevel.z4);
      expect(HeartRateZone.fromBpm(165).level, HeartRateZoneLevel.z4);
      expect(HeartRateZone.fromBpm(165).code, 'Z4');
      expect(HeartRateZone.fromBpm(165).name, 'Seuil');

      // Z5: >= 90% of 190 (>= 171 bpm)
      expect(HeartRateZone.fromBpm(171).level, HeartRateZoneLevel.z5);
      expect(HeartRateZone.fromBpm(195).level, HeartRateZoneLevel.z5);
      expect(HeartRateZone.fromBpm(195).code, 'Z5');
      expect(HeartRateZone.fromBpm(195).name, 'VO2 Max');
    });

    test('supports custom maxHr', () {
      // With maxHr = 200:
      // Z1 < 120, Z2 = 120..139, Z3 = 140..159, Z4 = 160..179, Z5 >= 180
      expect(HeartRateZone.fromBpm(118, maxHr: 200).level, HeartRateZoneLevel.z1);
      expect(HeartRateZone.fromBpm(125, maxHr: 200).level, HeartRateZoneLevel.z2);
      expect(HeartRateZone.fromBpm(150, maxHr: 200).level, HeartRateZoneLevel.z3);
      expect(HeartRateZone.fromBpm(170, maxHr: 200).level, HeartRateZoneLevel.z4);
      expect(HeartRateZone.fromBpm(185, maxHr: 200).level, HeartRateZoneLevel.z5);
    });

    test('has distinct colors for each zone', () {
      final colors = HeartRateZone.allZones.map((z) => z.color).toSet();
      expect(colors.length, 5);
    });
  });

  group('HeartRateHudGauge Widget', () {
    testWidgets('renders zone badge and bpm reading', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HeartRateHudGauge(bpm: 142),
          ),
        ),
      );

      expect(find.text('Z3'), findsOneWidget);
      expect(find.text('142 bpm'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    });

    testWidgets('supports compact mode without intensity bar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HeartRateHudGauge(bpm: 168, compact: true),
          ),
        ),
      );

      expect(find.text('Z4'), findsOneWidget);
      expect(find.text('168 bpm'), findsOneWidget);
    });

    testWidgets('supports showValue=false for mini participant tiles', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HeartRateHudGauge(bpm: 175, showValue: false),
          ),
        ),
      );

      expect(find.text('Z5'), findsOneWidget);
      expect(find.text('175 bpm'), findsNothing);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    });
  });
}
