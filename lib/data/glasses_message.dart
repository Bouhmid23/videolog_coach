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

  /// Longueur maximale du texte : police 2 (35 px de haut), 14 caractères par ligne et 6 lignes au plus,
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

/// Découpe [ascii] (déjà passé par [toGlassesAscii]) en lignes d'au plus [maxChars] caractères,
/// en coupant aux espaces ; un mot plus long qu'une ligne est coupé. Au plus [maxLines] lignes :
/// au-delà, la dernière est tronquée par `..`.
List<String> wrapGlassesText(
  String ascii, {
  int maxChars = GlassesLayout.charsPerLine,
  int maxLines = GlassesLayout.maxLines,
}) {
  final lines = <String>[];
  var current = '';

  void flush() {
    if (current.isNotEmpty) lines.add(current);
    current = '';
  }

  for (var word in ascii.split(RegExp(r' +')).where((w) => w.isNotEmpty)) {
    while (word.length > maxChars) {
      flush();
      lines.add(word.substring(0, maxChars));
      word = word.substring(maxChars);
    }
    if (current.isEmpty) {
      current = word;
    } else if (current.length + 1 + word.length <= maxChars) {
      current = '$current $word';
    } else {
      flush();
      current = word;
    }
  }
  flush();

  if (lines.length <= maxLines) return lines;
  final kept = lines.sublist(0, maxLines);
  final last = kept.last;
  kept[maxLines - 1] =
      '${last.length > maxChars - 2 ? last.substring(0, maxChars - 2) : last}..';
  return kept;
}

/// Géométrie du message sur l'afficheur ActiveLook (304 × 256 pixels).
///
/// Police 2 : 35 px de haut (documentation ActiveLook : polices 0 à 3 = 24, 24, 35 et 49 px,
/// Computer Modern Sans Serif, proportionnelles). Avec la rotation 4 utilisée par l'appli, le
/// texte est tourné de 180° autour du point d'ancrage (x, y) : il s'étend vers les x décroissants
/// et vers les y décroissants. L'ancrage est donc le coin bas-droit de la boîte de texte dans le
/// repère de l'afficheur ; vu de l'utilisateur, l'écran est retourné (haut de l'écran = y grand).
class GlassesLayout {
  static const int displayW = 304;
  static const int displayH = 256;
  static const int fontId = 2;
  static const int fontHeight = 35;
  static const int lineGap = 4;
  static const int margin = 8;

  /// Ancrage horizontal : marge de 8 px côté utilisateur (le texte s'étend ensuite vers x décroissant).
  static const int anchorX = displayW - margin;

  /// Largeur utile : 288 px, soit environ 14 caractères de police 2 (moyenne ≈ 17 px, majuscules ≈ 20 px).
  static const int charsPerLine = 14;

  static const int linePitch = fontHeight + lineGap;

  /// Lignes qui tiennent entre les marges : (256 - 2 × 8) / 39 = 6.
  static const int maxLines = (displayH - 2 * margin) ~/ linePitch;

  /// y d'ancrage de la ligne [index] (0 = première ligne, en haut pour l'utilisateur).
  static int anchorY(int index) => displayH - margin - index * linePitch;
}
