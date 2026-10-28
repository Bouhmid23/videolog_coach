import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/data/frame_geometry.dart';

void main() {
  group('frameSizeForOrientation', () {
    test('échange largeur et hauteur en portrait (capteur 4:3)', () {
      final upright = frameSizeForOrientation(
        const Size(640, 480),
        portrait: true,
      );
      expect(upright, const Size(480, 640));
      expect(upright.width / upright.height, closeTo(portraitFrameRatio, 1e-9));
    });

    test('laisse une image déjà en portrait inchangée', () {
      expect(
        frameSizeForOrientation(const Size(480, 640), portrait: true),
        const Size(480, 640),
      );
      expect(
        frameSizeForOrientation(const Size(240, 320), portrait: true),
        const Size(240, 320),
      );
    });

    test('ne touche à rien en paysage', () {
      expect(
        frameSizeForOrientation(const Size(640, 480), portrait: false),
        const Size(640, 480),
      );
      expect(
        frameSizeForOrientation(const Size(480, 640), portrait: false),
        const Size(480, 640),
      );
    });

    test('240x320 et 360x480 donnent le même ratio', () {
      final small = frameSizeForOrientation(
        const Size(240, 320),
        portrait: true,
      );
      final large = frameSizeForOrientation(
        const Size(360, 480),
        portrait: true,
      );
      expect(
        small.width / small.height,
        closeTo(large.width / large.height, 1e-9),
      );
    });
  });
}
