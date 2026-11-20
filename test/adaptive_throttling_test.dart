import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';
import 'package:videolog_coach/core/mediapipe_pose_detector.dart';
import 'package:videolog_coach/core/thermal_service.dart';
import 'package:videolog_coach/data/pose_models.dart';
import 'package:videolog_coach/viewmodels/pose_detection_viewmodel.dart';

class _FakeMediaPipePoseDetector extends MediaPipeVisionPoseDetector {
  _FakeMediaPipePoseDetector({PoseModelVariant initialModel = PoseModelVariant.lite})
      : _fakeVariant = initialModel,
        super(initialModel: initialModel);

  PoseModelVariant _fakeVariant;
  int switchCallCount = 0;

  @override
  PoseModelVariant get modelVariant => _fakeVariant;

  @override
  String get modelLabel => _fakeVariant.label;

  @override
  bool get isInitialized => true;

  @override
  Future<Delegate> switchModel(PoseModelVariant variant) async {
    switchCallCount++;
    _fakeVariant = variant;
    return Delegate.cpu;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  setUp(() {
    ThermalService.instance.resetForTesting();
    ThermalService.instance.autoShowDialog = false;
  });

  tearDown(() {
    ThermalService.instance.resetForTesting();
  });

  group('MediaPipeVisionPoseDetector & PoseDetectionViewModel', () {
    test('mapResult convertit 33 landmarks image et world landmarks', () {
      final mpResult = PoseLandmarkerResult(
        poseLandmarks: [
          List.generate(
            33,
            (i) => NormalizedLandmark(
              x: 0.1 + i * 0.01,
              y: 0.2 + i * 0.01,
              z: -0.05,
              visibility: 0.9,
            ),
          ),
        ],
        poseWorldLandmarks: [
          List.generate(
            33,
            (i) => Landmark(
              x: 0.01 * i,
              y: -0.02 * i,
              z: 0.03 * i,
              visibility: 0.85,
            ),
          ),
        ],
        imageWidth: 480,
        imageHeight: 640,
        timestampMilliseconds: 120,
      );

      final mapped = MediaPipeVisionPoseDetector.mapResult(
        mpResult,
        processingTimeMs: 14,
        decodeTimeMs: 5,
        delegateName: 'cpu',
      );

      expect(mapped.hasPoses, isTrue);
      expect(mapped.imageWidth, equals(480));
      expect(mapped.imageHeight, equals(640));
      expect(mapped.processingTimeMs, equals(14));
      expect(mapped.decodeTimeMs, equals(5));
      expect(mapped.delegateName, equals('cpu'));

      final pose = mapped.firstPose!;
      expect(pose.landmarks.length, equals(LandmarkType.count));
      expect(pose.worldLandmarks.length, equals(LandmarkType.count));
      expect(pose.getLandmark(LandmarkType.nose).x, closeTo(0.1, 1e-6));
      expect(pose.getLandmark(LandmarkType.nose).visibility, closeTo(0.9, 1e-6));
      expect(pose.worldLandmarks[11].typeIndex, equals(11));
      expect(pose.worldLandmarks[11].visibility, closeTo(0.85, 1e-6));
      expect(pose.score, closeTo(0.9, 1e-6));
    });

    test('nextMonotonicTimestampMs garantit des timestamps strictement croissants', () {
      final detector = MediaPipeVisionPoseDetector();

      expect(detector.decodeTargetWidth, equals(320));
      expect(detector.nextMonotonicTimestampMs(0), equals(0));
      expect(detector.nextMonotonicTimestampMs(0), equals(1));
      expect(detector.nextMonotonicTimestampMs(1), equals(2));
      expect(detector.nextMonotonicTimestampMs(50), equals(50));
      expect(detector.nextMonotonicTimestampMs(40), equals(51));
    });

    test('PoseModelVariant.fromName et opposite basculent correctement lite/full', () {
      expect(PoseModelVariant.fromName('lite'), equals(PoseModelVariant.lite));
      expect(PoseModelVariant.fromName('full'), equals(PoseModelVariant.full));
      expect(PoseModelVariant.fromName(' FULL '), equals(PoseModelVariant.full));
      expect(PoseModelVariant.fromName('unknown'), equals(PoseModelVariant.lite));
      expect(PoseModelVariant.fromName(null), equals(PoseModelVariant.lite));
      expect(PoseModelVariant.lite.opposite, equals(PoseModelVariant.full));
      expect(PoseModelVariant.full.opposite, equals(PoseModelVariant.lite));
    });

    test('PoseDetectionViewModel expose les getters par défaut avec mediapipe_vision', () {
      final vm = PoseDetectionViewModel();

      expect(vm.isThermalThrottled, isFalse);
      expect(vm.currentTargetFps, equals(30));
      expect(vm.nativeFps, equals(0.0));
      expect(vm.modelVariant, equals(PoseModelVariant.lite));
      expect(vm.modelVariantListenable.value, equals(PoseModelVariant.lite));
      expect(vm.modelLabel, equals('lite'));
      expect(vm.isSwitchingModel, isFalse);
      expect(vm.isBusy, isFalse);

      vm.dispose();
    });

    test('PoseDetectionViewModel bride la cadence (15/10 FPS) et rétrograde full -> lite en cas de surchauffe', () async {
      final fakeDetector = _FakeMediaPipePoseDetector(
        initialModel: PoseModelVariant.full,
      );
      final vm = PoseDetectionViewModel(poseDetector: fakeDetector);

      expect(vm.isThermalThrottled, isFalse);
      expect(vm.currentTargetFps, equals(30));
      expect(vm.modelVariant, equals(PoseModelVariant.full));

      // Surchauffe modérée (status = 2) -> 15 FPS + rétrogradation vers lite
      ThermalService.instance.notifyThermalThrottled(isThrottled: true);
      await Future<void>.delayed(Duration.zero);

      expect(vm.isThermalThrottled, isTrue);
      expect(vm.currentTargetFps, equals(15));
      expect(fakeDetector.switchCallCount, equals(1));
      expect(vm.modelVariant, equals(PoseModelVariant.lite));
      expect(vm.modelVariantListenable.value, equals(PoseModelVariant.lite));

      // Surchauffe sévère (status = 3) -> 10 FPS
      ThermalService.instance.thermalInfo.value = ThermalInfo(
        isOverheating: true,
        status: 3,
        statusName: 'SEVERE',
        timestamp: DateTime.now(),
      );
      expect(vm.isThermalThrottled, isTrue);
      expect(vm.currentTargetFps, equals(10));

      // Retour à la normale -> 30 FPS
      ThermalService.instance.notifyThermalThrottled(isThrottled: false);
      ThermalService.instance.thermalInfo.value = ThermalInfo.normal();
      expect(vm.isThermalThrottled, isFalse);
      expect(vm.currentTargetFps, equals(30));

      vm.dispose();
    });
  });
}
