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
    test('chaque ligne tient dans la largeur utile, le texte est conservé', () {
      const text = 'Allez plus vite encore un effort pour finir';
      final lines = wrapGlassesText(text);
      expect(lines.every((l) => GlassesFontMetrics.textWidth(l) <= GlassesLayout.usableWidth), isTrue);
      expect(lines.join(' '), text);
    });

    test('les lettres étroites en laissent passer plus que les lettres larges', () {
      expect(wrapGlassesText('i' * 20), hasLength(1));
      expect(wrapGlassesText('W' * 10), hasLength(2));
    });

    test('un mot plus large qu\'une ligne est coupé sans perdre de lettre', () {
      const word = 'Anticonstitutionnellement';
      final lines = wrapGlassesText(word);
      expect(lines.length, greaterThan(1));
      expect(lines.join(), word);
      expect(lines.every((l) => GlassesFontMetrics.textWidth(l) <= GlassesLayout.usableWidth), isTrue);
    });

    test('au plus 6 lignes, la dernière est tronquée par .. et tient dans la largeur', () {
      final lines = wrapGlassesText(List.filled(40, 'mot').join(' '));
      expect(lines.length, 6);
      expect(lines.last.endsWith('..'), isTrue);
      expect(GlassesFontMetrics.textWidth(lines.last), lessThanOrEqualTo(GlassesLayout.usableWidth));
    });

    test('un message de 70 caractères courants tient sans troncature', () {
      final lines = wrapGlassesText('Plus vite, tiens le rythme, respire bien et garde le dos droit jusqu au bout');
      expect(lines.length, lessThanOrEqualTo(6));
      expect(lines.last.endsWith('..'), isFalse);
    });

    test('texte vide : aucune ligne', () {
      expect(wrapGlassesText(''), isEmpty);
    });
  });
}

void _layoutTests() {
  group('GlassesLayout.place', () {
    double viewerTop(GlassesLine l) => GlassesLayout.displayH - l.y.toDouble();
    double viewerLeft(GlassesLine l) => GlassesLayout.displayW - l.x.toDouble();

    test('texte vide : rien à placer', () {
      expect(GlassesLayout.place(const []), isEmpty);
    });

    test('bloc centré verticalement, quel que soit le nombre de lignes', () {
      for (var n = 1; n <= GlassesLayout.maxLines; n++) {
        final placed = GlassesLayout.place(List.filled(n, 'abc'));
        final top = viewerTop(placed.first);
        final bottom = GlassesLayout.displayH - (viewerTop(placed.last) + GlassesLayout.fontHeight);
        expect((top - bottom).abs(), lessThanOrEqualTo(1.5), reason: '$n ligne(s) : haut $top, bas $bottom');
      }
    });

    test('chaque ligne est centrée horizontalement d\'après sa largeur', () {
      for (final text in ['Hi', 'Hello world', 'Allez plus vite']) {
        final line = GlassesLayout.place([text]).single;
        final width = GlassesFontMetrics.textWidth(text);
        final left = viewerLeft(line);
        final right = GlassesLayout.displayW - left - width;
        expect((left - right).abs(), lessThanOrEqualTo(1.5), reason: '$text : gauche $left, droite $right');
      }
    });

    test('une ligne courte est ancrée plus loin du bord qu\'une ligne longue', () {
      final short = GlassesLayout.place(['Hi']).single;
      final long = GlassesLayout.place(['Hello world']).single;
      expect(viewerLeft(short), greaterThan(viewerLeft(long)));
    });

    test('rien ne dépasse les marges, même avec 6 lignes pleines', () {
      final lines = wrapGlassesText(List.filled(40, 'WW').join(' '));
      for (final line in GlassesLayout.place(lines)) {
        final width = GlassesFontMetrics.textWidth(line.text);
        expect(viewerLeft(line), greaterThanOrEqualTo(GlassesLayout.margin - 1));
        expect(viewerLeft(line) + width, lessThanOrEqualTo(GlassesLayout.displayW - GlassesLayout.margin + 1));
        expect(viewerTop(line), greaterThanOrEqualTo(GlassesLayout.margin - 1));
        expect(viewerTop(line) + GlassesLayout.fontHeight, lessThanOrEqualTo(GlassesLayout.displayH - GlassesLayout.margin + 1));
      }
    });

    test('régression « hello world » : la boîte de texte est entièrement à l\'écran', () {
      final line = GlassesLayout.place(['hello world']).single;
      // Boîte dans le repère de l'afficheur (rotation 4) : [y - hauteur, y].
      expect(line.y - GlassesLayout.fontHeight, greaterThanOrEqualTo(0));
      expect(line.y, lessThanOrEqualTo(GlassesLayout.displayH));
    });

    test('les lignes ne se chevauchent pas', () {
      final placed = GlassesLayout.place(['a', 'b', 'c']);
      expect(viewerTop(placed[1]) - viewerTop(placed[0]), greaterThanOrEqualTo(GlassesLayout.fontHeight));
    });
  });
}
