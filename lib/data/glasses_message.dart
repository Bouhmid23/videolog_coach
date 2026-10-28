import 'dart:convert';

/// Message texte du coach à afficher sur les lunettes Engo (topic LiveKit `engo_message`).
///
/// ```json
/// {"v":1,"id":"coach-abc","type":"text","text":"Allez, plus vite !","ttl":5000,"ts":1793189739144}
/// ```
class GlassesMessage {
  static const int formatVersion = 1;
  static const String textType = 'text';

  /// Taille maximale du message reçu (octets).
  static const int maxMessageBytes = 1024;

  /// Longueur maximale du texte : police 2 (35 px de haut), 6 lignes au plus de 288 px de large,
  /// avec de la marge pour le retour à la ligne par mots.
  static const int maxChars = 70;

  static const int defaultTtlMs = 5000;
  static const int minTtlMs = 1000;
  static const int maxTtlMs = 10000;

  const GlassesMessage({
    required this.id,
    required this.text,
    required this.ttl,
  });

  final String id;

  /// Texte brut, tronqué à [maxChars].
  final String text;
  final Duration ttl;

  /// Décode et valide un message ; `null` si le message est invalide (ignoré sans erreur).
  static GlassesMessage? tryParse(Object? data) {
    if (data is! List<int> || data.isEmpty || data.length > maxMessageBytes) {
      return null;
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(data));
    } catch (_) {
      return null;
    }
    if (json is! Map<String, dynamic>) return null;
    if (json['v'] != formatVersion || json['type'] != textType) return null;

    final raw = json['text'];
    if (raw is! String) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;

    final ttlRaw = json['ttl'];
    final ttlMs = ttlRaw is num
        ? ttlRaw.toInt().clamp(minTtlMs, maxTtlMs).toInt()
        : defaultTtlMs;
    final id = json['id'];

    return GlassesMessage(
      id: id is String ? id : '',
      text: text.length > maxChars ? text.substring(0, maxChars) : text,
      ttl: Duration(milliseconds: ttlMs),
    );
  }
}

/// Les polices ActiveLook par défaut ne gèrent que l'ASCII : les caractères accentués sont
/// remplacés par leur équivalent sans accent, les autres caractères non pris en charge par `?`.
String toGlassesAscii(String text) {
  const map = <String, String>{
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
    'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A',
    'ç': 'c', 'Ç': 'C',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I',
    'ñ': 'n', 'Ñ': 'N',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U',
    'ý': 'y', 'ÿ': 'y', 'Ý': 'Y',
    'œ': 'oe', 'Œ': 'OE', 'æ': 'ae', 'Æ': 'AE', 'ß': 'ss',
    '’': "'", '‘': "'", '“': '"', '”': '"', '«': '"', '»': '"',
    '–': '-', '—': '-', '…': '...', '€': 'EUR', '°': 'o',
    ' ': ' ', '\t': ' ', '\n': ' ', '\r': ' ',
  };
  final out = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final mapped = map[char];
    if (mapped != null) {
      out.write(mapped);
    } else if (rune >= 32 && rune < 127) {
      out.write(char);
    } else {
      out.write('?');
    }
  }
  return out.toString();
}

/// Largeurs des caractères de la police ActiveLook par défaut (Computer Modern Sans Serif,
/// proportionnelle). L'API ActiveLook n'offre aucune commande pour mesurer un texte ni pour le
/// centrer : la largeur d'une ligne est estimée ici, à partir de largeurs relatives (en em) et d'un
/// seul coefficient [emPx], à ajuster d'après ce qu'on mesure sur les lunettes.
class GlassesFontMetrics {
  /// Taille de l'em en pixels pour la police 2 (35 px de haut, soit environ 0,9 em).
  /// SEULE valeur à ajuster : si les messages paraissent trop à gauche ou à droite, ou coupés,
  /// mesurer la largeur réelle d'une ligne connue et corriger ce coefficient.
  static const double emPx = 39;

  static const List<double> _lower = [
    0.48, 0.52, 0.44, 0.52, 0.44, 0.30, 0.47, 0.52, 0.24, 0.27, 0.50, 0.24, 0.80, //
    0.52, 0.50, 0.52, 0.52, 0.34, 0.38, 0.36, 0.52, 0.50, 0.74, 0.50, 0.50, 0.45,
  ];
  static const List<double> _upper = [
    0.67, 0.56, 0.58, 0.64, 0.50, 0.47, 0.63, 0.64, 0.29, 0.39, 0.62, 0.44, 0.85, //
    0.64, 0.67, 0.50, 0.67, 0.57, 0.49, 0.56, 0.63, 0.67, 0.88, 0.67, 0.67, 0.55,
  ];

  /// Largeur relative (en em) d'un caractère ASCII.
  static double _em(int unit) {
    if (unit >= 97 && unit <= 122) return _lower[unit - 97];
    if (unit >= 65 && unit <= 90) return _upper[unit - 65];
    if (unit >= 48 && unit <= 57) return 0.52;
    switch (String.fromCharCode(unit)) {
      case ' ':
        return 0.33;
      case '.':
      case ',':
      case ':':
      case ';':
      case '!':
      case "'":
        return 0.26;
      case '-':
        return 0.33;
      case '?':
        return 0.45;
      case '(':
      case ')':
        return 0.39;
      default:
        return 0.55;
    }
  }

  /// Largeur estimée de [text] en pixels.
  static double textWidth(String text) {
    var em = 0.0;
    for (final unit in text.codeUnits) {
      em += _em(unit);
    }
    return em * emPx;
  }
}

/// Découpe [ascii] (déjà passé par [toGlassesAscii]) en lignes dont la largeur estimée ne dépasse
/// pas [maxWidth] pixels, en coupant aux espaces ; un mot plus large qu'une ligne est coupé. Au plus
/// [maxLines] lignes : au-delà, la dernière est tronquée par `..`.
List<String> wrapGlassesText(
  String ascii, {
  double maxWidth = GlassesLayout.usableWidth,
  int maxLines = GlassesLayout.maxLines,
}) {
  final lines = <String>[];
  var current = '';

  void flush() {
    if (current.isNotEmpty) lines.add(current);
    current = '';
  }

  for (var word in ascii.split(RegExp(r' +')).where((w) => w.isNotEmpty)) {
    while (GlassesFontMetrics.textWidth(word) > maxWidth) {
      // Mot plus large qu'une ligne : on en détache le plus long préfixe qui tient.
      var cut = word.length - 1;
      while (cut > 1 && GlassesFontMetrics.textWidth(word.substring(0, cut)) > maxWidth) {
        cut--;
      }
      flush();
      lines.add(word.substring(0, cut));
      word = word.substring(cut);
    }
    if (current.isEmpty) {
      current = word;
    } else if (GlassesFontMetrics.textWidth('$current $word') <= maxWidth) {
      current = '$current $word';
    } else {
      flush();
      current = word;
    }
  }
  flush();

  if (lines.length <= maxLines) return lines;
  final kept = lines.sublist(0, maxLines);
  var last = kept.last;
  while (last.length > 1 && GlassesFontMetrics.textWidth('$last..') > maxWidth) {
    last = last.substring(0, last.length - 1);
  }
  kept[maxLines - 1] = '$last..';
  return kept;
}

/// Une ligne de texte à envoyer aux lunettes : texte et point d'ancrage dans le repère de l'afficheur.
class GlassesLine {
  const GlassesLine(this.text, this.x, this.y);

  final String text;
  final int x;
  final int y;
}

/// Géométrie du message sur l'afficheur ActiveLook (304 × 256 pixels).
///
/// Police 2 : 35 px de haut (documentation ActiveLook : polices 0 à 3 = 24, 24, 35 et 49 px,
/// Computer Modern Sans Serif, proportionnelles). Avec la rotation 4 utilisée par l'appli, le
/// texte est tourné de 180° autour du point d'ancrage (x, y) : il s'étend vers les x décroissants
/// et vers les y décroissants. L'ancrage est donc le coin bas-droit de la boîte de texte dans le
/// repère de l'afficheur ; vu de l'utilisateur, l'écran est retourné (haut gauche de l'écran =
/// x et y grands).
///
/// Le message est centré à partir de son contenu : verticalement d'après le nombre de lignes,
/// horizontalement d'après la largeur estimée de chaque ligne ([GlassesFontMetrics]).
class GlassesLayout {
  static const int displayW = 304;
  static const int displayH = 256;
  static const int fontId = 2;
  static const int fontHeight = 35;
  static const int lineGap = 4;
  static const int margin = 8;

  /// Largeur utile entre les marges.
  static const double usableWidth = (displayW - 2 * margin) * 1.0;

  static const int linePitch = fontHeight + lineGap;

  /// Lignes qui tiennent entre les marges : (256 - 2 × 8) / 39 = 6.
  static const int maxLines = (displayH - 2 * margin) ~/ linePitch;

  /// Place [lines] au centre de l'afficheur : bloc centré verticalement, chaque ligne centrée
  /// horizontalement d'après sa largeur estimée.
  static List<GlassesLine> place(List<String> lines) {
    if (lines.isEmpty) return const [];
    final count = lines.length.clamp(1, maxLines).toInt();
    final blockHeight = count * fontHeight + (count - 1) * lineGap;
    final top = (displayH - blockHeight) / 2; // haut du bloc, côté utilisateur

    final placed = <GlassesLine>[];
    for (var i = 0; i < count; i++) {
      final width = GlassesFontMetrics.textWidth(lines[i]).clamp(0.0, usableWidth).toDouble();
      final viewerLeft = (displayW - width) / 2;
      final viewerTop = top + i * linePitch;
      placed.add(GlassesLine(
        lines[i],
        (displayW - viewerLeft).round(),
        (displayH - viewerTop).round(),
      ));
    }
    return placed;
  }
}
