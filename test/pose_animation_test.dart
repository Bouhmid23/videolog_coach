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

  test('ButterworthFilter2D atténue les bruits haute fréquence et préserve les positions stables', () {
    final filter = ButterworthFilter2D(cutoffFrequency: 5.0, samplingRate: 30.0);
    // Première valeur d'initialisation
    final initial = filter.filter(const Offset(100, 100));
    expect(initial, const Offset(100, 100));

    // Entrée stable : reste stable à 100
    for (int i = 0; i < 10; i++) {
      final res = filter.filter(const Offset(100, 100));
      expect(res.dx, closeTo(100, 0.1));
      expect(res.dy, closeTo(100, 0.1));
    }

    // Injection d'un pic de bruit haute fréquence (bruit MediaPipe Lite isolé)
    final noisy = filter.filter(const Offset(130, 130)); // saut brusque de 30px
    // Le filtre passe-bas doit amortir drastiquement ce pic isolé
    expect(noisy.dx, lessThan(115));
    expect(noisy.dy, lessThan(115));
  });

  test('ButterworthPoseFilter filtre l ensemble des repères anatomiques', () {
    final poseFilter = ButterworthPoseFilter(cutoffFrequency: 5.0, samplingRate: 30.0);
    final rawPose = _pose(50);
    final filtered = poseFilter.filterPose(rawPose);
    expect(filtered.points.containsKey(LandmarkType.nose), isTrue);
    expect(filtered.points[LandmarkType.nose]!.dx, 50);
  });
}
