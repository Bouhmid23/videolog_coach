import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/data/ball_marker.dart';
import 'package:videolog_coach/presentation/widgets/marker_overlay.dart';

void main() {
  testWidgets('affiche un ballon centré sur la position normalisée', (
    tester,
  ) async {
    final markers = ValueNotifier<List<BallMarker>>(const []);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: MarkerOverlay(
              markers: markers,
              frameSize: const Size(1000, 1000),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(SvgPicture), findsNothing);

    markers.value = [
      BallMarker(
        id: 'ball-1',
        x: 0.25,
        y: 0.5,
        ttl: const Duration(seconds: 5),
        receivedAt: DateTime.now(),
      ),
    ];
    await tester.pump();

    expect(find.byType(SvgPicture), findsOneWidget);

    // Même aspect ratio que l'image : centre = (100, 200) dans un canevas
    // 400x400 ; diamètre = 10 % de 400 = 40.
    final positioned = tester.widget<Positioned>(find.byType(Positioned).first);
    expect(positioned.left, closeTo(80, 0.01));
    expect(positioned.top, closeTo(180, 0.01));
    expect(positioned.width, closeTo(40, 0.01));
    expect(positioned.height, closeTo(40, 0.01));

    // Retrait : plus aucun ballon.
    markers.value = const [];
    await tester.pump();
    expect(find.byType(SvgPicture), findsNothing);

    await tester.pumpWidget(const SizedBox());
    markers.dispose();
  });

  testWidgets('les quatre ballons de debug tombent aux positions attendues', (
    tester,
  ) async {
    final now = DateTime.now();
    final markers = ValueNotifier<List<BallMarker>>([
      BallMarker(
        id: 'debug-centre',
        x: 0.5,
        y: 0.5,
        ttl: const Duration(seconds: 10),
        receivedAt: now,
      ),
      BallMarker(
        id: 'debug-haut-gauche',
        x: 0.1,
        y: 0.1,
        ttl: const Duration(seconds: 10),
        receivedAt: now,
      ),
      BallMarker(
        id: 'debug-haut-droite',
        x: 0.9,
        y: 0.1,
        ttl: const Duration(seconds: 10),
        receivedAt: now,
      ),
      BallMarker(
        id: 'debug-bas-centre',
        x: 0.5,
        y: 0.9,
        ttl: const Duration(seconds: 10),
        receivedAt: now,
      ),
    ]);

    // Écran 600,9 × 1006,6 et image 3:4 (480×640) : en contain l'image est
    // affichée 600,9 × 801,2, décalée de 102,7 px vers le bas.
    tester.view.physicalSize = const Size(601, 1007);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600.9,
              height: 1006.6,
              child: MarkerOverlay(
                markers: markers,
                frameSize: const Size(480, 640),
                fit: BoxFit.contain,
                mirrorX: true,
                debugFrameCandidates: const [
                  FrameCandidate('publication (pivoté)', Size(480, 640)),
                  FrameCandidate('capture (pivoté)', Size(480, 640)),
                  FrameCandidate('pose', Size(480, 640)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final positions = tester
        .widgetList<Positioned>(
          find.descendant(
            of: find.byType(MarkerOverlay),
            matching: find.byType(Positioned),
          ),
        )
        .toList();
    expect(positions, hasLength(4));

    const diameter = 600.9 * MarkerOverlay.diameterRatio;
    const half = diameter / 2;

    // Miroir actif : (0.1, 0.1) et (0.9, 0.1) s'échangent.
    final expected = <int, Offset>{
      0: const Offset(300.45, 102.7 + 801.2 / 2),
      1: const Offset(600.9 - 60.09, 182.82),
      2: const Offset(60.09, 182.82),
      3: const Offset(300.45, 823.78),
    };

    expected.forEach((index, center) {
      expect(positions[index].left, closeTo(center.dx - half, 0.05));
      expect(positions[index].top, closeTo(center.dy - half, 0.05));
      expect(positions[index].width, closeTo(diameter, 0.01));
      expect(positions[index].height, closeTo(diameter, 0.01));
    });

    await tester.pumpWidget(const SizedBox());
    markers.dispose();
  });

  testWidgets('ne dessine rien sans taille d image connue', (tester) async {
    final markers = ValueNotifier<List<BallMarker>>([
      BallMarker(
        id: 'ball-1',
        x: 0.5,
        y: 0.5,
        ttl: const Duration(seconds: 5),
        receivedAt: DateTime.now(),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: MarkerOverlay(markers: markers, frameSize: null),
          ),
        ),
      ),
    );

    expect(find.byType(SvgPicture), findsNothing);

    await tester.pumpWidget(const SizedBox());
    markers.dispose();
  });
}
