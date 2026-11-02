import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppLifecycleState;
import 'package:flutter/foundation.dart'
    show
        ChangeNotifier,
        ValueListenable,
        debugPrint,
        VoidCallback;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:livekit_client/livekit_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/athletic_haptics.dart';
import '../core/auth_service.dart';
import '../core/beep_service.dart';
import '../core/ble_sensor_service.dart';
import '../core/ble_telemetry_service.dart';
import '../core/call_foreground_service.dart';
import '../core/pip_service.dart';
import '../data/ball_marker.dart';
import '../data/glasses_message.dart';
import '../data/remote_posture.dart';
import '../data/remote_telemetry.dart';
import '../data/telemetry_codec.dart';
import '../data/user_role.dart';
import '../presentation/widgets/participant_info.dart';
import '../utils.dart';
import 'controls_viewmodel.dart';
import 'marker_controller.dart';
import 'pose_detection_viewmodel.dart';
import 'room/participant_track_manager.dart';
import 'room/room_telemetry_coordinator.dart';

/// Orchestrateur de session sportive LiveKit :
/// - Coordonne les flux participants via [ParticipantTrackManager].
/// - Coordonne la télémétrie locale, GPS et capteurs via [RoomTelemetryCoordinator].
/// - Intègre la détection de pose [PoseDetectionViewModel], les contrôles média [ControlsViewModel]
///   et les repères tactiques [MarkerController].
class RoomViewModel extends ChangeNotifier {
  // ── Services & Sub-viewmodels ──
  final BleTelemetryService bleService = BleTelemetryService();
  final BleSensorService sensorService = BleSensorService();
  final PoseDetectionViewModel poseViewModel = PoseDetectionViewModel();
  final ControlsViewModel controlsViewModel = ControlsViewModel();
  final MarkerController markers = MarkerController();

  late final RoomTelemetryCoordinator _telemetryCoordinator;
  late final ParticipantTrackManager _trackManager;

  // ── Callbacks & lifecycle ──
  VoidCallback? _onDisconnected;
  bool _disposed = false;

  // ── Room references ──
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  UserRole _role = UserRole.trainee;

  RoomViewModel() {
    _trackManager = ParticipantTrackManager(onStateChanged: _notifySafe);
    _telemetryCoordinator = RoomTelemetryCoordinator(
      bleService: bleService,
      sensorService: sensorService,
      onTelemetryUpdated: _notifySafe,
      onLocalTelemetryChanged: (tel) {
        final localId = _room?.localParticipant?.identity;
        if (localId != null) {
          _trackManager.setTelemetryFor(localId, tel);
        }
      },
    );
  }

  // ── Getters délégués ──
  Room? get room => _room;
  EventsListener<RoomEvent>? get listener => _listener;
  UserRole get role => _role;

  List<ParticipantTrack> get participantTracks => _trackManager.participantTracks;
  ParticipantTrack? get primaryTrack => _trackManager.primaryTrack;
  List<ParticipantTrack> get secondaryTracks => _trackManager.secondaryTracks;

  int? get sensorHeartRate => _telemetryCoordinator.sensorHeartRate;
  int? get sensorCadence => _telemetryCoordinator.sensorCadence;
  SportMetrics? get bleMetrics => _telemetryCoordinator.bleMetrics;
  double get totalDistanceMiles => _telemetryCoordinator.totalDistanceMiles;
  double get totalDistanceKm => _telemetryCoordinator.totalDistanceKm;

  bool get showPosePip => _trackManager.showPosePip;
  bool get showPosture => _trackManager.showPosture;
  ValueListenable<bool> get showPostureListenable => _trackManager.showPostureListenable;
  ValueListenable<List<BallMarker>> get markerListenable => markers.listenable;
  double get poseSmoothingAlpha => poseViewModel.smoothingAlpha;
  String? get selectedParticipantIdentity => _trackManager.selectedParticipantIdentity;
  bool get showSideSheet => _trackManager.showSideSheet;

  RemoteTelemetry get localTelemetry => _telemetryCoordinator.buildLocalTelemetry(_role);

  ValueListenable<RemoteTelemetry?> telemetryListenableFor(String identity) =>
      _trackManager.telemetryListenableFor(identity);

  void _notifySafe() {
    if (!_disposed) notifyListeners();
  }

  void onAppLifecycleStateChanged(AppLifecycleState state) {
    final isBackground =
        state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    if (isBackground && !PipService.isInPip.value) {
      poseViewModel.pause();
    } else if (state == AppLifecycleState.resumed) {
      poseViewModel.resume();
    }
  }

  void togglePosePip() => _trackManager.togglePosePip();
  void togglePosture() => _trackManager.togglePosture();
  void selectParticipant(String? identity) => _trackManager.selectParticipant(identity);
  void closeSideSheet() => _trackManager.closeSideSheet();
  void setPrimaryTrack(ParticipantTrack track) => _trackManager.setPrimaryTrack(track);

  bool switchToNextParticipant() => _trackManager.switchToNextParticipant();
  bool switchToPreviousParticipant() => _trackManager.switchToPreviousParticipant();

  void togglePostureVisibility(String participantIdentity) {
    _trackManager.togglePostureVisibility(participantIdentity, _sortParticipants);
  }

  bool isPostureVisible(String participantIdentity) =>
      _trackManager.isPostureVisible(participantIdentity);

  RemotePosture? posturesForParticipant(Participant participant) =>
      _trackManager.posturesForParticipant(participant);

  RemoteTelemetry? telemetryForParticipant(Participant participant) =>
      _trackManager.telemetryForParticipant(participant);

  // ── Initialisation ──
  Future<void> init(
    Room room,
    EventsListener<RoomEvent> listener, {
    UserRole role = UserRole.trainee,
    VoidCallback? onDisconnected,
  }) async {
    if (_disposed) return;
    _room = room;
    _listener = listener;
    _role = role;
    _onDisconnected = onDisconnected;

    unawaited(WakelockPlus.enable());

    CallForegroundService.setOnEndCall(() {
      unawaited(room.disconnect());
    });
    final firebaseName = AuthService.instance.displayName;
    unawaited(CallForegroundService.start(
      roomName: room.name ?? '',
      username: firebaseName.isNotEmpty
          ? firebaseName
          : displayNameForIdentity(
              room.localParticipant?.identity ?? '',
            ),
    ));

    controlsViewModel.init(
      participant: room.localParticipant!,
      room: room,
      bleService: bleService,
      sensorService: sensorService,
      onBleConnected: onBleConnected,
      onBleDisconnected: onBleDisconnected,
    );

    _setUpListeners();
    _sortParticipants();

    await poseViewModel.init();
    if (_disposed) return;

    _telemetryCoordinator.start(room, _role);

    if (_role.isTrainee) {
      poseViewModel.start(room);
      _updatePoseDestinations();
    }
    _notifySafe();
  }

  void _setUpListeners() {
    final listener = _listener;
    if (listener == null) return;

    listener
      ..on<RoomDisconnectedEvent>((event) {
        debugPrint('🔌 Room disconnected: reason=${event.reason}');
        _telemetryCoordinator.stop();
        markers.clear();
        poseViewModel.stop();
        _onDisconnected?.call();
      })
      ..on<RoomReconnectingEvent>((_) => _notifySafe())
      ..on<RoomReconnectedEvent>((_) => _notifySafe())
      ..on<LocalTrackPublishedEvent>((_) => _sortParticipants())
      ..on<LocalTrackUnpublishedEvent>((_) => _sortParticipants())
      ..on<TrackPublishedEvent>((_) => _sortParticipants())
      ..on<TrackUnpublishedEvent>((_) => _sortParticipants())
      ..on<TrackSubscribedEvent>((_) => _sortParticipants())
      ..on<TrackUnsubscribedEvent>((_) => _sortParticipants())
      ..on<TrackMutedEvent>((_) => _sortParticipants())
      ..on<TrackUnmutedEvent>((_) => _sortParticipants())
      ..on<ActiveSpeakersChangedEvent>((_) => _sortParticipants())
      ..on<ParticipantConnectedEvent>((event) => _sortParticipants())
      ..on<ParticipantDisconnectedEvent>((event) {
        final identity = event.participant.identity;
        _trackManager.removeParticipant(identity);
        _updatePoseDestinations();
        _sortParticipants();
      })
      ..on<DataReceivedEvent>((event) {
        final participant = event.participant;
        if (participant == null) return;

        if (event.topic == 'marker') {
          _handleMarker(event.data);
          return;
        }

        if (event.topic == 'correction' || event.topic == 'posture_correction') {
          _handlePostureCorrection(event.data);
          return;
        }

        if (event.topic == 'engo_message') {
          _handleGlassesMessage(event.data);
          return;
        }

        if (event.topic == 'telemetry') {
          final telemetry = TelemetryCodec.decode(event.data, receivedAt: DateTime.now());
          if (telemetry != null) {
            _updateRemoteTelemetry(participant.identity, telemetry);
            return;
          }
        }

        try {
          final decoded = utf8.decode(event.data);
          _handleIncomingData(participant, decoded, event.topic);
        } catch (err) {
          debugPrint('Failed to decode data: $err');
        }
      });
  }

  void _handleGlassesMessage(Object? data) {
    if (!_role.isTrainee) return;
    final message = GlassesMessage.tryParse(data);
    if (message == null) return;

    unawaited(HapticFeedback.mediumImpact());
    final lines = wrapGlassesText(toGlassesAscii(message.text));
    unawaited(
      bleService.showMessage(lines, message.ttl).then((shown) {
        if (!shown) return;
        unawaited(BeepService.beep());
        Timer(message.ttl, () => _telemetryCoordinator.resetGlassesTimer());
      }),
    );
  }

  void _handleMarker(Object? data) {
    if (!_role.isTrainee) return;
    final marker = BallMarker.tryParse(data, receivedAt: DateTime.now());
    if (marker == null) return;
    unawaited(AthleticHaptics.coachingDoublePulse());
    markers.add(marker);
  }

  void _handlePostureCorrection(Object? data) {
    if (!_role.isTrainee) return;
    unawaited(AthleticHaptics.coachingDoublePulse());
  }

  void _handleIncomingData(
    Participant? participant,
    String decoded,
    String? topic,
  ) {
    if (participant == null) return;
    try {
      final data = jsonDecode(decoded);
      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);

      if (topic == 'telemetry' || map['type'] == 'telemetry') {
        final telemetry = RemoteTelemetry.tryParse(map);
        if (telemetry != null) {
          _updateRemoteTelemetry(participant.identity, telemetry);
        }
        return;
      }
    } catch (error) {
      debugPrint('⚠️ Invalid incoming data: $error');
    }
  }

  void _updateRemoteTelemetry(String identity, RemoteTelemetry telemetry) {
    final prevRole = _trackManager.remoteTelemetryMap[identity]?.role;
    _trackManager.updateRemoteTelemetry(identity, telemetry);
    if (prevRole != telemetry.role) {
      _updatePoseDestinations();
    }
  }

  void _updatePoseDestinations() {
    if (!_role.isTrainee) return;
    final coaches = <String>[
      for (final entry in _trackManager.remoteTelemetryMap.entries)
        if (UserRole.fromWire(entry.value.role).isCoach) entry.key,
    ];
    poseViewModel.setDestinationIdentities(coaches);
  }

  void _sortParticipants() {
    _trackManager.sortParticipants(
      room: _room,
      localTelemetry: localTelemetry,
      poseFrameNotifier: poseViewModel.frameNotifier,
      markerListenable: markerListenable,
      role: _role,
    );
  }

  void onBleConnected() {
    unawaited(HapticFeedback.mediumImpact());
    _telemetryCoordinator.onBleConnected();
  }

  void onBleDisconnected() {
    _telemetryCoordinator.onBleDisconnected();
  }

  // ── Nettoyage ──
  @override
  void dispose() {
    _disposed = true;
    unawaited(WakelockPlus.disable());
    CallForegroundService.setOnEndCall(null);
    unawaited(CallForegroundService.stop());
    _telemetryCoordinator.dispose();
    unawaited(bleService.dispose());
    unawaited(sensorService.dispose());
    poseViewModel.dispose();
    controlsViewModel.dispose();
    markers.dispose();
    _trackManager.dispose();
    unawaited(_listener?.dispose());
    unawaited(_room?.dispose());
    super.dispose();
  }
}
