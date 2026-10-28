import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_pose_detection/flutter_pose_detection.dart';

/// Codec binaire v7 pour le topic `posture` (émission uniquement).
///
/// Paquet = en-tête de 11 octets + 33 points × 8 octets = 275 octets.
///
/// En-tête (big-endian) :
///   0      version (7)
///   1      code du label (0 debout, 1 assis, 2 allongé, 255 inconnu, 254 pose perdue)
///   2      confiance (0..255, 0 = inconnue)
///   3-4    seq (uint16, modulo 65536)
///   5-6    timestamp ms (uint16, modulo 65536)
///   7-8    largeur de frame (uint16)
///   9-10   hauteur de frame (uint16)
///
/// Extension optionnelle « gravité » (6 octets, après les 33 points, paquet de 281 octets) :
///   3 × int16 big-endian = direction « haut » dans les axes des worldLandmarks
///   (x droite, y bas, z s'éloignant de la caméra), vecteur unitaire × 30000.
///   La version reste 7 : un décodeur qui ignore les octets en trop lit le paquet comme avant.
///
/// Point (8 octets, ordre fixe défini par [sent]) :
///   x image 12 bits | y image 12 bits | world x/y/z 12 bits chacun | visibilité 4 bits
///   image x/y : plage normalisée [-0.5, 1.5]
///   world x/y/z : mètres, plage [-1.5, 1.5], MediaPipe world landmarks centrés au bassin
///   visibilité : raw / 15
class PostureCodec {
  PostureCodec._();

  static const int version = 7;
  static const int headerSize = 11;
  static const int pointSize = 8;
  static const int unknownLabelCode = 255;
  static const int lostLabelCode = 254;

  /// Le z image de MediaPipe (format v6) est relatif et à l'échelle de x,
  /// pas une distance métrique. Le format v7 transmet séparément les world landmarks.
  static const double worldRange = 1.5;

  /// Landmarks transmis : les 33 points MediaPipe / ML Kit, dans l'ordre.
  /// L'ordre est partagé avec le décodeur web : ne pas le modifier seul.
  static const List<int> sent = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, //                visage
    11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, //  épaules -> pouces
    23, 24, 25, 26, 27, 28, 29, 30, 31, 32, //          hanches -> pieds
  ];

  static final int packetSize = headerSize + sent.length * pointSize; // 275
  static const int gravitySize = 6;

  /// Au-delà de cette valeur (en x ou y), les coordonnées d'une pose sont lues en pixels.
  static const double pixelThreshold = 10;

  /// Vrai si les coordonnées de la pose sont en pixels (au moins un x ou y au-delà de
  /// [pixelThreshold]). Décision prise une fois par pose, jamais point par point :
  /// un point hors cadre (x ou y légèrement hors de [0, 1]) reste normalisé.
  static bool isPixelSpace(Iterable<PoseLandmark> landmarks) =>
      landmarks.any((l) => l.x.abs() > pixelThreshold || l.y.abs() > pixelThreshold);
  static const double gravityScale = 30000;

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

  static int _quantizeWorld(double n) {
    if (!n.isFinite) return 2048;
    return (((n / worldRange + 1) / 2).clamp(0.0, 1.0) * 4095).round();
  }

  static int _clampU16(double value) =>
      value.isFinite ? value.clamp(0, 65535).round() : 0;

  /// Encode une frame de posture.
  static Uint8List encode({
    required String label,
    required double? confidence,
    required List<PoseLandmark> landmarks,
    required List<WorldLandmark> worldLandmarks,
    required Size frameSize,
    required int seq,
    required int timestampMs,
    List<double>? gravity,
  }) {
    final byType = <int, PoseLandmark>{
      for (final l in landmarks) l.type.value: l,
    };
    final worldByType = <int, WorldLandmark>{
      for (final l in worldLandmarks) l.typeIndex: l,
    };

    final List<double>? up =
        (gravity != null && gravity.length == 3 && gravity.every((g) => g.isFinite))
            ? gravity
            : null;
    final bd = ByteData(packetSize + (up != null ? gravitySize : 0));
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
    // normalisé, ou pixels. Le plugin renvoie des coordonnées normalisées, mais
    // les points hors cadre (jambes d'un sportif assis près du téléphone)
    // dépassent facilement 2 (chevilles à y ≈ 2,4) : le seuil ne doit donc pas
    // être trop bas, sinon toute la pose est divisée par la taille de l'image
    // et s'écrase au coin (0, 0). Une pose en pixels, elle, dépasse toujours
    // [pixelThreshold] pour au moins un point visible.
    final normalized = !isPixelSpace(landmarks);
    final fw = frameSize.width > 0 ? frameSize.width : 1.0;
    final fh = frameSize.height > 0 ? frameSize.height : 1.0;

    var o = headerSize;
    for (final type in sent) {
      final lm = byType[type];
      var x = 0, y = 0, wx = 2048, wy = 2048, wz = 2048, v = 0;
      if (lm != null) {
        final nx = normalized ? lm.x : lm.x / fw;
        final ny = normalized ? lm.y : lm.y / fh;
        x = _quantize(nx);
        y = _quantize(ny);
      }
      final world = worldByType[type];
      if (lm != null) {
        v = (lm.visibility.clamp(0.0, 1.0) * 15).round();
      }
      if (world != null) {
        wx = _quantizeWorld(world.x);
        wy = _quantizeWorld(world.y);
        wz = _quantizeWorld(world.z);
      }
      bd.setUint8(o, x >> 4);
      bd.setUint8(o + 1, ((x & 0xF) << 4) | (y >> 8));
      bd.setUint8(o + 2, y & 0xFF);
      bd.setUint8(o + 3, wx >> 4);
      bd.setUint8(o + 4, ((wx & 0xF) << 4) | (wy >> 8));
      bd.setUint8(o + 5, wy & 0xFF);
      bd.setUint8(o + 6, wz >> 4);
      bd.setUint8(o + 7, ((wz & 0xF) << 4) | (v & 0xF));
      o += pointSize;
    }

    if (up != null) {
      for (var i = 0; i < 3; i++) {
        bd.setInt16(
          o + i * 2,
          (up[i].clamp(-1.0, 1.0) * gravityScale).round(),
        );
      }
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
