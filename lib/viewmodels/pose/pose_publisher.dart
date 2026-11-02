import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Size;
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:livekit_client/livekit_client.dart';
import '../../core/gravity_service.dart';
import '../../data/posture_codec.dart';
import '../../data/remote_posture.dart';

/// Encodage v7 et publication du flux de posture sur le DataTrack LiveKit.
class PosePublisher {
  int _seq = 0;
  List<String>? _destinationIdentities;

  // Mesures de publication
  int _publishMicros = 0;
  int _publishSamples = 0;
  int _publishedSinceStats = 0;
  int _seqAtLastStats = 0;

  int get seq => _seq;
  int get publishedSinceStats => _publishedSinceStats;
  int get seqAtLastStats => _seqAtLastStats;
  int get publishMicros => _publishMicros;
  int get publishSamples => _publishSamples;

  void resetStats(int currentSeq) {
    _publishMicros = 0;
    _publishSamples = 0;
    _publishedSinceStats = 0;
    _seqAtLastStats = currentSeq;
  }

  void setDestinationIdentities(List<String>? identities) {
    _destinationIdentities = (identities == null || identities.isEmpty)
        ? null
        : List<String>.unmodifiable(identities);
  }

  void publish({
    required Room? room,
    required Pose pose,
    required RemotePosture? posture,
    required Size frameSize,
    required DateTime capturedAt,
    required String deviceModel,
    int? captureMicros,
    int? detectMicros,
    int? inferMicros,
  }) {
    if (room?.localParticipant == null) return;

    final seq = ++_seq;
    final bytes = PostureCodec.encode(
      label: posture?.label ?? 'inconnu',
      confidence: posture?.confidence,
      landmarks: pose.landmarks,
      worldLandmarks: pose.worldLandmarks,
      frameSize: frameSize,
      seq: seq,
      timestampMs: capturedAt.millisecondsSinceEpoch,
      gravity: GravityService.instance.upInCameraAxes,
    );

    _send(
      room: room,
      bytes: bytes,
      kind: 'posture',
      deviceModel: deviceModel,
      frameSeq: seq,
      frameSize: frameSize,
      captureMicros: captureMicros,
      detectMicros: detectMicros,
      inferMicros: inferMicros,
    );
  }

  void publishLost({
    required Room? room,
    required DateTime capturedAt,
    required String deviceModel,
  }) {
    if (room?.localParticipant == null) return;
    _send(
      room: room,
      bytes: PostureCodec.encodeLost(
        ++_seq,
        timestampMs: capturedAt.millisecondsSinceEpoch,
      ),
      kind: 'lost',
      deviceModel: deviceModel,
    );
  }

  void _send({
    required Room? room,
    required Uint8List bytes,
    required String kind,
    required String deviceModel,
    int? frameSeq,
    Size? frameSize,
    int? captureMicros,
    int? detectMicros,
    int? inferMicros,
  }) {
    final participant = room?.localParticipant;
    if (participant == null) return;

    _publishedSinceStats++;
    final watch = Stopwatch()..start();
    unawaited(
      participant
          .publishData(
            bytes,
            reliable: false,
            topic: 'posture',
            destinationIdentities: _destinationIdentities,
          )
          .then((_) {
            watch.stop();
            _publishMicros += watch.elapsedMicroseconds;
            _publishSamples++;
            if (kDebugMode && frameSeq != null && frameSize != null) {
              debugPrint(
                '📊 pose-frame seq=$frameSeq model=lite device=$deviceModel '
                'resolution=${frameSize.width.toInt()}x${frameSize.height.toInt()} '
                'capture=${(captureMicros ?? 0) / 1000.0}ms '
                'detect=${(detectMicros ?? 0) / 1000.0}ms '
                'infer=${(inferMicros ?? 0) / 1000.0}ms '
                'publish=${watch.elapsedMicroseconds / 1000.0}ms',
              );
            }
          })
          .catchError((Object e) {
            watch.stop();
            _publishMicros += watch.elapsedMicroseconds;
            _publishSamples++;
            debugPrint('⚠️ Failed to publish $kind: $e');
          }),
    );
  }
}

