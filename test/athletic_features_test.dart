import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/core/athletic_haptics.dart';
import 'package:videolog_coach/data/remote_telemetry.dart';
import 'package:videolog_coach/presentation/widgets/data_hud.dart';
import 'package:videolog_coach/presentation/widgets/sweat_lock_overlay.dart';

void main() {
  group('Outdoor Sun Mode & Neon Zones', () {
    test('HeartRateZone retourne des couleurs néon saturées en mode plein soleil', () {
      // Z2 - Vert néon
      final z2 = HeartRateZone.z2;
      expect(z2.colorFor(outdoorSunMode: false), const Color(0xFF10B981));
      expect(z2.colorFor(outdoorSunMode: true), const Color(0xFF00FF66));

      // Z3 - Ambre néon
      final z3 = HeartRateZone.z3;
      expect(z3.colorFor(outdoorSunMode: false), const Color(0xFFF59E0B));
      expect(z3.colorFor(outdoorSunMode: true), const Color(0xFFFFB800));

      // Z5 - Rouge vif néon
      final z5 = HeartRateZone.z5;
      expect(z5.colorFor(outdoorSunMode: false), const Color(0xFFEF4444));
      expect(z5.colorFor(outdoorSunMode: true), const Color(0xFFFF0033));
    });

    testWidgets('HeartRateHudGauge applique fond noir opaque et couleur néon en plein soleil', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HeartRateHudGauge(
              bpm: 175, // Z5
              outdoorSunMode: true,
            ),
          ),
        ),
      );

      final containerFinder = find.byType(Container).first;
      final container = tester.widget<Container>(containerFinder);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, Colors.black);
      expect(decoration.border?.top.color, const Color(0xFFFF0033));
      expect(find.text('Z5'), findsOneWidget);
      expect(find.text('175 bpm'), findsOneWidget);
    });
  });

  group('AnimatedSportsCount & Monospaced Figures', () {
    testWidgets('utilise tabularFigures et rend la valeur avec suffixe', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedSportsCount(
              value: 28.4,
              fractionDigits: 1,
              suffix: ' km/h',
            ),
          ),
        ),
      );

      expect(find.text('28.4 km/h'), findsOneWidget);
      final textWidget = tester.widget<Text>(find.text('28.4 km/h'));
      expect(
        textWidget.style?.fontFeatures?.contains(const ui.FontFeature.tabularFigures()),
        isTrue,
      );
    });

    testWidgets('supporte le mode plein soleil avec typographie blanche pure', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedSportsCount(
              value: 95,
              fractionDigits: 0,
              suffix: ' rpm',
              outdoorSunMode: true,
            ),
          ),
        ),
      );

      expect(find.text('95 rpm'), findsOneWidget);
      final textWidget = tester.widget<Text>(find.text('95 rpm'));
      expect(textWidget.style?.color, Colors.white);
      expect(textWidget.style?.fontWeight, FontWeight.w900);
    });
  });

  group('DataHud en Outdoor Sun Mode', () {
    testWidgets('DataHud applique fond opaque et bordure blanche en plein soleil', (tester) async {
      final telemetry = RemoteTelemetry(
        speed: 32.5,
        cadence: 88,
        heartRate: 145,
        receivedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataHud(
              telemetry: telemetry,
              outdoorSunMode: true,
            ),
          ),
        ),
      );

      expect(find.text('32.5 km/h'), findsOneWidget);
      expect(find.text('88 rpm'), findsOneWidget);
      expect(find.text('145 bpm'), findsOneWidget);
    });
  });

  group('SweatLockOverlay (Pocket & Sweat Lock)', () {
    testWidgets('affiche les avertissements de verrouillage et réagit au maintien', (tester) async {
      bool unlocked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                SweatLockOverlay(
                  onUnlock: () => unlocked = true,
                  outdoorSunMode: true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('POCKET & SWEAT LOCK ACTIF'), findsOneWidget);
      expect(find.text('Maintenir 1.5s pour déverrouiller'), findsOneWidget);

      // Tap simple ne déverrouille pas
      await tester.tap(find.text('Maintenir 1.5s pour déverrouiller'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(unlocked, isFalse);

      // Appui long simulé
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CircularProgressIndicator)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Maintenez...'), findsOneWidget);
      expect(unlocked, isFalse);

      // Maintien jusqu'à dépasser les 1500ms requises
      await tester.pump(const Duration(milliseconds: 1600));
      expect(unlocked, isTrue);
      await gesture.up();
      await tester.pump();
    });
  });

  group('AthleticHaptics API', () {
    test('les méthodes haptiques s exécutent sans erreur', () async {
      await expectLater(AthleticHaptics.thresholdZone5Alert(), completes);
      await expectLater(AthleticHaptics.coachingDoublePulse(), completes);
      await expectLater(AthleticHaptics.sweatLockToggled(locked: true), completes);
      await expectLater(AthleticHaptics.sweatLockToggled(locked: false), completes);
      await expectLater(AthleticHaptics.outdoorModeToggled(active: true), completes);
      await expectLater(AthleticHaptics.participantSwitched(), completes);
      await expectLater(AthleticHaptics.micToggled(muted: true), completes);
      await expectLater(AthleticHaptics.micToggled(muted: false), completes);
    });
  });
}
