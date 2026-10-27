# Flutter Pose Detection Example

Example app demonstrating the flutter_pose_detection plugin features.

## Features

### Home Screen
- **Acceleration Mode Toggle**: Switch between GPU (fast) and NPU (battery-efficient) modes
- **Delegate Benchmark**: Run performance benchmarks to compare NPU, GPU, and CPU inference times
- **Status Display**: Shows current acceleration mode in use

### Detection Modes

1. **Image Detection**: Detect poses in static images from gallery
2. **Camera Detection**: Real-time pose detection from device camera
3. **Video Analysis**: Analyze poses in video files with progress tracking

## NPU vs GPU Mode

| Mode | Inference Time | Power | Best For |
|------|---------------|-------|----------|
| GPU | ~3ms | High | Short sessions, max FPS |
| NPU | ~13-16ms | Low | Long-running apps |
| CPU | ~17ms | Medium | Fallback |

## Usage

```dart
// GPU mode (default) - fastest
final detector = NpuPoseDetector();

// NPU mode - battery efficient (Snapdragon only)
final detector = NpuPoseDetector(
  config: PoseDetectorConfig(
    preferredAcceleration: AccelerationMode.npu,
  ),
);

final mode = await detector.initialize();
print('Running on: ${mode.name}');
```

## Running the Example

```bash
cd example
flutter run
```

## Requirements

- **iOS**: iOS 14+
- **Android**: API 31+ (NPU requires Snapdragon chipset)
