import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_pose_detection/flutter_pose_detection.dart';

/// Codec binaire v6 pour le topic `posture` (émission uniquement).
///
/// Paquet = en-tête de 11 octets + 33 points × 5 octets = 176 octets.
///
/// En-tête (big-endian) :
///   0      version (6)
///   1      code du label (0 debout, 1 assis, 2 allongé, 255 inconnu, 254 pose perdue)
///   2      confiance (0..255, 0 = inconnue)
///   3-4    seq (uint16, modulo 65536)
///   5-6    timestamp ms (uint16, modulo 65536)
///   7-8    largeur de frame (uint16)
///   9-10   hauteur de frame (uint16)
///
/// Point (5 octets = 40 bits, ordre fixe défini par [sent]) :
///   x 12 bits | y 12 bits | z 12 bits | visibilité 4 bits
///   x, y : plage normalisée [-0.5, 1.5]  ->  valeur = raw / 4095 * 2 - 0.5
///   z    : plage [-zRange, zRange]       ->  valeur = (raw / 4095 * 2 - 1) * zRange
///   visibilité : raw / 15
class PostureCodec {
  PostureCodec._();

  static const int version = 6;
  static const int headerSize = 11;
  static const int pointSize = 5;
  static const int unknownLabelCode = 255;
  static const int lostLabelCode = 254;

  /// Plage de la profondeur z (MediaPipe : relative au plan des hanches,
  /// négative = vers la caméra). Identique à Z_RANGE côté web.
  static const double zRange = 1.0;

  /// Landmarks transmis : les 33 points MediaPipe / ML Kit, dans l'ordre.
  /// L'ordre est partagé avec le décodeur web : ne pas le modifier seul.
  static const List<int> sent = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, //                visage
    11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, //  épaules -> pouces
    23, 24, 25, 26, 27, 28, 29, 30, 31, 32, //          hanches -> pieds
  ];

  static final int packetSize = headerSize + sent.length * pointSize; // 176

  static const Map<String, int> _labelToCode = {
    'debout': 0,
    'assis': 1,
    'allongé': 2,
    'allonge': 2,
  };

  static int labelToCode(String label) =>
      _labelToCode[label.toLowerCase()] ?? unknownLabelCode;

  /// Quantifie x ou y (normalisé) sur 12 bits, plage [-0.5, 1.5].
  /// Les points hors cadre (fréquents sur les membres coupés) sont conservés
  /// au lieu d'être écrasés sur le bord de l'image.
  static int _quantize(double n) {
    if (!n.isFinite) return 0;
    return (((n + 0.5) / 2).clamp(0.0, 1.0) * 4095).round();
  }

  /// Quantifie z sur 12 bits, plage [-zRange, zRange].
  static int _quantizeZ(double z) {
    if (!z.isFinite) return 2048;
    return (((z / zRange + 1) / 2).clamp(0.0, 1.0) * 4095).round();
  }

  static int _clampU16(double value) =>
      value.isFinite ? value.clamp(0, 65535).round() : 0;

  /// Encode une frame de posture.
  static Uint8List encode({
    required String label,
    required double? confidence,
    required List<PoseLandmark> landmarks,
    required Size frameSize,
    required int seq,
    required int timestampMs,
  }) {
    final byType = <int, PoseLandmark>{
      for (final l in landmarks) l.type.value: l,
    };

    final bd = ByteData(packetSize);
    bd.setUint8(0, version);
    bd.setUint8(1, labelToCode(label));
    bd.setUint8(
      2,
      confidence == null ? 0 : (confidence.clamp(0.0, 1.0) * 255).round(),
    );
    bd.setUint16(3, seq & 0xFFFF);
    bd.setUint16(5, timestampMs & 0xFFFF);
    bd.setUint16(7, _clampU16(frameSize.width));
    bd.setUint16(9, _clampU16(frameSize.height));

    // Espace des coordonnées décidé UNE fois par pose (et non par coordonnée) :
    // normalisé, ou pixels. Une pose en pixels a toujours au moins une
    // coordonnée > 2.
    final normalized =
    landmarks.every((l) => l.x.abs() <= 2 && l.y.abs() <= 2);
    final fw = frameSize.width > 0 ? frameSize.width : 1.0;
    final fh = frameSize.height > 0 ? frameSize.height : 1.0;

    var o = headerSize;
    for (final type in sent) {
      final lm = byType[type];
      var x = 0, y = 0, z = 2048, v = 0;
      if (lm != null) {
        final nx = normalized ? lm.x : lm.x / fw;
        final ny = normalized ? lm.y : lm.y / fh;
        final nz = normalized ? lm.z : lm.z / fw;
        x = _quantize(nx);
        y = _quantize(ny);
        z = _quantizeZ(nz);
        v = (lm.visibility.clamp(0.0, 1.0) * 15).round();
      }
      bd.setUint8(o, x >> 4);
      bd.setUint8(o + 1, ((x & 0xF) << 4) | (y >> 8));
      bd.setUint8(o + 2, y & 0xFF);
      bd.setUint8(o + 3, z >> 4);
      bd.setUint8(o + 4, ((z & 0xF) << 4) | (v & 0xF));
      o += pointSize;
    }

    return bd.buffer.asUint8List();
  }

  /// Paquet « pose perdue » (11 octets) : le web efface le squelette.
  /// [timestampMs] est l'heure de capture, comme pour une pose valide.
  static Uint8List encodeLost(int seq, {int? timestampMs}) {
    final bd = ByteData(headerSize);
    bd.setUint8(0, version);
    bd.setUint8(1, lostLabelCode);
    bd.setUint16(3, seq & 0xFFFF);
    if (timestampMs != null) {
      bd.setUint16(5, timestampMs & 0xFFFF);
    }
    return bd.buffer.asUint8List();
  }
}
