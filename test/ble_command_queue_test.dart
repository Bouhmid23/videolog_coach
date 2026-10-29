import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/core/ble_telemetry_service.dart';

void main() {
  group('BleTelemetryService GATT Command Queue', () {
    test(
      'attend chaque accusé d\'écriture GATT (writeCharacteristicWithResponse) dans l\'ordre strict',
      () async {
        final pendingAcks = <Completer<void>>[];
        final writtenPayloads = <List<int>>[];

        final service = BleTelemetryService(
          gattWriter: (deviceId, bytes) {
            writtenPayloads.add(bytes);
            final ack = Completer<void>();
            pendingAcks.add(ack);
            return ack.future;
          },
        );
        service.debugConfigureSession(
          deviceId: 'engo-1',
          displaySessionActive: true,
          negotiatedMtu: 128,
        );

        var firstDone = false;
        var secondDone = false;

        final f1 = service.enqueueCommand('engo-1', [0xFF, 0x01, 0x00, 0x05, 0xAA]).then((_) {
          firstDone = true;
        });
        final f2 = service.enqueueCommand('engo-1', [0xFF, 0x05, 0x00, 0x05, 0xAA]).then((_) {
          secondDone = true;
        });

        await Future<void>.delayed(Duration.zero);
        expect(writtenPayloads.length, 1);
        expect(firstDone, isFalse);
        expect(secondDone, isFalse);

        // Acquitte la 1re écriture GATT -> la 2e démarre immédiatement sans Future.delayed arbitraire
        pendingAcks[0].complete();
        await Future<void>.delayed(Duration.zero);
        expect(firstDone, isTrue);
        expect(writtenPayloads.length, 2);
        expect(secondDone, isFalse);

        // Acquitte la 2e écriture GATT
        pendingAcks[1].complete();
        await Future.wait([f1, f2]);
        expect(secondDone, isTrue);

        await service.dispose();
      },
    );

    test(
      'aucune trame tronquée quand un message coach arrive pendant un rafraîchissement télémétrique',
      () async {
        final gate = Completer<void>();
        var holdGateOnFirstWrite = true;
        final framesWritten = <List<int>>[];

        final service = BleTelemetryService(
          gattWriter: (deviceId, bytes) async {
            framesWritten.add(bytes);
            if (holdGateOnFirstWrite) {
              holdGateOnFirstWrite = false;
              await gate.future;
            }
          },
        );
        service.debugConfigureSession(
          deviceId: 'engo-1',
          displaySessionActive: true,
          negotiatedMtu: 128,
        );

        // 1) Télémétrie #1 démarre son écriture (bloquée sur la 1re commande Hold)
        final tel1Future = service.displayMetrics(
          'engo-1',
          distanceMiles: 1.0,
          bpm: 140,
          kcal: 100,
          cadence: 80,
        );
        await Future<void>.delayed(Duration.zero);
        expect(framesWritten.length, 1);

        // 2) Télémétrie #2 et #3 arrivent pendant que #1 écrit encore -> coalescées en file
        final tel2Future = service.displayMetrics(
          'engo-1',
          distanceMiles: 2.0,
          bpm: 150,
          kcal: 110,
          cadence: 85,
        );
        final tel3Future = service.displayMetrics(
          'engo-1',
          distanceMiles: 3.0,
          bpm: 160,
          kcal: 120,
          cadence: 90,
        );

        // 3) Un message coach arrive simultanément -> évince la télémétrie en attente (#2/#3),
        //    mais laisse la transaction #1 en cours finir son Flush sans troncature !
        final coachFuture = service.showMessage(
          const ['GARDE LE RYTHME'],
          const Duration(seconds: 5),
        );

        // Libère le verrou GATT
        gate.complete();
        await Future.wait([tel1Future, tel2Future, tel3Future]);
        final coachShown = await coachFuture;
        expect(coachShown, isTrue);

        // Vérification : chaque bloc commence par Hold [0xFF, 0x39, 0x00, 0x06, 0x00, 0xAA]
        // suivi de Clear [0xFF, 0x01, 0x00, 0x05, 0xAA] et se termine par Flush [0xFF, 0x39, 0x00, 0x06, 0x01, 0xAA].
        final holdIndices = <int>[];
        final flushIndices = <int>[];
        for (var i = 0; i < framesWritten.length; i++) {
          final f = framesWritten[i];
          if (f.length >= 6 && f[1] == 0x39 && f[4] == 0x00) {
            holdIndices.add(i);
          } else if (f.length >= 6 && f[1] == 0x39 && f[4] == 0x01) {
            flushIndices.add(i);
          }
        }

        // Exactement 2 transactions complètes ont été envoyées : Télémétrie #1 puis Message Coach
        // (Télémétrie #2 et #3 ont été proprement évincées avant leur démarrage).
        expect(holdIndices.length, 2);
        expect(flushIndices.length, 2);
        expect(holdIndices[0], 0);
        expect(flushIndices[0], lessThan(holdIndices[1]));
        expect(flushIndices[1], framesWritten.length - 1);

        // Vérifie que le texte du coach est bien présent dans la 2e transaction
        final secondTxPayloads = framesWritten
            .sublist(holdIndices[1], flushIndices[1] + 1)
            .where((f) => f[1] == 0x37)
            .map((f) => ascii.decode(f.sublist(11, f.length - 1)))
            .toList();
        expect(secondTxPayloads, contains('GARDE LE RYTHME'));

        await service.dispose();
      },
    );

    test(
      'contrôle de débit ActiveLook (0x02 STOP / 0x01 CAN_SEND) met en pause sans perdre de trame',
      () async {
        final framesWritten = <List<int>>[];

        late final BleTelemetryService service;
        service = BleTelemetryService(
          gattWriter: (deviceId, bytes) async {
            framesWritten.add(bytes);
            // Dès la 2e trame (Clear), les lunettes signalent un buffer à 75% (0x02 STOP)
            if (framesWritten.length == 2) {
              service.handleFlowControlByte(0x02);
            }
          },
        );
        service.debugConfigureSession(
          deviceId: 'engo-1',
          displaySessionActive: true,
          negotiatedMtu: 128,
        );

        var completed = false;
        final future = service
            .showMessage(const ['PAUSE FLOW'], const Duration(seconds: 5))
            .then((ok) {
              completed = ok;
            });

        await Future<void>.delayed(const Duration(milliseconds: 20));
        // En pause après 2 trames (Hold + Clear), mais non terminé ni tronqué
        expect(service.canSendData, isFalse);
        expect(framesWritten.length, 2);
        expect(completed, isFalse);

        // Les lunettes envoient 0x01 (CAN_SEND) -> reprise immédiate des trames restantes (Text + Flush)
        service.handleFlowControlByte(0x01);
        await future;

        expect(service.canSendData, isTrue);
        expect(completed, isTrue);
        expect(framesWritten.length, 4); // Hold, Clear, Text, Flush

        await service.dispose();
      },
    );
  });
}
