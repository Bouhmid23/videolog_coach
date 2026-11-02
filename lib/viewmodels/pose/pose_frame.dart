import 'dart:typed_data';
import 'dart:ui' show Size;
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

/// Chemin du JPEG capturé et instant où l'image a été prise. Le timestamp
/// reste attaché à l'image : la capture N+1 tourne pendant la détection N.
class CapturedFrame {
  const CapturedFrame(
    this.bytes,
    this.capturedAt,
    this.videoTimestampMs,
    this.captureMicros,
  );

  final Uint8List bytes;
  final DateTime capturedAt;
  final int videoTimestampMs;
  final int captureMicros;
}

/// Dernière pose détectée, prête à être dessinée par l'UI.
class PoseFrame {
  const PoseFrame({
    required this.pose,
    required this.frameSize,
    required this.capturedAt,
  });

  final Pose pose;
  final Size frameSize;
  final DateTime capturedAt;
}

