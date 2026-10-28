import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/data/ball_marker.dart';

void main() {
  const validJson =
      '{"v":1,"id":"cCSw0rQG3Bh2uk0nzApLE0go3O72-mvs2vdzc","type":"ball",'
      '"x":0.9232,"y":0.4755,"ttl":5000,"ts":1793189739144}';

  BallMarker? parse(String json) =>
      BallMarker.tryParse(utf8.encode(json), receivedAt: DateTime(2026));

  group('BallMarker.tryParse', () {
    test('accepte un message valide', () {
      final marker = parse(validJson);
      expect(marker, isNotNull);
      expect(marker!.x, closeTo(0.9232, 1e-9));
      expect(marker.y, closeTo(0.4755, 1e-9));
      expect(marker.ttl, const Duration(milliseconds: 5000));
      expect(marker.id, 'cCSw0rQG3Bh2uk0nzApLE0go3O72-mvs2vdzc');
    });

    test('ignore une version inconnue', () {
      expect(parse(validJson.replaceFirst('"v":1', '"v":2')), isNull);
    });

    test('ignore un type inconnu', () {
      expect(parse(validJson.replaceFirst('"ball"', '"arrow"')), isNull);
    });

    test('ignore des coordonnées hors image', () {
      expect(parse(validJson.replaceFirst('0.9232', '1.2')), isNull);
      expect(parse(validJson.replaceFirst('0.4755', '-0.1')), isNull);
    });

    test('ignore un JSON invalide', () {
      expect(parse('{"v":1,"type":"ball",'), isNull);
    });

    test('ignore un message trop volumineux', () {
      final payload = '{"v":1,"id":"${'a' * 600}",'
          '"type":"ball","x":0.5,"y":0.5,"ttl":5000}';
      expect(utf8.encode(payload).length, greaterThan(512));
      expect(parse(payload), isNull);
    });

    test('plafonne le ttl à 10 s', () {
      final marker = parse(validJson.replaceFirst('5000', '30000'));
      expect(marker?.ttl, const Duration(milliseconds: 10000));
    });

    test('ttl par défaut si absent ou invalide', () {
      final marker = parse(validJson.replaceFirst('"ttl":5000,', ''));
      expect(marker?.ttl,
          const Duration(milliseconds: BallMarker.defaultTtlMs));
    });

    test('expire à partir de l horloge locale', () {
      final marker = BallMarker.tryParse(
        utf8.encode(validJson),
        receivedAt: DateTime.now().subtract(const Duration(seconds: 3)),
      )!;
      expect(marker.isExpired, isFalse);
      expect(marker.remainingFraction(), closeTo(0.4, 0.05));

      final expired = BallMarker.tryParse(
        utf8.encode(validJson),
        receivedAt: DateTime.now().subtract(const Duration(seconds: 6)),
      )!;
      expect(expired.isExpired, isTrue);
    });
  });
}
