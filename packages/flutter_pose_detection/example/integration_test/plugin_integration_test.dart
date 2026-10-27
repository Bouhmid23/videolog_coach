// Integration test for flutter_pose_detection plugin.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('NpuPoseDetector can be created', (WidgetTester tester) async {
    final detector = NpuPoseDetector();
    expect(detector, isNotNull);
    expect(detector.isInitialized, false);
  });

  testWidgets('PoseDetectorConfig can be configured', (WidgetTester tester) async {
    const config = PoseDetectorConfig(
      mode: DetectionMode.fast,
      maxPoses: 1,
      minConfidence: 0.5,
    );

    expect(config.mode, DetectionMode.fast);
    expect(config.maxPoses, 1);
    expect(config.minConfidence, 0.5);
  });

  testWidgets('LandmarkType has all 33 landmarks', (WidgetTester tester) async {
    expect(LandmarkType.values.length, 33);
    expect(LandmarkType.nose.value, 0);
    expect(LandmarkType.rightFootIndex.value, 32);
  });
}
