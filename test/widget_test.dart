import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/data/mobile_room.dart';
import 'package:videolog_coach/data/recording_state.dart';

void main() {
  group('RecordingState', () {
    test('normalise les statuts LiveKit bruts', () {
      final active = RecordingState.fromJson({
        'room_name': 'session-a',
        'status': 'EGRESS_ACTIVE',
        'egress_id': 'egress-1',
        'started_at': '2026-10-25T10:00:00+00:00',
      });

      expect(active.status, 'recording');
      expect(active.isActive, isTrue);
      expect(active.canStop, isTrue);
      expect(active.canStart, isFalse);
      expect(active.label, 'Enregistrement');
      expect(active.egressId, 'egress-1');
      expect(active.startedAt, isNotNull);
    });

    test('considère un enregistrement terminé comme redémarrable', () {
      final completed = RecordingState.fromJson({
        'room_name': 'session-a',
        'status': 'EGRESS_COMPLETE',
      });

      expect(completed.status, 'completed');
      expect(completed.isTerminal, isTrue);
      expect(completed.canStart, isTrue);
      expect(completed.canStop, isFalse);
    });

    test('parse les fichiers signés', () {
      final state = RecordingState.fromJson({
        'room_name': 'session-a',
        'status': 'completed',
        'files': [
          {
            'filename': 'session-a/recording.mp4',
            'url':
                'https://minio.videolog.app/recordings/session-a/recording.mp4',
            'size': 1024,
            'duration': 180,
          },
        ],
      });

      expect(state.files, hasLength(1));
      expect(state.files.first.filename, 'session-a/recording.mp4');
      expect(state.files.first.url, contains('minio.videolog.app'));
      expect(state.files.first.sizeBytes, 1024);
    });
  });

  group('MobileRoom', () {
    test('parse la réponse de /mobile/rooms', () {
      final room = MobileRoom.fromJson({
        'room_name': 'session-2026-10-25-a',
        'count': 2,
        'recording': true,
        'recording_status': 'recording',
        'created_at': '2026-10-25T10:00:00+00:00',
        'updated_at': '2026-10-25T10:05:00+00:00',
        'can_control_recording': true,
      });

      expect(room.name, 'session-2026-10-25-a');
      expect(room.participantCount, 2);
      expect(room.isRecording, isTrue);
      expect(room.canControlRecording, isTrue);
      expect(room.recordingLabel, 'Enregistrement');
      expect(room.updatedAt, isNotNull);
    });

    test('accepte le champ name en repli', () {
      final room = MobileRoom.fromJson({'name': 'session-fallback'});

      expect(room.name, 'session-fallback');
    });
  });
}
