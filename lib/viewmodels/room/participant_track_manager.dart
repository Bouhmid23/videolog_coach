import 'dart:async';

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, VoidCallback;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:livekit_client/livekit_client.dart';

import '../../data/ball_marker.dart';
import '../../data/remote_posture.dart';
import '../../data/remote_telemetry.dart';
import '../../data/user_role.dart';
import '../../presentation/widgets/participant_info.dart';
import '../pose_detection_viewmodel.dart';

/// Gestionnaire des participants, de la disposition des flux vidéo (primaire / secondaire)
/// et des notifications d'état par participant.
class ParticipantTrackManager {
  final VoidCallback onStateChanged;

  ParticipantTrackManager({required this.onStateChanged});

  List<ParticipantTrack> _participantTracks = [];
  final Map<String, RemotePosture> _remotePostures = {};
  final Map<String, RemoteTelemetry> _remoteTelemetry = {};
  final Map<String, ValueNotifier<RemoteTelemetry?>> _telemetryNotifiers = {};
  final ValueNotifier<bool> _showPostureNotifier = ValueNotifier<bool>(true);

  // Visibilité posture par participant
  final Set<String> _hiddenPostures = {};

  // Sélections et panneaux
  bool _showPosePip = true;
  String? _selectedParticipantIdentity;
  bool _showSideSheet = false;
  ({String identity, ParticipantTrackType type})? _selectedPrimaryTrack;

  // ── Getters ──
  List<ParticipantTrack> get participantTracks => _participantTracks;
  bool get showPosePip => _showPosePip;
  bool get showPosture => _showPostureNotifier.value;
  ValueListenable<bool> get showPostureListenable => _showPostureNotifier;
  String? get selectedParticipantIdentity => _selectedParticipantIdentity;
  bool get showSideSheet => _showSideSheet;
  Map<String, RemoteTelemetry> get remoteTelemetryMap => _remoteTelemetry;

  ValueNotifier<RemoteTelemetry?> telemetryNotifierFor(String identity) {
    return _telemetryNotifiers.putIfAbsent(
      identity,
      () => ValueNotifier<RemoteTelemetry?>(_remoteTelemetry[identity]),
    );
  }

  ValueListenable<RemoteTelemetry?> telemetryListenableFor(String identity) =>
      telemetryNotifierFor(identity);

  void setTelemetryFor(String identity, RemoteTelemetry telemetry) {
    final notifier = telemetryNotifierFor(identity);
    if (!telemetry.equalValues(notifier.value)) {
      notifier.value = telemetry;
    }
    for (final track in _participantTracks) {
      if (track.type == ParticipantTrackType.kUserMedia &&
          track.participant.identity == identity) {
        track.telemetry = telemetry;
      }
    }
  }

  void updateRemoteTelemetry(String identity, RemoteTelemetry telemetry) {
    _remoteTelemetry[identity] = telemetry;
    setTelemetryFor(identity, telemetry);
  }

  void removeParticipant(String identity) {
    _remotePostures.remove(identity);
    _remoteTelemetry.remove(identity);
    _telemetryNotifiers.remove(identity)?.dispose();
  }

  void togglePosePip() {
    _showPosePip = !_showPosePip;
    onStateChanged();
  }

  void togglePosture() {
    unawaited(HapticFeedback.lightImpact());
    final next = !_showPostureNotifier.value;
    _showPostureNotifier.value = next;
    for (final track in _participantTracks) {
      track.showPosture = next;
    }
  }

  void selectParticipant(String? identity) {
    if (_selectedParticipantIdentity == identity) {
      _showSideSheet = !_showSideSheet;
    } else {
      _selectedParticipantIdentity = identity;
      _showSideSheet = identity != null;
    }
    onStateChanged();
  }

  void closeSideSheet() {
    if (!_showSideSheet) return;
    _showSideSheet = false;
    onStateChanged();
  }

  void setPrimaryTrack(ParticipantTrack track) {
    final selected = (identity: track.participant.identity, type: track.type);
    if (_selectedPrimaryTrack == selected) return;
    _selectedPrimaryTrack = selected;
    onStateChanged();
  }

  bool switchToNextParticipant() {
    if (_participantTracks.length <= 1) return false;
    final current = primaryTrack;
    if (current == null) return false;
    final currentIndex = _participantTracks.indexOf(current);
    final nextIndex = (currentIndex + 1) % _participantTracks.length;
    setPrimaryTrack(_participantTracks[nextIndex]);
    return true;
  }

  bool switchToPreviousParticipant() {
    if (_participantTracks.length <= 1) return false;
    final current = primaryTrack;
    if (current == null) return false;
    final currentIndex = _participantTracks.indexOf(current);
    final prevIndex =
        (currentIndex - 1 + _participantTracks.length) %
        _participantTracks.length;
    setPrimaryTrack(_participantTracks[prevIndex]);
    return true;
  }

  void togglePostureVisibility(
    String participantIdentity,
    VoidCallback onSortNeeded,
  ) {
    if (_hiddenPostures.contains(participantIdentity)) {
      _hiddenPostures.remove(participantIdentity);
    } else {
      _hiddenPostures.add(participantIdentity);
    }
    onSortNeeded();
  }

  bool isPostureVisible(String participantIdentity) {
    return !_hiddenPostures.contains(participantIdentity);
  }

  RemotePosture? posturesForParticipant(Participant participant) {
    return _remotePostures[participant.identity];
  }

  RemoteTelemetry? telemetryForParticipant(Participant participant) {
    return _remoteTelemetry[participant.identity];
  }

  ParticipantTrack? get primaryTrack {
    final selected = _selectedPrimaryTrack;
    if (selected != null) {
      for (final track in _participantTracks) {
        if (track.participant.identity == selected.identity &&
            track.type == selected.type) {
          return track;
        }
      }
    }

    for (final track in _participantTracks) {
      if (track.participant is LocalParticipant &&
          track.type == ParticipantTrackType.kUserMedia) {
        return track;
      }
    }

    return _participantTracks.isNotEmpty ? _participantTracks.first : null;
  }

  List<ParticipantTrack> get secondaryTracks {
    final primary = primaryTrack;
    if (primary == null) return _participantTracks;
    return _participantTracks.where((t) => t != primary).toList();
  }

  bool _isDisplayable(Participant p) {
    if (p.kind == ParticipantKind.AGENT) return false;
    if (p.kind != ParticipantKind.STANDARD) return false;
    return p.permissions.canPublish;
  }

  void sortParticipants({
    required Room? room,
    required RemoteTelemetry localTelemetry,
    required ValueNotifier<PoseFrame?> poseFrameNotifier,
    required ValueListenable<List<BallMarker>> markerListenable,
    required UserRole role,
  }) {
    if (room == null) return;

    final activeIdentities = <String>{
      if (room.localParticipant != null) room.localParticipant!.identity,
      ...room.remoteParticipants.values
          .where(_isDisplayable)
          .map((p) => p.identity),
    };
    _remotePostures.removeWhere(
      (identity, _) => !activeIdentities.contains(identity),
    );

    final userMediaTracks = <ParticipantTrack>[];
    final screenTracks = <ParticipantTrack>[];

    for (var participant in room.remoteParticipants.values.where(
      _isDisplayable,
    )) {
      var hasUserMediaVideo = false;
      for (var t in participant.videoTrackPublications) {
        if (t.isScreenShare) {
          screenTracks.add(
            ParticipantTrack(
              participant: participant,
              type: ParticipantTrackType.kScreenShare,
            ),
          );
        } else {
          hasUserMediaVideo = true;
          userMediaTracks.add(
            ParticipantTrack(
              participant: participant,
              telemetry: _remoteTelemetry[participant.identity],
              telemetryListenable: telemetryNotifierFor(participant.identity),
            ),
          );
        }
      }
      if (!hasUserMediaVideo) {
        userMediaTracks.add(
          ParticipantTrack(
            participant: participant,
            type: ParticipantTrackType.kUserMedia,
            telemetry: _remoteTelemetry[participant.identity],
            telemetryListenable: telemetryNotifierFor(participant.identity),
          ),
        );
      }
    }

    userMediaTracks.sort((a, b) {
      if (a.participant.isSpeaking && b.participant.isSpeaking) {
        return a.participant.audioLevel > b.participant.audioLevel ? -1 : 1;
      }
      final aSpokeAt = a.participant.lastSpokeAt?.millisecondsSinceEpoch ?? 0;
      final bSpokeAt = b.participant.lastSpokeAt?.millisecondsSinceEpoch ?? 0;
      if (aSpokeAt != bSpokeAt) return aSpokeAt > bSpokeAt ? -1 : 1;
      return a.participant.joinedAt.millisecondsSinceEpoch -
          b.participant.joinedAt.millisecondsSinceEpoch;
    });

    final localParticipant = room.localParticipant;
    if (localParticipant != null) {
      final localTracks = localParticipant.videoTrackPublications;
      final localTelNotifier = telemetryNotifierFor(localParticipant.identity);
      if (!localTelemetry.equalValues(localTelNotifier.value)) {
        localTelNotifier.value = localTelemetry;
      }
      var hasLocalUserMedia = false;
      for (var t in localTracks) {
        if (t.isScreenShare) {
          screenTracks.add(
            ParticipantTrack(
              participant: localParticipant,
              type: ParticipantTrackType.kScreenShare,
            ),
          );
        } else {
          hasLocalUserMedia = true;
          userMediaTracks.add(
            ParticipantTrack(
              participant: localParticipant,
              telemetry: localTelemetry,
              telemetryListenable: localTelNotifier,
              poseListenable: poseFrameNotifier,
              markers: role.isTrainee ? markerListenable : null,
              showPosture: _showPostureNotifier.value,
              showPostureListenable: _showPostureNotifier,
            ),
          );
        }
      }
      if (!hasLocalUserMedia) {
        userMediaTracks.add(
          ParticipantTrack(
            participant: localParticipant,
            type: ParticipantTrackType.kUserMedia,
            telemetry: localTelemetry,
            telemetryListenable: localTelNotifier,
            poseListenable: poseFrameNotifier,
            markers: role.isTrainee ? markerListenable : null,
            showPosture: _showPostureNotifier.value,
            showPostureListenable: _showPostureNotifier,
          ),
        );
      }
    }

    final nextTracks = [...screenTracks, ...userMediaTracks];
    final previousTracks = _participantTracks;
    _participantTracks = nextTracks;

    var selectionCleared = false;
    if (_selectedPrimaryTrack != null &&
        !_participantTracks.any(
          (t) =>
              t.participant.identity == _selectedPrimaryTrack!.identity &&
              t.type == _selectedPrimaryTrack!.type,
        )) {
      _selectedPrimaryTrack = null;
      selectionCleared = true;
    }

    if (selectionCleared || !_sameTrackList(previousTracks, nextTracks)) {
      onStateChanged();
    }
  }

  static bool _sameTrackList(
    List<ParticipantTrack> a,
    List<ParticipantTrack> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].participant.identity != b[i].participant.identity ||
          a[i].type != b[i].type) {
        return false;
      }
      final aPub = a[i].participant.videoTrackPublications
          .where((e) => e.source == a[i].type.lkVideoSourceType)
          .firstOrNull;
      final bPub = b[i].participant.videoTrackPublications
          .where((e) => e.source == b[i].type.lkVideoSourceType)
          .firstOrNull;
      if (aPub?.sid != bPub?.sid ||
          aPub?.muted != bPub?.muted ||
          (aPub?.track != null) != (bPub?.track != null)) {
        return false;
      }
    }
    return true;
  }

  void dispose() {
    for (final notifier in _telemetryNotifiers.values) {
      notifier.dispose();
    }
    _telemetryNotifiers.clear();
    _showPostureNotifier.dispose();
  }
}
