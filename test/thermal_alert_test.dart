import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/core/thermal_service.dart';
import 'package:videolog_coach/presentation/widgets/thermal_alert_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThermalInfo Models', () {
    test('ThermalInfo.normal() returns correct baseline values', () {
      final info = ThermalInfo.normal();
      expect(info.isOverheating, isFalse);
      expect(info.status, equals(0));
      expect(info.statusName, equals('NONE'));
      expect(info.batteryTempC, isNull);
    });

    test('ThermalInfo.fromMap parses standard payload correctly', () {
      final map = {
        'isOverheating': true,
        'status': 2,
        'statusName': 'MODERATE',
        'batteryTempC': 42.5,
      };

      final info = ThermalInfo.fromMap(map, source: 'test');
      expect(info.isOverheating, isTrue);
      expect(info.status, equals(2));
      expect(info.statusName, equals('MODERATE'));
      expect(info.batteryTempC, closeTo(42.5, 0.01));
      expect(info.source, equals('test'));
      expect(info.toString(), contains('MODERATE'));
      expect(info.toString(), contains('42.5°C'));
    });

    test('ThermalInfo.fromMap handles missing or null fields gracefully', () {
      final map = <String, dynamic>{};
      final info = ThermalInfo.fromMap(map);
      expect(info.isOverheating, isFalse);
      expect(info.status, equals(0));
      expect(info.statusName, equals('UNKNOWN'));
      expect(info.batteryTempC, isNull);
    });
  });

  group('ThermalService Logic', () {
    late ThermalService service;

    setUp(() {
      service = ThermalService.instance;
      service.resetForTesting();
    });

    tearDown(() {
      service.resetForTesting();
    });

    test('ThermalService initial state is not overheating', () {
      expect(service.isOverheating, isFalse);
      expect(service.isDialogShowing, isFalse);
      expect(service.thermalInfo.value.isOverheating, isFalse);
    });

    test('notifyThermalThrottled updates state and values', () {
      service.autoShowDialog = false; // Désactiver l'auto-dialog sans navigatorKey

      service.notifyThermalThrottled(isThrottled: true, reason: 'test_npu');
      expect(service.isOverheating, isTrue);
      expect(service.thermalInfo.value.status, greaterThanOrEqualTo(2));
      expect(service.thermalInfo.value.source, equals('test_npu'));

      // Retour à la normale
      service.notifyThermalThrottled(isThrottled: false, reason: 'test_npu');
      expect(service.isOverheating, isFalse);
      expect(service.thermalInfo.value.status, equals(0));
    });
  });

  group('ThermalAlertDialog Widget', () {
    testWidgets('renders dialog content, recommendations and button', (tester) async {
      final info = ThermalInfo(
        isOverheating: true,
        status: 2,
        statusName: 'MODERATE',
        batteryTempC: 43.0,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ThermalAlertDialog.show(context, info: info),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      // Ouvrir le dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Vérifier le titre et le contenu
      expect(find.text('Alerte Surchauffe'), findsOneWidget);
      expect(
        find.textContaining('température de votre appareil est anormalement élevée'),
        findsOneWidget,
      );
      expect(find.text('Recommandations immédiates :'), findsOneWidget);
      expect(
        find.textContaining('lumière directe du soleil'),
        findsOneWidget,
      );
      expect(
        find.textContaining('coque de protection'),
        findsOneWidget,
      );
      expect(
        find.textContaining('chargeur'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Niveau : MODERATE · 43.0°C'),
        findsOneWidget,
      );

      // Bouton "J'ai compris"
      final button = find.text('J\'ai compris');
      expect(button, findsOneWidget);

      // Fermer le dialog en cliquant sur le bouton
      await tester.tap(button);
      await tester.pumpAndSettle();

      // Le dialogue doit avoir disparu
      expect(find.text('Alerte Surchauffe'), findsNothing);
    });

    testWidgets('renders critical style when status >= 3', (tester) async {
      final info = ThermalInfo(
        isOverheating: true,
        status: 4,
        statusName: 'CRITICAL',
        batteryTempC: 46.5,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ThermalAlertDialog.show(context, info: info),
                child: const Text('Show Critical Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Critical Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Surchauffe Critique'), findsOneWidget);
      expect(find.textContaining('46.5°C'), findsOneWidget);
    });
  });
}
