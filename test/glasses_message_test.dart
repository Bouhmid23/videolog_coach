import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/data/glasses_message.dart';

List<int> _msg(Map<String, Object?> json) => utf8.encode(jsonEncode(json));

void main() {
  _layoutTests();
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

    test('texte tronqué à 70 caractères', () {
      final m = GlassesMessage.tryParse(_msg({'v': 1, 'type': 'text', 'text': 'x' * 150}));
      expect(m!.text.length, 70);
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
    test('coupe aux espaces, au plus 14 caractères par ligne', () {
      final lines = wrapGlassesText('Allez plus vite encore un effort pour finir');
      expect(lines, ['Allez plus', 'vite encore un', 'effort pour', 'finir']);
      expect(lines.every((l) => l.length <= 14), isTrue);
    });

    test('un mot plus long qu\'une ligne est coupé', () {
      expect(wrapGlassesText('Anticonstitutionnellement'), ['Anticonstituti', 'onnellement']);
    });

    test('au plus 6 lignes, la dernière est tronquée par ..', () {
      final lines = wrapGlassesText(List.filled(40, 'mot').join(' '));
      expect(lines.length, 6);
      expect(lines.last.endsWith('..'), isTrue);
      expect(lines.every((l) => l.length <= 14), isTrue);
    });

    test('70 caractères de mots courts tiennent sur 6 lignes sans troncature', () {
      final text = List.filled(17, 'abc').join(' '); // 67 caractères
      final lines = wrapGlassesText(text);
      expect(lines.length, lessThanOrEqualTo(6));
      expect(lines.last.endsWith('..'), isFalse);
    });

    test('texte vide : aucune ligne', () {
      expect(wrapGlassesText(''), isEmpty);
    });
  });
}

void _layoutTests() {
  group('GlassesLayout', () {
    test('6 lignes de police 2 tiennent entre les marges', () {
      expect(GlassesLayout.maxLines, 6);
      for (var i = 0; i < GlassesLayout.maxLines; i++) {
        final bottom = GlassesLayout.anchorY(i);
        final top = bottom - GlassesLayout.fontHeight;
        expect(top, greaterThanOrEqualTo(GlassesLayout.margin), reason: 'ligne $i coupée en haut');
        expect(bottom, lessThanOrEqualTo(GlassesLayout.displayH - GlassesLayout.margin), reason: 'ligne $i coupée en bas');
      }
    });

    test('la première ligne ne laisse plus que la partie haute du texte visible (régression « hello world »)', () {
      // Ancien calcul : y = 8 pour la première ligne => boîte [8 - 35, 8] : 27 px sur 35 hors de l\'écran.
      expect(8 - GlassesLayout.fontHeight, lessThan(0));
      // Nouveau calcul : boîte entièrement à l\'écran.
      expect(GlassesLayout.anchorY(0) - GlassesLayout.fontHeight, greaterThanOrEqualTo(0));
    });

    test('les lignes ne se chevauchent pas', () {
      expect(GlassesLayout.linePitch, greaterThanOrEqualTo(GlassesLayout.fontHeight));
    });
  });
}
