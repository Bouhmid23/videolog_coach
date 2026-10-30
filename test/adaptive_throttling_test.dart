import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:videolog_coach/viewmodels/pose_detection_viewmodel.dart';

void main() {
  group('Adaptive Throttling & Zero-Copy Pipeline Models', () {
    test('FrameResult correctly parses thermal and battery throttling payload', () {
      final json = {
        'type': 'frame',
        'frameNumber': 42,
        'timestampUs': 1690000000000,
        'fps': 28.5,
        'isThermalThrottled': true,
        'isLowBattery': false,
        'batteryLevel': 0.65,
        'targetFps': 15,
        'result': {
          'poses': [
            {
              'landmarks': List.generate(
                33,
                (i) => {'type': i, 'x': 0.5, 'y': 0.5, 'z': 0.0, 'visibility': 0.99},
              ),
              'worldLandmarks': [],
              'score': 0.99,
            }
          ],
          'processingTimeMs': 12,
          'accelerationMode': 'gpu',
          'imageWidth': 640,
          'imageHeight': 480,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }
      };

      final frameResult = FrameResult.fromJson(json);

      expect(frameResult.frameNumber, equals(42));
      expect(frameResult.fps, closeTo(28.5, 0.01));
      expect(frameResult.isThermalThrottled, isTrue);
      expect(frameResult.isLowBattery, isFalse);
      expect(frameResult.batteryLevel, closeTo(0.65, 0.01));
      expect(frameResult.targetFps, equals(15));
      expect(frameResult.result.hasPoses, isTrue);
      expect(frameResult.result.firstPose?.landmarks.length, equals(33));
    });

    test('PoseDetectionViewModel exposes throttling getters with default values', () {
      final vm = PoseDetectionViewModel();

      expect(vm.isNativePipelineActive, isFalse);
      expect(vm.isThermalThrottled, isFalse);
      expect(vm.isLowBattery, isFalse);
      expect(vm.currentTargetFps, equals(30));
      expect(vm.nativeFps, equals(0.0));
      expect(vm.isBusy, isFalse);

      vm.dispose();
    });
  });
}
