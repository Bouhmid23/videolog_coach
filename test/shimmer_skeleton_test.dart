import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/presentation/widgets/shimmer_skeleton.dart';

void main() {
  group('ShimmerSkeleton Widgets', () {
    testWidgets('RoomsListSkeleton renders placeholder items', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RoomsListSkeleton(itemCount: 2),
          ),
        ),
      );

      expect(find.byType(ShimmerEffect), findsOneWidget);
      expect(find.byType(RoomsHeaderSkeleton), findsOneWidget);
      expect(find.byType(RoomCardSkeleton), findsNWidgets(2));
    });

    testWidgets('SkeletonBox renders with requested shape and dimensions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SkeletonBox(
              width: 50,
              height: 50,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );

      final boxFinder = find.byType(SkeletonBox);
      expect(boxFinder, findsOneWidget);

      final container = tester.widget<Container>(
        find.descendant(of: boxFinder, matching: find.byType(Container)),
      );
      expect((container.decoration as BoxDecoration).shape, BoxShape.circle);
    });
  });
}
