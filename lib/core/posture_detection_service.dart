
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

class PostureSmoothing {
  final Map<LandmarkType, _SmoothedPoint> _smoothedPoints = {};
  final Map<int, _SmoothedWorldPoint> _smoothedWorldPoints = {};
  double _alpha;

  PostureSmoothing({double alpha = 1.0})
    : _alpha = alpha.clamp(0.0, 1.0).toDouble();

  double get alpha => _alpha;

  set alpha(double value) {
    final next = value.clamp(0.0, 1.0).toDouble();
    if (next == _alpha) return;
    _alpha = next;
    reset();
  }

  Pose smooth(Pose pose) {
    if (_alpha >= 1.0) return pose;
    final List<PoseLandmark> smoothedLandmarks = [];

    for (final entry in pose.landmarks) {
      final type = entry.type;

      final smoothed = _smoothedPoints.putIfAbsent(
        type,
            () => _SmoothedPoint(
          entry.x,
          entry.y,
          entry.z,
        ),
      );

      smoothed.update(entry.x, entry.y, entry.z, _alpha);

      smoothedLandmarks.add(
        PoseLandmark(
          type: type,
          x: smoothed.x,
          y: smoothed.y,
          z: smoothed.z,
          visibility: entry.visibility,
        ),
      );
    }

    final smoothedWorld = pose.worldLandmarks.map((point) {
      final smoothed = _smoothedWorldPoints.putIfAbsent(
        point.typeIndex,
        () => _SmoothedWorldPoint(point.x, point.y, point.z),
      );
      smoothed.update(point.x, point.y, point.z, _alpha);
      return WorldLandmark(
        typeIndex: point.typeIndex,
        x: smoothed.x,
        y: smoothed.y,
        z: smoothed.z,
        visibility: point.visibility,
      );
    }).toList(growable: false);

    return Pose(
      landmarks: smoothedLandmarks,
      worldLandmarks: smoothedWorld,
      score: pose.score,
    );
  }

  void reset() {
    _smoothedPoints.clear();
    _smoothedWorldPoints.clear();
  }
}

class _SmoothedPoint {
  double x, y, z;
  _SmoothedPoint(this.x, this.y, this.z);

  void update(double nx, double ny, double nz, double alpha) {
    x = x + alpha * (nx - x);
    y = y + alpha * (ny - y);
    z = z + alpha * (nz - z);
  }
}

class _SmoothedWorldPoint {
  double x, y, z;
  _SmoothedWorldPoint(this.x, this.y, this.z);

  void update(double nx, double ny, double nz, double alpha) {
    x = x + alpha * (nx - x);
    y = y + alpha * (ny - y);
    z = z + alpha * (nz - z);
  }
}
