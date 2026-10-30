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
