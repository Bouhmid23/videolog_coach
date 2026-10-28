import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/data/glasses_message.dart';

List<int> _msg(Map<String, Object?> json) => utf8.encode(jsonEncode(json));

void main() {
  group('GlassesMessage.tryParse', () {
    test('message valide', () {
      final m = GlassesMessage.tryParse(
        _msg({'v': 1, 'id': 'c1', 'type': 'text', 'text': ' Allez, plus vite ! ', 'ttl': 5000}),
      );
      expect(m, isNotNull);
      expect(m!.text, 'Allez, plus vite !');
      expect(m.ttl, const Duration(seconds: 5));
      expect(m.id, 'c1');
    });

    test('ttl absent : 5 s ; ttl borné entre 1 s et 10 s', () {
      expect(GlassesMessage.tryParse(_msg({'v': 1, 'type': 'text', 'text': 'a'}))!.ttl, const Duration(seconds: 5));
      expect(GlassesMessage.tryParse(_msg({'v': 1, 'type': 'text', 'text': 'a', 'ttl': 99999}))!.ttl, const Duration(seconds: 10));
      expect(GlassesMessage.tryParse(_msg({'v': 1, 'type': 'text', 'text': 'a', 'ttl': 1}))!.ttl, const Duration(seconds: 1));
    });

    test('texte tronqué à 100 caractères', () {
      final m = GlassesMessage.tryParse(_msg({'v': 1, 'type': 'text', 'text': 'x' * 150}));
      expect(m!.text.length, 100);
    });

    test('invalides : version, type, texte vide ou absent, JSON cassé, trop gros, mauvais type', () {
      expect(GlassesMessage.tryParse(_msg({'v': 2, 'type': 'text', 'text': 'a'})), isNull);
      expect(GlassesMessage.tryParse(_msg({'v': 1, 'type': 'clear', 'text': 'a'})), isNull);
      expect(GlassesMessage.tryParse(_msg({'v': 1, 'type': 'text', 'text': '   '})), isNull);
      expect(GlassesMessage.tryParse(_msg({'v': 1, 'type': 'text'})), isNull);
      expect(GlassesMessage.tryParse(_msg({'v': 1, 'type': 'text', 'text': 42})), isNull);
      expect(GlassesMessage.tryParse(utf8.encode('pas du json')), isNull);
      expect(GlassesMessage.tryParse(utf8.encode('[1,2]')), isNull);
      expect(GlassesMessage.tryParse(List<int>.filled(2000, 65)), isNull);
      expect(GlassesMessage.tryParse(<int>[]), isNull);
      expect(GlassesMessage.tryParse('texte'), isNull);
    });
  });

  group('toGlassesAscii', () {
    test('accents et ponctuation typographique', () {
      expect(toGlassesAscii('Très bien, écoute ça !'), 'Tres bien, ecoute ca !');
      expect(toGlassesAscii('Où ça ? À côté… « oui » – œuf'), 'Ou ca ? A cote... " oui " - oeuf');
      expect(toGlassesAscii('L’effort'), "L'effort");
    });

    test('retours à la ligne en espaces, caractères inconnus en ?', () {
      expect(toGlassesAscii('a\nb'), 'a b');
      expect(toGlassesAscii('ok 💪'), 'ok ?');
    });

    test('le résultat ne contient que de l\'ASCII imprimable', () {
      final out = toGlassesAscii('Énergie ! Là-bas, ça va très vite… 100 % ✓');
      expect(out.runes.every((r) => r >= 32 && r < 127), isTrue, reason: out);
    });
  });

  group('wrapGlassesText', () {
    test('coupe aux espaces, au plus 17 caractères par ligne', () {
      final lines = wrapGlassesText('Allez plus vite encore un effort pour finir');
      expect(lines, ['Allez plus vite', 'encore un effort', 'pour finir']);
      expect(lines.every((l) => l.length <= 17), isTrue);
    });

    test('un mot plus long qu\'une ligne est coupé', () {
      expect(wrapGlassesText('Anticonstitutionnellement'), ['Anticonstitutionn', 'ellement']);
    });

    test('au plus 8 lignes, la dernière est tronquée par ..', () {
      final lines = wrapGlassesText(List.filled(40, 'mot').join(' '));
      expect(lines.length, 8);
      expect(lines.last.endsWith('..'), isTrue);
      expect(lines.every((l) => l.length <= 17), isTrue);
    });

    test('100 caractères de mots courts tiennent sur 8 lignes sans troncature', () {
      final text = List.filled(25, 'abc').join(' '); // 99 caractères
      final lines = wrapGlassesText(text);
      expect(lines.length, lessThanOrEqualTo(8));
      expect(lines.last.endsWith('..'), isFalse);
    });

    test('texte vide : aucune ligne', () {
      expect(wrapGlassesText(''), isEmpty);
    });
  });
}
