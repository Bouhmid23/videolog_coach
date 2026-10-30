import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppLifecycleState;
import 'package:flutter/foundation.dart'
    show
        ChangeNotifier,
        ValueListenable,
        ValueNotifier,
        debugPrint,
        VoidCallback;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:geolocator/geolocator.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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

class RoomViewModel extends ChangeNotifier {
  // ── Services ──
  final BleTelemetryService bleService = BleTelemetryService();
  final BleSensorService sensorService = BleSensorService();
  final PoseDetectionViewModel poseViewModel = PoseDetectionViewModel();
  final ControlsViewModel controlsViewModel = ControlsViewModel();

  /// Ballons envoyés par le coach (topic LiveKit `marker`).
  final MarkerController markers = MarkerController();

  // ── Callbacks & lifecycle ──
  VoidCallback? _onDisconnected;
  bool _disposed = false;

  // ── Room references ──
  Room? _room;
  EventsListener<RoomEvent>? _listener;

  // ── Role ──
  UserRole _role = UserRole.trainee;

  // ── Telemetry ──
  Timer? _telemetryTimer;
  double _simT = 0.0;
  DateTime? _lastGlassesDisplayTime;

  // ── GPS ──
  StreamSubscription<Position>? _gpsSub;
  double _totalDistanceMiles = 0.0;
  Position? _lastPosition;

  // ── Sensors ──
  StreamSubscription<int>? _hrmSub;
  StreamSubscription<int>? _cadenceSub;
  StreamSubscription<SensorStatus>? _hrmStatusSub;
  StreamSubscription<SensorStatus>? _cscStatusSub;
  int? _sensorHeartRate;
  int? _sensorCadence;

  // ── BLE glasses ──
  StreamSubscription<SportMetrics>? _bleMetricsSub;
  SportMetrics? _bleMetrics;

  // ── Participants & granular notifiers ──
  List<ParticipantTrack> _participantTracks = [];
  final Map<String, RemotePosture> _remotePostures = {};
  final Map<String, RemoteTelemetry> _remoteTelemetry = {};
  final Map<String, ValueNotifier<RemoteTelemetry?>> _telemetryNotifiers = {};
  final ValueNotifier<bool> _showPostureNotifier = ValueNotifier<bool>(true);

  // ── Posture visibility per remote participant ──
  final Set<String> _hiddenPostures = {};

  // ── Posture PIP & SideSheet ──
  bool _showPosePip = true;
  String? _selectedParticipantIdentity;
  bool _showSideSheet = false;
  ({String identity, ParticipantTrackType type})? _selectedPrimaryTrack;

  // ── Getters ──
  Room? get room => _room;
  EventsListener<RoomEvent>? get listener => _listener;
  UserRole get role => _role;
  List<ParticipantTrack> get participantTracks => _participantTracks;
  int? get sensorHeartRate => _sensorHeartRate;
  int? get sensorCadence => _sensorCadence;
  SportMetrics? get bleMetrics => _bleMetrics;
  double get totalDistanceMiles => _totalDistanceMiles;
  double get totalDistanceKm => _totalDistanceMiles * 1.60934;
  bool get showPosePip => _showPosePip;
  bool get showPosture => _showPostureNotifier.value;
  ValueListenable<bool> get showPostureListenable => _showPostureNotifier;
  ValueListenable<List<BallMarker>> get markerListenable => markers.listenable;
  double get poseSmoothingAlpha => poseViewModel.smoothingAlpha;
  String? get selectedParticipantIdentity => _selectedParticipantIdentity;
  bool get showSideSheet => _showSideSheet;

  ValueNotifier<RemoteTelemetry?> _telemetryNotifierFor(String identity) {
    return _telemetryNotifiers.putIfAbsent(
      identity,
      () => ValueNotifier<RemoteTelemetry?>(_remoteTelemetry[identity]),
    );
  }

  ValueListenable<RemoteTelemetry?> telemetryListenableFor(String identity) =>
      _telemetryNotifierFor(identity);

  void _setTelemetryFor(String identity, RemoteTelemetry telemetry) {
    final notifier = _telemetryNotifierFor(identity);
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

  void togglePosePip() {
    _showPosePip = !_showPosePip;
    _notifySafe();
  }

  void togglePosture() {
    unawaited(HapticFeedback.lightImpact());
    final next = !_showPostureNotifier.value;
    _showPostureNotifier.value = next;
    for (final track in _participantTracks) {
      track.showPosture = next;
    }
  }

  /*Future<void> setPoseSmoothingAlpha(double alpha) async {
    await poseViewModel.setSmoothingAlpha(alpha);
  }*/

  void selectParticipant(String? identity) {
    if (_selectedParticipantIdentity == identity) {
      _showSideSheet = !_showSideSheet;
    } else {
      _selectedParticipantIdentity = identity;
      _showSideSheet = identity != null;
    }
    _notifySafe();
  }

  void setPrimaryTrack(ParticipantTrack track) {
    final selected = (
      identity: track.participant.identity,
      type: track.type,
    );
    if (_selectedPrimaryTrack == selected) return;
    _selectedPrimaryTrack = selected;
    _notifySafe();
  }

  void closeSideSheet() {
    if (!_showSideSheet) return;
    _showSideSheet = false;
    _notifySafe();
  }

  void togglePostureVisibility(String participantIdentity) {
    if (_hiddenPostures.contains(participantIdentity)) {
      _hiddenPostures.remove(participantIdentity);
    } else {
      _hiddenPostures.add(participantIdentity);
    }
    _sortParticipants();
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

  RemoteTelemetry get localTelemetry => RemoteTelemetry(
    heartRate: sensorService.isHrmConnected ? _sensorHeartRate : null,
    cadence: sensorService.isCadenceConnected ? _sensorCadence?.toDouble() : null,
    speed: _lastPosition != null
        ? double.parse((_lastPosition!.speed * 3.6).toStringAsFixed(1))
        : null,
    lat: _lastPosition?.latitude,
    lng: _lastPosition?.longitude,
    altitude: _lastPosition?.altitude,
    bearing: _lastPosition?.heading,
    role: _role.wire,
    receivedAt: DateTime.now(),
  );

  ParticipantTrack? get primaryTrack {
    // 1. Si un flux a été explicitement sélectionné par clic et est toujours présent :
    final selected = _selectedPrimaryTrack;
    if (selected != null) {
      for (final track in _participantTracks) {
        if (track.participant.identity == selected.identity &&
            track.type == selected.type) {
          return track;
        }
      }
    }

    // 2. Par défaut, le flux principal est celui du participant local (caméra).
    for (final track in _participantTracks) {
      if (track.participant is LocalParticipant &&
          track.type == ParticipantTrackType.kUserMedia) {
        return track;
      }
    }

    // 3. Repli s'il n'y a pas de flux caméra local disponible.
    return _participantTracks.isNotEmpty ? _participantTracks.first : null;
  }

  List<ParticipantTrack> get secondaryTracks {
    final primary = primaryTrack;
    if (primary == null) return _participantTracks;
    return _participantTracks.where((t) => t != primary).toList();
  }

  // ── Init ──
  Future<void> init(Room room, EventsListener<RoomEvent> listener,
      {UserRole role = UserRole.trainee, VoidCallback? onDisconnected}) async {
    if (_disposed) return;
    _room = room;
    _listener = listener;
    _role = role;
    _onDisconnected = onDisconnected;

    // Keep screen on during call
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

    _startTelemetry();
    // Le coach est observateur : il ne publie pas de posture.
    if (_role.isTrainee) {
      poseViewModel.start(room);
      _updatePoseDestinations();
    }
    unawaited(_startGps());
    _startSensorListeners();
    _notifySafe();
  }

  // ── Room event listeners ──
  void _setUpListeners() {
    final listener = _listener;
    if (listener == null) return;

    listener
      ..on<RoomDisconnectedEvent>((event) {
        debugPrint('🔌 Room disconnected: reason=${event.reason}');
        _stopTelemetry();
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
        _remotePostures.remove(identity);
        _remoteTelemetry.remove(identity);
        _telemetryNotifiers.remove(identity)?.dispose();
        _updatePoseDestinations();
        _sortParticipants();
      })
      ..on<DataReceivedEvent>((event) {
        final participant = event.participant;
        if (participant == null) return;

        // Ballon du coach : JSON sur le topic `marker`, traité avant le
        // décodage JSON générique.
        if (event.topic == 'marker') {
          _handleMarker(event.data);
          return;
        }

        // Message du coach pour les lunettes Engo : JSON sur le topic `engo_message`.
        if (event.topic == 'engo_message') {
          _handleGlassesMessage(event.data);
          return;
        }

        // Chemin rapide temps réel : paquet binaire compact sur le topic telemetry.
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

  /// Relaie un message du coach aux lunettes Engo (affichage de 5 s, puis le tableau de bord reprend).
  void _handleGlassesMessage(Object? data) {
    if (!_role.isTrainee) return;

    final message = GlassesMessage.tryParse(data);
    if (message == null) return; // Message invalide : ignoré sans erreur.

    unawaited(HapticFeedback.mediumImpact());
    final lines = wrapGlassesText(toGlassesAscii(message.text));
    unawaited(
      bleService.showMessage(lines, message.ttl).then((shown) {
        if (!shown) return;
        unawaited(BeepService.beep()); // petit bip : le sportif regarde ses lunettes
        // Le tableau de bord se redessine au prochain tour de télémétrie après la fin du message.
        Timer(message.ttl, () => _lastGlassesDisplayTime = null);
      }),
    );
  }

  /// Le sportif dessine les ballons du coach sur sa propre vidéo.
  void _handleMarker(Object? data) {
    if (!_role.isTrainee) return;
    final marker = BallMarker.tryParse(data, receivedAt: DateTime.now());
    if (marker == null) return; // Message invalide : ignoré sans erreur.
    unawaited(HapticFeedback.lightImpact());
    markers.add(marker);
  }

  // ── Telemetry ──
  void _startTelemetry() {
    _telemetryTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      _sendTelemetryTick,
    );
    debugPrint('📡 Telemetry started (2 Hz)');
  }

  void _stopTelemetry() {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
  }

  void _sendTelemetryTick(Timer timer) {
    final room = _room;
    if (room == null || room.connectionState != ConnectionState.connected) return;

    _simT += 0.5;
    
    // Use actual sensor data, null if not connected
    final heartRate = sensorService.isHrmConnected ? _sensorHeartRate?.toDouble() : null;
    final cadence = sensorService.isCadenceConnected ? _sensorCadence?.toDouble() : null;

    // Use real GPS data, null if not available (removed simulation)
    final position = _lastPosition;
    double? speed;
    double? lat;
    double? lng;
    double? altitude;
    double? bearing;
    
    if (position != null) {
      speed = double.parse((position.speed * 3.6).toStringAsFixed(1));
      lat = position.latitude;
      lng = position.longitude;
      altitude = position.altitude;
      bearing = position.heading;
    }

    // Encodage binaire compact via TelemetryCodec
    final bytes = TelemetryCodec.encode(
      role: _role.wire,
      speed: speed,
      heartRate: heartRate,
      cadence: cadence,
      lat: lat,
      lng: lng,
      altitude: altitude,
      bearing: bearing,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );

    try {
      room.localParticipant?.publishData(
        bytes,
        reliable: false, // Mode lossy pour le temps réel
        topic: 'telemetry',
      );
    } catch (e) {
      debugPrint('⚠️ Telemetry publish error: $e');
    }

    final localIdentity = room.localParticipant?.identity;
    if (localIdentity != null) {
      _setTelemetryFor(localIdentity, localTelemetry);
    }

    _pushGlassesDisplay(heartRate);
  }

  void _pushGlassesDisplay(double? heartRate) {
    final deviceId = bleService.connectedDeviceId;
    if (deviceId == null || !bleService.isDisplaySessionActive) return;

    final now = DateTime.now();
    if (_lastGlassesDisplayTime != null &&
        now.difference(_lastGlassesDisplayTime!) < const Duration(seconds: 2)) {
      return;
    }
    _lastGlassesDisplayTime = now;

    // Use actual distance; calories estimated via Keytel formula when a heart-rate sensor is present
    final dist = _totalDistanceMiles;
    final kcal = heartRate != null
        ? SportMetrics.estimateKcal(
            bpm: heartRate.round(),
            weightKg: 70,
            ageYears: 30,
            isMale: true,
            durationSeconds: _simT.round(),
          ).clamp(0, 9999)
        : 0;

    unawaited(
      bleService.displayMetrics(
        deviceId,
        distanceMiles: dist,
        bpm: heartRate?.round().clamp(30, 220),
        kcal: kcal,
        cadence: _sensorCadence,
      ),
    );
  }

  // ── GPS ──
  Future<void> _startGps() async {
    _gpsSub?.cancel();

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (_disposed) return;
    if (!serviceEnabled) {
      debugPrint('⚠️ GPS: Location services are disabled');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (_disposed) return;
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (_disposed) return;
      if (permission == LocationPermission.denied) {
        debugPrint('⚠️ GPS: Location permission denied');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('⚠️ GPS: Location permission denied forever');
      return;
    }

    try {
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((position) {
        if (_lastPosition != null) {
          final delta = SportMetrics.haversineDistanceMiles(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            position.latitude,
            position.longitude,
          );
          _totalDistanceMiles += delta;
        }
        _lastPosition = position;
      });
      debugPrint('📍 GPS tracking started');
    } catch (e) {
      debugPrint('⚠️ GPS error: $e');
    }
  }

  void _stopGps() {
    _gpsSub?.cancel();
    _gpsSub = null;
  }

  // ── Sensors ──
  void _startSensorListeners() {
    _hrmSub?.cancel();
    _cadenceSub?.cancel();
    _hrmStatusSub?.cancel();
    _cscStatusSub?.cancel();

    _hrmSub = sensorService.heartRateStream.listen((bpm) {
      if (_sensorHeartRate == bpm) return;
      _sensorHeartRate = bpm;
      final localIdentity = _room?.localParticipant?.identity;
      if (localIdentity != null) {
        _setTelemetryFor(localIdentity, localTelemetry);
      }
    });

    _cadenceSub = sensorService.cadenceStream.listen((rpm) {
      if (_sensorCadence == rpm) return;
      _sensorCadence = rpm;
      final localIdentity = _room?.localParticipant?.identity;
      if (localIdentity != null) {
        _setTelemetryFor(localIdentity, localTelemetry);
      }
    });

    _hrmStatusSub = sensorService.hrmStatusStream.listen((status) {
      debugPrint('💓 HRM status: ${status.state}');
    });

    _cscStatusSub = sensorService.cscStatusStream.listen((status) {
      debugPrint('🚴 CSC status: ${status.state}');
    });
  }

  // ── BLE glasses ──
  void onBleConnected() {
    unawaited(HapticFeedback.mediumImpact());
    _bleMetricsSub?.cancel();
    _bleMetricsSub = bleService.metricsStream.listen((data) {
      _bleMetrics = data;
    });
  }

  void onBleDisconnected() {
    _bleMetrics = null;
  }

  // ── Participant sorting ──
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
    final prevRole = _remoteTelemetry[identity]?.role;
    _remoteTelemetry[identity] = telemetry;
    _setTelemetryFor(identity, telemetry);
    if (prevRole != telemetry.role) {
      _updatePoseDestinations();
    }
  }

  /// Le squelette ne part qu'aux viewers (rôle coach) déjà identifiés.
  /// Tant qu'aucun coach n'est connu, on laisse LiveKit broadcaster par défaut.
  void _updatePoseDestinations() {
    if (!_role.isTrainee) return;
    final coaches = <String>[
      for (final entry in _remoteTelemetry.entries)
        if (UserRole.fromWire(entry.value.role).isCoach) entry.key,
    ];
    poseViewModel.setDestinationIdentities(coaches);
  }

  bool _isDisplayable(Participant p) {
    if (p.kind == ParticipantKind.AGENT) return false;
    if (p.kind != ParticipantKind.STANDARD) return false;
    return p.permissions.canPublish;
  }

  void _sortParticipants() {
    final room = _room;
    if (room == null || _disposed) return;

    final activeIdentities = <String>{
      if (room.localParticipant != null) room.localParticipant!.identity,
      ...room.remoteParticipants.values.where(_isDisplayable).map((p) => p.identity),
    };
    _remotePostures.removeWhere(
      (identity, _) => !activeIdentities.contains(identity),
    );

    final userMediaTracks = <ParticipantTrack>[];
    final screenTracks = <ParticipantTrack>[];

    for (var participant
    in room.remoteParticipants.values.where(_isDisplayable)) {
      var hasUserMediaVideo = false;
      for (var t in participant.videoTrackPublications) {
        if (t.isScreenShare) {
          screenTracks.add(ParticipantTrack(
            participant: participant,
            type: ParticipantTrackType.kScreenShare,
          ));
        } else {
          hasUserMediaVideo = true;
          userMediaTracks.add(ParticipantTrack(
            participant: participant,
            telemetry: _remoteTelemetry[participant.identity],
            telemetryListenable: _telemetryNotifierFor(participant.identity),
          ));
        }
      }
      if (!hasUserMediaVideo) {
        userMediaTracks.add(ParticipantTrack(
          participant: participant,
          type: ParticipantTrackType.kUserMedia,
          telemetry: _remoteTelemetry[participant.identity],
          telemetryListenable: _telemetryNotifierFor(participant.identity),
        ));
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
      final localTel = localTelemetry;
      final localTelNotifier = _telemetryNotifierFor(localParticipant.identity);
      if (!localTel.equalValues(localTelNotifier.value)) {
        localTelNotifier.value = localTel;
      }
      var hasLocalUserMedia = false;
      for (var t in localTracks) {
        if (t.isScreenShare) {
          screenTracks.add(ParticipantTrack(
            participant: localParticipant,
            type: ParticipantTrackType.kScreenShare,
          ));
        } else {
          hasLocalUserMedia = true;
          userMediaTracks.add(ParticipantTrack(
            participant: localParticipant,
            telemetry: localTel,
            telemetryListenable: localTelNotifier,
            poseListenable: poseViewModel.frameNotifier,
            markers: _role.isTrainee ? markerListenable : null,
            showPosture: _showPostureNotifier.value,
            showPostureListenable: _showPostureNotifier,
          ));
        }
      }
      if (!hasLocalUserMedia) {
        userMediaTracks.add(ParticipantTrack(
          participant: localParticipant,
          type: ParticipantTrackType.kUserMedia,
          telemetry: localTel,
          telemetryListenable: localTelNotifier,
          poseListenable: poseViewModel.frameNotifier,
          markers: _role.isTrainee ? markerListenable : null,
          showPosture: _showPostureNotifier.value,
          showPostureListenable: _showPostureNotifier,
        ));
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
      _notifySafe();
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
      final aPub = a[i]
          .participant
          .videoTrackPublications
          .where((e) => e.source == a[i].type.lkVideoSourceType)
          .firstOrNull;
      final bPub = b[i]
          .participant
          .videoTrackPublications
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

  // ── Cleanup ──
  @override
  void dispose() {
    _disposed = true;
    unawaited(WakelockPlus.disable());
    CallForegroundService.setOnEndCall(null);
    unawaited(CallForegroundService.stop());
    _stopTelemetry();
    _stopGps();
    unawaited(_bleMetricsSub?.cancel());
    unawaited(_hrmSub?.cancel());
    unawaited(_cadenceSub?.cancel());
    unawaited(_hrmStatusSub?.cancel());
    unawaited(_cscStatusSub?.cancel());
    unawaited(bleService.dispose());
    unawaited(sensorService.dispose());
    poseViewModel.dispose();
    controlsViewModel.dispose();
    markers.dispose();
    for (final notifier in _telemetryNotifiers.values) {
      notifier.dispose();
    }
    _telemetryNotifiers.clear();
    _showPostureNotifier.dispose();
    unawaited(_listener?.dispose());
    unawaited(_room?.dispose());
    super.dispose();
  }
}
