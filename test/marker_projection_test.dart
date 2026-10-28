import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/presentation/widgets/marker_overlay.dart';

void main() {
  group('projectMarker', () {
    test('même aspect ratio : simple mise à l échelle', () {
      final point = projectMarker(
        const Offset(0.5, 0.5),
        const Size(1280, 720),
        const Size(640, 360),
      );
      expect(point.dx, closeTo(320, 0.01));
      expect(point.dy, closeTo(180, 0.01));
    });

    test('cover recadre horizontalement sans décaler le centre', () {
      // Image 16:9 affichée dans un carré : les côtés sont rognés.
      final center = projectMarker(
        const Offset(0.5, 0.5),
        const Size(1920, 1080),
        const Size(400, 400),
      );
      expect(center.dx, closeTo(200, 0.01));
      expect(center.dy, closeTo(200, 0.01));

      final left = projectMarker(
        const Offset(0, 0.5),
        const Size(1920, 1080),
        const Size(400, 400),
      );
      // La source visible commence à x = (1920 - 1080) / 2 = 420 px.
      expect(left.dx, closeTo(-420 / 1080 * 400, 0.01));
    });

    test('le miroir inverse x', () {
      final direct = projectMarker(
        const Offset(0.25, 0.5),
        const Size(1000, 1000),
        const Size(1000, 1000),
      );
      final mirrored = projectMarker(
        const Offset(0.25, 0.5),
        const Size(1000, 1000),
        const Size(1000, 1000),
        mirrorX: true,
      );
      expect(direct.dx, closeTo(250, 0.01));
      expect(mirrored.dx, closeTo(750, 0.01));
      expect(mirrored.dy, closeTo(direct.dy, 0.01));
    });
  });
}
