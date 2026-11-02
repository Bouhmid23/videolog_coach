import 'dart:math' as math;
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

/// Détecteur de mouvement pour l'adaptation intelligente du framerate.
/// Si la variation moyenne des articulations est faible pendant plusieurs frames,
/// la posture est considérée comme statique (ex: gainage, repos, posture fixe).
class MotionDetector {
  Pose? _lastPose;
  int _staticFrameCount = 0;
  static const int _staticThresholdFrames = 15; // ~0.5s - 1s
  static const double _motionEpsilon = 0.015; // Seuil de déplacement normalisé

  bool update(Pose? currentPose) {
    if (currentPose == null || _lastPose == null) {
      _lastPose = currentPose;
      _staticFrameCount = 0;
      return false;
    }

    final p1 = _lastPose!.landmarks;
    final p2 = currentPose.landmarks;
    _lastPose = currentPose;

    if (p1.isEmpty || p2.isEmpty) return false;

    double totalDelta = 0;
    int count = 0;

    for (int i = 0; i < math.min(p1.length, p2.length); i++) {
      final lm1 = p1[i];
      final lm2 = p2[i];
      if (lm1.visibility > 0.5 && lm2.visibility > 0.5) {
        final dx = lm1.x - lm2.x;
        final dy = lm1.y - lm2.y;
        totalDelta += math.sqrt(dx * dx + dy * dy);
        count++;
      }
    }

    final avgDelta = count > 0 ? (totalDelta / count) : 0.0;
    if (avgDelta < _motionEpsilon) {
      _staticFrameCount++;
    } else {
      _staticFrameCount = 0;
    }

    return _staticFrameCount >= _staticThresholdFrames;
  }

  void reset() {
    _lastPose = null;
    _staticFrameCount = 0;
  }
}

