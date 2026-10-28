import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/data/frame_geometry.dart';
import 'package:videolog_coach/presentation/widgets/marker_overlay.dart';

void main() {
  test('cadre paysage 640x480 sur écran portrait : remis en portrait 480x640', () {
    expect(
      orientFrameToScreen(const Size(640, 480), portraitScreen: true),
      const Size(480, 640),
    );
  });

  test('cadre déjà portrait sur écran portrait : inchangé', () {
    expect(
      orientFrameToScreen(const Size(240, 320), portraitScreen: true),
      const Size(240, 320),
    );
  });

  test('cadre portrait sur écran paysage : remis en paysage', () {
    expect(
      orientFrameToScreen(const Size(480, 640), portraitScreen: false),
      const Size(640, 480),
    );
  });

  test('cadre vide ou carré : inchangé', () {
    expect(orientFrameToScreen(Size.zero, portraitScreen: true), Size.zero);
    expect(
      orientFrameToScreen(const Size(500, 500), portraitScreen: true),
      const Size(500, 500),
    );
  });

  test('régression : le cadre paysage fausse les bords du ballon, le cadre orienté les place juste', () {
    const screen = Size(411, 890);
    const normalized = Offset(0.8, 0.5);

    final bad = projectMarker(normalized, const Size(640, 480), screen);
    final good = projectMarker(
      normalized,
      orientFrameToScreen(const Size(640, 480), portraitScreen: true),
      screen,
    );
    final reference = projectMarker(normalized, const Size(480, 640), screen);

    expect(good.dx, closeTo(reference.dx, 0.01));
    expect(good.dy, closeTo(reference.dy, 0.01));
    expect((bad.dx - reference.dx).abs(), greaterThan(100));
    // Le centre et la verticale étaient déjà justes avec le mauvais cadre.
    final centerBad = projectMarker(const Offset(0.5, 0.5), const Size(640, 480), screen);
    final centerGood = projectMarker(const Offset(0.5, 0.5), const Size(480, 640), screen);
    expect(centerBad.dx, closeTo(centerGood.dx, 0.01));
  });
}
