import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/data/participant_display_name.dart';

void main() {
  group('displayNameFromMetadata', () {
    test('lit la clé display_name', () {
      expect(displayNameFromMetadata('{"display_name":"Ahmed B."}'), 'Ahmed B.');
    });

    test('accepte les variantes de clé', () {
      expect(displayNameFromMetadata('{"displayName":"Sara"}'), 'Sara');
      expect(displayNameFromMetadata('{"name":"Karim"}'), 'Karim');
    });

    test('ignore un JSON sans nom', () {
      expect(displayNameFromMetadata('{"role":"coach"}'), isNull);
      expect(displayNameFromMetadata('{"display_name":"   "}'), isNull);
    });

    test('tolère une metadata texte brute', () {
      expect(displayNameFromMetadata('Coach Ahmed'), 'Coach Ahmed');
    });

    test('ignore une metadata vide ou json invalide', () {
      expect(displayNameFromMetadata(null), isNull);
      expect(displayNameFromMetadata('  '), isNull);
      expect(displayNameFromMetadata('{"display_name":'), isNull);
    });
  });

  test('buildDisplayNameMetadata est relisible', () {
    final raw = buildDisplayNameMetadata('Ahmed B.');
    expect(displayNameFromMetadata(raw), 'Ahmed B.');
  });
}
