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

    test('contain letterboxe sans décaler le centre', () {
      // Image 4:3 dans un canevas 9:16 : bandes noires en haut et en bas.
      const canvas = Size(405, 720);
      const frame = Size(640, 480);

      final center = projectMarker(
        const Offset(0.5, 0.5),
        frame,
        canvas,
        fit: BoxFit.contain,
      );
      expect(center.dx, closeTo(202.5, 0.01));
      expect(center.dy, closeTo(360, 0.01));

      // La zone affichée fait 405 x 303.75, centrée verticalement.
      final topLeft = projectMarker(
        Offset.zero,
        frame,
        canvas,
        fit: BoxFit.contain,
      );
      expect(topLeft.dx, closeTo(0, 0.01));
      expect(topLeft.dy, closeTo((720 - 303.75) / 2, 0.01));
    });

    test('les 4 ballons de debug restent symétriques', () {
      const frame = Size(640, 480);
      const canvas = Size(480, 360);

      Offset project(double x, double y) => projectMarker(
        Offset(x, y),
        frame,
        canvas,
        fit: BoxFit.contain,
        mirrorX: true,
      );

      final center = project(0.5, 0.5);
      expect(center.dx, closeTo(240, 0.01));
      expect(center.dy, closeTo(180, 0.01));

      // Miroir : (0.1, 0.1) et (0.9, 0.1) s'échangent autour du centre.
      final topLeft = project(0.1, 0.1);
      final topRight = project(0.9, 0.1);
      expect(topLeft.dx, closeTo(240 + (240 - topRight.dx), 0.01));
      expect(topLeft.dy, closeTo(topRight.dy, 0.01));

      final bottomCenter = project(0.5, 0.9);
      expect(bottomCenter.dx, closeTo(center.dx, 0.01));
      expect(bottomCenter.dy, closeTo(324, 0.01));
    });

    group('géométrie terrain (image 3:4, contain)', () {
      // Écran du téléphone : 600,9 × 1006,6. Image 480×640 → affichée
      // 600,9 × 801,2, centrée verticalement (marge de 102,7 px).
      const frame = Size(480, 640);
      const canvas = Size(600.9, 1006.6);
      const topMargin = 102.7;
      const displayedHeight = 801.2;

      Offset project(double x, double y, {bool mirrorX = false}) =>
          projectMarker(
            Offset(x, y),
            frame,
            canvas,
            fit: BoxFit.contain,
            mirrorX: mirrorX,
          );

      test('les 4 positions de debug tombent dans l image affichée', () {
        final center = project(0.5, 0.5);
        expect(center.dx, closeTo(300.45, 0.05));
        expect(center.dy, closeTo(topMargin + displayedHeight / 2, 0.05));

        final topLeft = project(0.1, 0.1);
        expect(topLeft.dx, closeTo(60.09, 0.05));
        expect(topLeft.dy, closeTo(182.82, 0.05));

        final topRight = project(0.9, 0.1);
        expect(topRight.dx, closeTo(540.81, 0.05));
        expect(topRight.dy, closeTo(182.82, 0.05));

        final bottomCenter = project(0.5, 0.9);
        expect(bottomCenter.dx, closeTo(300.45, 0.05));
        expect(bottomCenter.dy, closeTo(823.78, 0.05));
      });

      test('contain garde les bords dans l écran, cover les fait sortir', () {
        final leftContain = project(0.1, 0.5);
        final rightContain = project(0.9, 0.5);
        expect(leftContain.dx, greaterThanOrEqualTo(60));
        expect(rightContain.dx, lessThanOrEqualTo(600.9 - 60));

        final leftCover = projectMarker(
          const Offset(0.1, 0.5),
          frame,
          canvas,
          fit: BoxFit.cover,
        );
        final rightCover = projectMarker(
          const Offset(0.9, 0.5),
          frame,
          canvas,
          fit: BoxFit.cover,
        );
        // Valeurs constatées sur le terrain : x = −1,5 et 602,6.
        expect(leftCover.dx, closeTo(-1.5, 0.2));
        expect(rightCover.dx, closeTo(602.6, 0.2));
      });

      test('le miroir échange gauche et droite', () {
        final left = project(0.1, 0.1);
        final mirroredLeft = project(0.1, 0.1, mirrorX: true);
        expect(mirroredLeft.dx, closeTo(600.9 - left.dx, 0.05));
        expect(mirroredLeft.dy, closeTo(left.dy, 0.05));
      });
    });
  });
}
