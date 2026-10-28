import 'dart:ui';

import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/presentation/widgets/pose_animation.dart';

InterpolatedPose _pose(double x) => InterpolatedPose(
      points: {LandmarkType.nose: Offset(x, 10)},
      confidence: {LandmarkType.nose: 1},
    );

void main() {
  test('les os standard et de détail relient les 33 points du squelette', () {
    final linked = <LandmarkType>{
      for (final bone in [...HumanSkeletonBones.standardBones, ...HumanSkeletonBones.detailBones]) ...[bone.from, bone.to],
    };
    expect(linked, LandmarkType.values.toSet(), reason: 'points jamais dessinés');
    expect(linked.length, 33);
  });

  test('les os standard seuls ne relient que 12 points (corps)', () {
    final linked = <LandmarkType>{
      for (final bone in HumanSkeletonBones.standardBones) ...[bone.from, bone.to],
    };
    expect(linked.length, 12);
  });

  testWidgets('le squelette atteint la cible à la fin de la durée demandée, sans la dépasser', (tester) async {
    final controller = PoseAnimationController(vsync: const TestVSync());
    controller.jumpToPose(_pose(0));
    controller.updatePose(_pose(100), duration: const Duration(milliseconds: 50));

    await tester.pump(); // démarre l'animation
    await tester.pump(const Duration(milliseconds: 25));
    final mid = controller.currentPose!.points[LandmarkType.nose]!.dx;
    expect(mid, closeTo(50, 5), reason: 'interpolation linéaire à mi-parcours');

    await tester.pump(const Duration(milliseconds: 40));
    expect(controller.currentPose!.points[LandmarkType.nose]!.dx, closeTo(100, 0.001));
    controller.dispose();
  });

  testWidgets('une nouvelle pose repart de la pose courante, sans saut', (tester) async {
    final controller = PoseAnimationController(vsync: const TestVSync());
    controller.jumpToPose(_pose(0));
    controller.updatePose(_pose(100), duration: const Duration(milliseconds: 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final before = controller.currentPose!.points[LandmarkType.nose]!.dx;
    controller.updatePose(_pose(0), duration: const Duration(milliseconds: 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    final after = controller.currentPose!.points[LandmarkType.nose]!.dx;
    expect((after - before).abs(), lessThan(5));
    controller.dispose();
  });
}
