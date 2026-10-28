import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/data/posture_codec.dart';

/// Décode x et y image (12 bits chacun, plage [-0.5, 1.5]) du point [index] d'un paquet v7.
({double x, double y}) _imagePoint(Uint8List p, int index) {
  final o = PostureCodec.headerSize + index * PostureCodec.pointSize;
  final qx = (p[o] << 4) | (p[o + 1] >> 4);
  final qy = ((p[o + 1] & 0xF) << 8) | p[o + 2];
  double dq(int q) => q / 4095 * 2 - 0.5;
  return (x: dq(qx), y: dq(qy));
}

List<PoseLandmark> _pose(double Function(int) x, double Function(int) y) => [
      for (final type in LandmarkType.values)
        PoseLandmark(type: type, x: x(type.value), y: y(type.value), visibility: 1),
    ];

Uint8List _encode(List<PoseLandmark> landmarks, Size size) => PostureCodec.encode(
      label: 'assis',
      confidence: 1,
      landmarks: landmarks,
      worldLandmarks: const [],
      frameSize: size,
      seq: 1,
      timestampMs: 0,
    );

void main() {
  const size = Size(240, 320);

  test('pose normalisée entièrement dans le cadre : points conservés', () {
    final p = _encode(_pose((i) => 0.2 + i * 0.01, (i) => 0.1 + i * 0.02), size);
    final nose = _imagePoint(p, 0);
    expect(nose.x, closeTo(0.2, 0.001));
    expect(nose.y, closeTo(0.1, 0.001));
  });

  test('sportif assis près du téléphone : chevilles et pieds hors cadre (y > 2) restent normalisés', () {
    // y de 0,5 (nez) à 2,54 (pieds) : régression, tout était divisé par 240 / 320 et écrasé au coin (0, 0).
    final p = _encode(_pose((i) => 0.3, (i) => i == 0 ? 0.51 : (i >= 27 ? 2.54 : 1.0)), size);
    final nose = _imagePoint(p, 0);
    expect(nose.x, closeTo(0.3, 0.001));
    expect(nose.y, closeTo(0.51, 0.001));
    // Les points très hors cadre sont bornés par la plage [-0.5, 1.5].
    expect(_imagePoint(p, 31).y, closeTo(1.5, 0.001));
  });

  test('pose en pixels (au moins un point au-delà du seuil) : divisée par la taille de l\'image', () {
    final p = _encode(_pose((i) => 120.0, (i) => 160.0), size);
    final nose = _imagePoint(p, 0);
    expect(nose.x, closeTo(0.5, 0.001));
    expect(nose.y, closeTo(0.5, 0.001));
  });
}
