import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/core/single_flight.dart';

void main() {
  group('SingleFlight', () {
    test('une seule opération à la fois, dans l ordre d arrivée', () async {
      final flight = SingleFlight();
      final events = <String>[];
      final releaseFirst = Completer<void>();

      final first = flight.run(() async {
        events.add('start-1');
        await releaseFirst.future;
        events.add('end-1');
      });
      final second = flight.run(() async {
        events.add('start-2');
      });

      await Future<void>.delayed(Duration.zero);
      expect(events, ['start-1'], reason: 'la 2e attend la fin de la 1re');
      expect(flight.isBusy, isTrue);

      releaseFirst.complete();
      await Future.wait([first, second]);
      expect(events, ['start-1', 'end-1', 'start-2']);
      expect(flight.isBusy, isFalse);
    });

    test('une erreur ne bloque pas la file', () async {
      final flight = SingleFlight();

      await expectLater(
        flight.run<void>(() async => throw StateError('boom')),
        throwsStateError,
      );
      expect(flight.isBusy, isFalse);

      final result = await flight.run<int>(() async => 42);
      expect(result, 42);
    });

    test('les appels simultanés sont sérialisés', () async {
      final flight = SingleFlight();
      var running = 0;
      var maxRunning = 0;

      Future<void> job() async {
        running++;
        maxRunning = running > maxRunning ? running : maxRunning;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        running--;
      }

      await Future.wait([
        flight.run(job),
        flight.run(job),
        flight.run(job),
      ]);

      expect(maxRunning, 1);
    });
  });
}
