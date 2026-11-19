import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:videolog_coach/core/recording_controller.dart';
import 'package:videolog_coach/data/recording_state.dart';
import 'package:videolog_coach/exts.dart';
import 'package:videolog_coach/presentation/utils/ui_utils.dart';
import 'package:videolog_coach/presentation/widgets/recording_controls.dart';
import 'package:videolog_coach/theme.dart';

double _relativeLuminance(Color c) {
  double channel(double v) => v <= 0.03928
      ? v / 12.92
      : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

double _contrastRatio(Color fg, Color bg) {
  final l1 = _relativeLuminance(fg);
  final l2 = _relativeLuminance(bg);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Phase 1 — Design System & Contraste WCAG', () {
    test('LKColors.textHint respecte un ratio de contraste >= 4.5:1 sur les surfaces principales', () {
      expect(
        _contrastRatio(LKColors.textHint, LKColors.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(LKColors.textHint, LKColors.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(LKColors.textHint, LKColors.surfaceElevated),
        greaterThanOrEqualTo(4.5),
      );
    });

    testWidgets('LiveKitTheme expose les thèmes M3 centralisés et VideologThemeTokens', (tester) async {
      late ThemeData builtTheme;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              builtTheme = const LiveKitTheme().buildThemeData(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(builtTheme.useMaterial3, isTrue);
      expect(builtTheme.colorScheme.surfaceContainer, LKColors.surfaceElevated);
      expect(builtTheme.colorScheme.surfaceContainerLow, LKColors.surface);
      expect(builtTheme.colorScheme.outline, LKColors.border);

      expect(builtTheme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(builtTheme.bottomSheetTheme.showDragHandle, isTrue);
      expect(builtTheme.filledButtonTheme.style, isNotNull);
      expect(builtTheme.outlinedButtonTheme.style, isNotNull);
      expect(builtTheme.textButtonTheme.style, isNotNull);

      final tokens = builtTheme.extension<VideologThemeTokens>();
      expect(tokens, isNotNull);
      expect(tokens!.success, LKColors.success);
      expect(tokens.warning, LKColors.warning);
      expect(tokens.outdoorBackground, Colors.black);
      expect(tokens.outdoorBorder, Colors.white);
    });

    testWidgets('UIUtils.showSnackBar affiche un SnackBar flottant stylisé', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => UIUtils.showSnackBar(
                  context,
                  'Synchronisation terminée',
                  tone: AppSnackBarTone.success,
                ),
                child: const Text('Trigger'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger'));
      await tester.pump();

      expect(find.text('Synchronisation terminée'), findsOneWidget);
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar, isNotNull);
    });
  });

  group('Phase 1 — Sécurité Déconnexion & Cibles Tactiles 48dp', () {
    testWidgets('showSignOutDialog demande confirmation et retourne false/true selon le choix', (tester) async {
      bool? lastResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  lastResult = await context.showSignOutDialog();
                },
                child: const Text('Logout'),
              ),
            ),
          ),
        ),
      );

      // Annuler
      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();
      expect(find.text('Se déconnecter'), findsNWidgets(2)); // Titre + bouton
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(lastResult, isFalse);

      // Confirmer
      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Se déconnecter'));
      await tester.pumpAndSettle();
      expect(lastResult, isTrue);
    });

    testWidgets('RecordingControls respecte des cibles tactiles >= 48x48 dp', (tester) async {
      final controller = RecordingController(
        roomName: 'session-test',
        canControl: true,
      );
      addTearDown(controller.dispose);
      controller.state = RecordingState.fromJson({
        'room_name': 'session-test',
        'status': 'recording',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RecordingControls(
                controller: controller,
                showActions: true,
              ),
            ),
          ),
        ),
      );

      final stopFinder = find.byIcon(Icons.stop_circle_rounded);
      expect(stopFinder, findsOneWidget);
      final stopButtonFinder = find.ancestor(
        of: stopFinder,
        matching: find.byType(IconButton),
      );
      final size = tester.getSize(stopButtonFinder);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));

      // Cas état indisponible -> bouton refresh >= 48x48
      controller.state = null;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RecordingControls(
                controller: controller,
                showActions: true,
              ),
            ),
          ),
        ),
      );

      final refreshFinder = find.byIcon(Icons.refresh_rounded);
      expect(refreshFinder, findsOneWidget);
      final refreshButtonFinder = find.ancestor(
        of: refreshFinder,
        matching: find.byType(IconButton),
      );
      final refreshSize = tester.getSize(refreshButtonFinder);
      expect(refreshSize.width, greaterThanOrEqualTo(48));
      expect(refreshSize.height, greaterThanOrEqualTo(48));
    });
  });
}
