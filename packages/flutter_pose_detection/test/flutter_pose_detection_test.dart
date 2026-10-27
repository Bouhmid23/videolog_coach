import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

void main() {
  group('LandmarkType', () {
    test('has 33 landmarks', () {
      expect(LandmarkType.values.length, 33);
    });

    test('nose has value 0', () {
      expect(LandmarkType.nose.value, 0);
    });

    test('rightFootIndex has value 32', () {
      expect(LandmarkType.rightFootIndex.value, 32);
    });

    test('fromIndex returns correct type', () {
      expect(LandmarkType.fromIndex(0), LandmarkType.nose);
      expect(LandmarkType.fromIndex(11), LandmarkType.leftShoulder);
      expect(LandmarkType.fromIndex(32), LandmarkType.rightFootIndex);
    });

    test('fromIndex throws for invalid index', () {
      expect(() => LandmarkType.fromIndex(-1), throwsArgumentError);
      expect(() => LandmarkType.fromIndex(33), throwsArgumentError);
    });
  });

  group('AccelerationMode', () {
    test('has 4 modes', () {
      expect(AccelerationMode.values.length, 4);
    });

    test('fromString parses correctly', () {
      expect(AccelerationMode.fromString('npu'), AccelerationMode.npu);
      expect(AccelerationMode.fromString('GPU'), AccelerationMode.gpu);
      expect(AccelerationMode.fromString('cpu'), AccelerationMode.cpu);
      expect(AccelerationMode.fromString('invalid'), AccelerationMode.unknown);
    });
  });

  group('DetectionMode', () {
    test('has 3 modes', () {
      expect(DetectionMode.values.length, 3);
    });

    test('fromString parses correctly', () {
      expect(DetectionMode.fromString('fast'), DetectionMode.fast);
      expect(DetectionMode.fromString('ACCURATE'), DetectionMode.accurate);
      expect(DetectionMode.fromString('invalid'), DetectionMode.balanced);
    });
  });

  group('PoseLandmark', () {
    test('creates landmark correctly', () {
      final landmark = PoseLandmark(
        type: LandmarkType.nose,
        x: 0.5,
        y: 0.3,
        z: 0.1,
        visibility: 0.95,
      );

      expect(landmark.type, LandmarkType.nose);
      expect(landmark.x, 0.5);
      expect(landmark.y, 0.3);
      expect(landmark.z, 0.1);
      expect(landmark.visibility, 0.95);
    });

    test('isDetected returns true when visibility > 0', () {
      final detected = PoseLandmark(
        type: LandmarkType.nose,
        x: 0.5,
        y: 0.3,
        visibility: 0.1,
      );
      expect(detected.isDetected, true);

      final notDetected = PoseLandmark.notDetected(LandmarkType.nose);
      expect(notDetected.isDetected, false);
    });

    test('isReliable respects threshold', () {
      final landmark = PoseLandmark(
        type: LandmarkType.nose,
        x: 0.5,
        y: 0.3,
        visibility: 0.6,
      );

      expect(landmark.isReliable(), true); // default 0.5
      expect(landmark.isReliable(threshold: 0.7), false);
      expect(landmark.isReliable(threshold: 0.5), true);
    });

    test('toJson and fromJson roundtrip', () {
      final original = PoseLandmark(
        type: LandmarkType.leftShoulder,
        x: 0.45,
        y: 0.55,
        z: -0.1,
        visibility: 0.88,
      );

      final json = original.toJson();
      final restored = PoseLandmark.fromJson(json);

      expect(restored.type, original.type);
      expect(restored.x, original.x);
      expect(restored.y, original.y);
      expect(restored.z, original.z);
      expect(restored.visibility, original.visibility);
    });
  });

  group('BoundingBox', () {
    test('creates box correctly', () {
      final box = BoundingBox(
        left: 0.1,
        top: 0.2,
        width: 0.5,
        height: 0.6,
      );

      expect(box.left, 0.1);
      expect(box.top, 0.2);
      expect(box.width, 0.5);
      expect(box.height, 0.6);
    });

    test('calculates derived properties', () {
      final box = BoundingBox(
        left: 0.1,
        top: 0.2,
        width: 0.4,
        height: 0.6,
      );

      expect(box.right, closeTo(0.5, 0.001));
      expect(box.bottom, closeTo(0.8, 0.001));
      expect(box.centerX, closeTo(0.3, 0.001));
      expect(box.centerY, closeTo(0.5, 0.001));
      expect(box.area, closeTo(0.24, 0.001));
    });

    test('toJson and fromJson roundtrip', () {
      final original = BoundingBox(
        left: 0.15,
        top: 0.25,
        width: 0.55,
        height: 0.65,
      );

      final json = original.toJson();
      final restored = BoundingBox.fromJson(json);

      expect(restored.left, original.left);
      expect(restored.top, original.top);
      expect(restored.width, original.width);
      expect(restored.height, original.height);
    });
  });

  group('Pose', () {
    late List<PoseLandmark> landmarks;

    setUp(() {
      landmarks = List.generate(
        33,
        (i) => PoseLandmark(
          type: LandmarkType.fromIndex(i),
          x: i / 33.0,
          y: i / 33.0,
          visibility: i < 20 ? 0.9 : 0.0, // First 20 visible
        ),
      );
    });

    test('creates pose correctly', () {
      final pose = Pose(landmarks: landmarks, score: 0.85);

      expect(pose.landmarks.length, 33);
      expect(pose.score, 0.85);
    });

    test('getLandmark returns correct landmark', () {
      final pose = Pose(landmarks: landmarks, score: 0.85);

      final nose = pose.getLandmark(LandmarkType.nose);
      expect(nose.type, LandmarkType.nose);
    });

    test('getVisibleLandmarks filters by threshold', () {
      final pose = Pose(landmarks: landmarks, score: 0.85);

      final visible = pose.getVisibleLandmarks();
      expect(visible.length, 20);

      final highConfidence = pose.getVisibleLandmarks(threshold: 0.95);
      expect(highConfidence.length, 0);
    });

    test('calculateAngle computes angle correctly', () {
      final angleLandmarks = List.generate(
        33,
        (i) => PoseLandmark.notDetected(LandmarkType.fromIndex(i)),
      );

      // Create a right angle: hip at (0.5, 0.5), knee at (0.5, 0.7), ankle at (0.7, 0.7)
      angleLandmarks[23] = PoseLandmark(
        type: LandmarkType.leftHip,
        x: 0.5,
        y: 0.5,
        visibility: 1.0,
      );
      angleLandmarks[25] = PoseLandmark(
        type: LandmarkType.leftKnee,
        x: 0.5,
        y: 0.7,
        visibility: 1.0,
      );
      angleLandmarks[27] = PoseLandmark(
        type: LandmarkType.leftAnkle,
        x: 0.7,
        y: 0.7,
        visibility: 1.0,
      );

      final pose = Pose(landmarks: angleLandmarks, score: 0.9);
      final angle = pose.calculateAngle(
        LandmarkType.leftHip,
        LandmarkType.leftKnee,
        LandmarkType.leftAnkle,
      );

      expect(angle, isNotNull);
      expect(angle!, closeTo(90.0, 1.0));
    });

    test('calculateDistance computes distance correctly', () {
      final distLandmarks = List.generate(
        33,
        (i) => PoseLandmark.notDetected(LandmarkType.fromIndex(i)),
      );

      distLandmarks[11] = PoseLandmark(
        type: LandmarkType.leftShoulder,
        x: 0.3,
        y: 0.5,
        visibility: 1.0,
      );
      distLandmarks[12] = PoseLandmark(
        type: LandmarkType.rightShoulder,
        x: 0.7,
        y: 0.5,
        visibility: 1.0,
      );

      final pose = Pose(landmarks: distLandmarks, score: 0.9);
      final distance = pose.calculateDistance(
        LandmarkType.leftShoulder,
        LandmarkType.rightShoulder,
      );

      expect(distance, isNotNull);
      expect(distance!, closeTo(0.4, 0.001));
    });
  });

  group('PoseResult', () {
    test('hasPoses returns correct value', () {
      final empty = PoseResult.empty(
        processingTimeMs: 50,
        accelerationMode: AccelerationMode.gpu,
        imageWidth: 640,
        imageHeight: 480,
      );
      expect(empty.hasPoses, false);
      expect(empty.firstPose, isNull);
    });

    test('poseCount returns correct value', () {
      final empty = PoseResult.empty(
        processingTimeMs: 50,
        accelerationMode: AccelerationMode.npu,
        imageWidth: 640,
        imageHeight: 480,
      );
      expect(empty.poseCount, 0);
    });
  });

  group('PoseDetectorConfig', () {
    test('default config has correct values', () {
      const config = PoseDetectorConfig();

      expect(config.mode, DetectionMode.fast);
      expect(config.maxPoses, 1);
      expect(config.minConfidence, 0.5);
      expect(config.enableZEstimation, true);
      expect(config.preferredAcceleration, isNull);
    });

    test('realtime factory creates optimized config', () {
      final config = PoseDetectorConfig.realtime();

      expect(config.mode, DetectionMode.fast);
      expect(config.maxPoses, 1);
      expect(config.minConfidence, 0.3);
      expect(config.enableZEstimation, false);
    });

    test('accurate factory creates optimized config', () {
      final config = PoseDetectorConfig.accurate();

      expect(config.mode, DetectionMode.accurate);
      expect(config.maxPoses, 5);
      expect(config.minConfidence, 0.5);
      expect(config.enableZEstimation, true);
    });

    test('copyWith creates modified config', () {
      const config = PoseDetectorConfig();
      final modified = config.copyWith(
        mode: DetectionMode.accurate,
        maxPoses: 3,
      );

      expect(modified.mode, DetectionMode.accurate);
      expect(modified.maxPoses, 3);
      expect(modified.minConfidence, config.minConfidence);
    });

    test('toJson and fromJson roundtrip', () {
      const original = PoseDetectorConfig(
        mode: DetectionMode.balanced,
        maxPoses: 3,
        minConfidence: 0.6,
        enableZEstimation: false,
        preferredAcceleration: AccelerationMode.gpu,
      );

      final json = original.toJson();
      final restored = PoseDetectorConfig.fromJson(json);

      expect(restored.mode, original.mode);
      expect(restored.maxPoses, original.maxPoses);
      expect(restored.minConfidence, original.minConfidence);
      expect(restored.enableZEstimation, original.enableZEstimation);
      expect(restored.preferredAcceleration, original.preferredAcceleration);
    });
  });

  group('DetectionError', () {
    test('creates error correctly', () {
      const error = DetectionError(
        code: DetectionErrorCode.invalidImageFormat,
        message: 'Image format not supported',
      );

      expect(error.code, DetectionErrorCode.invalidImageFormat);
      expect(error.message, 'Image format not supported');
      expect(error.isRecoverable, true);
    });

    test('fromCode creates error with default message', () {
      final error = DetectionError.fromCode(
        DetectionErrorCode.modelLoadFailed,
        platformMessage: 'File not found',
      );

      expect(error.code, DetectionErrorCode.modelLoadFailed);
      expect(error.message, 'ML model load failed');
      expect(error.platformMessage, 'File not found');
    });

    test('platformNotSupported is not recoverable', () {
      const error = DetectionError(
        code: DetectionErrorCode.platformNotSupported,
        message: 'Not supported',
      );

      expect(error.isRecoverable, false);
    });

    test('error codes have descriptions', () {
      for (final code in DetectionErrorCode.values) {
        expect(code.description, isNotEmpty);
      }
    });
  });

  group('FrameResult', () {
    test('creates frame result correctly', () {
      final poseResult = PoseResult.empty(
        processingTimeMs: 16,
        accelerationMode: AccelerationMode.npu,
        imageWidth: 640,
        imageHeight: 480,
      );

      final frameResult = FrameResult(
        result: poseResult,
        frameNumber: 10,
        timestampUs: 333333,
        fps: 30.0,
      );

      expect(frameResult.result, poseResult);
      expect(frameResult.frameNumber, 10);
      expect(frameResult.timestampUs, 333333);
      expect(frameResult.fps, 30.0);
    });

    test('toJson and fromJson roundtrip', () {
      final poseResult = PoseResult.empty(
        processingTimeMs: 16,
        accelerationMode: AccelerationMode.gpu,
        imageWidth: 1920,
        imageHeight: 1080,
      );

      final original = FrameResult(
        result: poseResult,
        frameNumber: 42,
        timestampUs: 1000000,
        fps: 25.5,
      );

      final json = original.toJson();
      final restored = FrameResult.fromJson(json);

      expect(restored.frameNumber, original.frameNumber);
      expect(restored.timestampUs, original.timestampUs);
      expect(restored.fps, original.fps);
      expect(restored.result.processingTimeMs, original.result.processingTimeMs);
    });

    test('toString formats correctly', () {
      final poseResult = PoseResult.empty(
        processingTimeMs: 16,
        accelerationMode: AccelerationMode.npu,
        imageWidth: 640,
        imageHeight: 480,
      );

      final frameResult = FrameResult(
        result: poseResult,
        frameNumber: 10,
        timestampUs: 333333,
        fps: 30.0,
      );

      expect(frameResult.toString(), contains('frame: 10'));
      expect(frameResult.toString(), contains('fps: 30.0'));
    });
  });

  group('VideoAnalysisResult', () {
    test('creates video analysis result correctly', () {
      final result = VideoAnalysisResult(
        frames: [],
        totalFrames: 900,
        analyzedFrames: 300,
        durationSeconds: 30.0,
        frameRate: 30.0,
        width: 1920,
        height: 1080,
        totalAnalysisTimeMs: 15000,
      );

      expect(result.totalFrames, 900);
      expect(result.analyzedFrames, 300);
      expect(result.durationSeconds, 30.0);
      expect(result.frameRate, 30.0);
      expect(result.width, 1920);
      expect(result.height, 1080);
      expect(result.totalAnalysisTimeMs, 15000);
    });

    test('analysisSpeed calculates correctly', () {
      final result = VideoAnalysisResult(
        frames: [],
        totalFrames: 900,
        analyzedFrames: 300,
        durationSeconds: 30.0,
        frameRate: 30.0,
        width: 1920,
        height: 1080,
        totalAnalysisTimeMs: 15000, // 15 seconds
      );

      // 300 frames in 15 seconds = 20 FPS
      expect(result.analysisSpeed, closeTo(20.0, 0.1));
    });

    test('detectionRate calculates correctly', () {
      final poseResult = PoseResult.empty(
        processingTimeMs: 16,
        accelerationMode: AccelerationMode.npu,
        imageWidth: 640,
        imageHeight: 480,
      );

      final frameWithPose = VideoFrameResult(
        frameIndex: 0,
        timestampSeconds: 0.0,
        result: PoseResult(
          poses: [
            Pose(
              landmarks: List.generate(
                33,
                (i) => PoseLandmark(
                  type: LandmarkType.fromIndex(i),
                  x: 0.5,
                  y: 0.5,
                  visibility: 0.9,
                ),
              ),
              score: 0.9,
            ),
          ],
          processingTimeMs: 16,
          accelerationMode: AccelerationMode.npu,
          timestamp: DateTime.now(),
          imageWidth: 640,
          imageHeight: 480,
        ),
      );

      final frameWithoutPose = VideoFrameResult(
        frameIndex: 1,
        timestampSeconds: 0.033,
        result: poseResult,
      );

      final result = VideoAnalysisResult(
        frames: [frameWithPose, frameWithoutPose],
        totalFrames: 60,
        analyzedFrames: 2,
        durationSeconds: 2.0,
        frameRate: 30.0,
        width: 640,
        height: 480,
        totalAnalysisTimeMs: 100,
      );

      // 1 out of 2 frames has pose = 50%
      expect(result.detectionRate, closeTo(0.5, 0.01));
    });
  });

  group('VideoAnalysisProgress', () {
    test('creates progress correctly', () {
      const progress = VideoAnalysisProgress(
        currentFrame: 100,
        totalFrames: 900,
        currentTimeSeconds: 3.33,
        durationSeconds: 30.0,
        estimatedRemainingSeconds: 26.67,
      );

      expect(progress.currentFrame, 100);
      expect(progress.totalFrames, 900);
      expect(progress.currentTimeSeconds, 3.33);
      expect(progress.durationSeconds, 30.0);
      expect(progress.estimatedRemainingSeconds, 26.67);
    });

    test('progress calculates correctly', () {
      const progress = VideoAnalysisProgress(
        currentFrame: 300,
        totalFrames: 900,
        currentTimeSeconds: 10.0,
        durationSeconds: 30.0,
      );

      // 300/900 = 33.3%
      expect(progress.progress, closeTo(0.333, 0.01));
    });

    test('toJson and fromJson roundtrip', () {
      const original = VideoAnalysisProgress(
        currentFrame: 450,
        totalFrames: 900,
        currentTimeSeconds: 15.0,
        durationSeconds: 30.0,
        estimatedRemainingSeconds: 15.0,
      );

      final json = original.toJson();
      final restored = VideoAnalysisProgress.fromJson(json);

      expect(restored.currentFrame, original.currentFrame);
      expect(restored.totalFrames, original.totalFrames);
      expect(restored.currentTimeSeconds, original.currentTimeSeconds);
      expect(restored.durationSeconds, original.durationSeconds);
      expect(restored.estimatedRemainingSeconds, original.estimatedRemainingSeconds);
    });
  });
}
