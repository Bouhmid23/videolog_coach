import 'dart:convert';

/// Marqueur envoyé par le coach sur le topic LiveKit `marker`.
///
/// Message attendu (JSON UTF-8, canal fiable) :
/// ```json
/// {"v":1,"id":"...","type":"ball","x":0.92,"y":0.47,"ttl":5000,"ts":1793189739144}
/// ```
///
/// `x` et `y` sont des fractions de l'image de la caméra du sportif,
/// **sans miroir**, origine en haut à gauche, entre 0 et 1.
/// `ts` est fourni pour information : il ne sert jamais à l'expiration,
/// l'horloge du mobile fait foi ([receivedAt]).
class BallMarker {
  /// Version du format supportée. Les autres valeurs sont ignorées.
  static const int formatVersion = 1;

  /// Seul type connu aujourd'hui (d'autres outils viendront).
  static const String ballType = 'ball';

  /// Un message plus gros que ça est ignoré sans être décodé.
  static const int maxMessageBytes = 512;

  /// Durée d'affichage par défaut.
  static const int defaultTtlMs = 5000;

  /// Plafond de sécurité, même si le coach demande plus long.
  static const int maxTtlMs = 10000;

  final String id;
  final double x;
  final double y;
  final Duration ttl;
  final DateTime receivedAt;

  const BallMarker({
    required this.id,
    required this.x,
    required this.y,
    required this.ttl,
    required this.receivedAt,
  });

  DateTime get expiresAt => receivedAt.add(ttl);

  Duration get remaining {
    final left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  bool get isExpired => remaining <= Duration.zero;

  /// Fraction de vie restante (1 = vient d'arriver, 0 = expiré).
  double remainingFraction([DateTime? now]) {
    final elapsed = (now ?? DateTime.now()).difference(receivedAt);
    final total = ttl.inMilliseconds;
    if (total <= 0) return 0;
    final left = total - elapsed.inMilliseconds;
    if (left <= 0) return 0;
    return (left / total).clamp(0.0, 1.0);
  }

  /// Décode et valide un message `marker`.
  ///
  /// Retourne `null` si le message est invalide : aucun cas ne doit lever
  /// d'exception (un message malformé est simplement ignoré).
  static BallMarker? tryParse(Object? data, {DateTime? receivedAt}) {
    final received = receivedAt ?? DateTime.now();

    final bytes = _asByteList(data);
    if (bytes == null || bytes.length > maxMessageBytes) return null;

    Map<String, dynamic> map;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return null;
      map = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }

    final version = map['v'];
    if (version is! num || version != formatVersion) return null;

    if (map['type'] != ballType) return null;

    final x = _readUnit(map['x']);
    final y = _readUnit(map['y']);
    if (x == null || y == null) return null;

    final rawTtl = map['ttl'];
    var ttlMs = defaultTtlMs;
    if (rawTtl is num) {
      ttlMs = rawTtl.round();
      if (ttlMs <= 0) ttlMs = defaultTtlMs;
      if (ttlMs > maxTtlMs) ttlMs = maxTtlMs;
    }

    final rawId = map['id'];
    final id = rawId is String && rawId.trim().isNotEmpty
        ? rawId
        : '${received.microsecondsSinceEpoch}-$x-$y';

    return BallMarker(
      id: id,
      x: x,
      y: y,
      ttl: Duration(milliseconds: ttlMs),
      receivedAt: received,
    );
  }

  static List<int>? _asByteList(Object? data) {
    if (data is List<int>) return data;
    if (data is List) {
      // LiveKit expose parfois une liste de valeurs numériques non typées.
      final bytes = <int>[];
      for (final value in data) {
        if (value is! int) return null;
        bytes.add(value);
      }
      return bytes;
    }
    if (data is String) {
      // Tolérance pour les tests / envois texte : on repasse par l'encodage.
      final bytes = utf8.encode(data);
      return bytes.length > maxMessageBytes ? null : bytes;
    }
    return null;
  }

  static double? _readUnit(Object? value) {
    if (value is! num) return null;
    final v = value.toDouble();
    if (v.isNaN || v.isInfinite) return null;
    if (v < 0 || v > 1) return null;
    return v;
  }

  @override
  String toString() =>
      'BallMarker($id, x: $x, y: $y, ttl: ${ttl.inMilliseconds}ms)';
}
