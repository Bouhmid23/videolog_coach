# livekitapp

## Real-time pose stream

The Android app uses the local `packages/flutter_pose_detection` fork of
`flutter_pose_detection` 0.4.1 and its bundled MediaPipe **lite** task model.
Pose inference runs in `VIDEO` mode with one pose and separate detection,
presence, and tracking confidence thresholds set to 0.5. Camera JPEG bytes are
passed in memory; a monotonic frame timestamp is used by MediaPipe, while the
posture packet keeps the image capture epoch timestamp.

Topic `posture` emits binary format **v7**: an 11-byte header followed by 33
8-byte points (275 bytes total). Each point contains image x/y, metric world
x/y/z in meters (±1.5 m), and 4-bit image-landmark visibility. The world coordinates come
from MediaPipe `worldLandmarks()` and are centered around the hip origin. The
web receiver must support v7 before this publisher is used with it.

Runtime logs include `📊 pose` stage timings/rates and a `📐 pose-runtime`
sample showing the image-z and world-z ranges. FPS, dropout, and turn-around
behavior require measurement on the target device; the code does not guarantee
20 poses/s or prevent semantic left/right changes during a full turn.

The trainee can adjust posture smoothing from the call controls. The value is
saved on the device, defaults to **1.00** (raw points), and can be changed while
the app is running without rebuilding.

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
