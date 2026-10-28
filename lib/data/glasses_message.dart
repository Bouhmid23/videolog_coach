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

  /// Longueur maximale du texte : police 2, environ 17 caractères par ligne et 8 lignes.
  static const int maxChars = 100;

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
  int maxChars = 17,
  int maxLines = 8,
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
