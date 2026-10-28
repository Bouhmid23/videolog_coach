import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show ChangeNotifier, ValueListenable, debugPrint, VoidCallback;
import 'package:geolocator/geolocator.dart';
import 'package:livekit_client/livekit_client.dart';

import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/auth_service.dart';
import '../core/ble_sensor_service.dart';
import '../core/ble_telemetry_service.dart';
import '../core/call_foreground_service.dart';
import '../data/ball_marker.dart';
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
  late final ControlsViewModel controlsViewModel;

  /// Ballons envoyés par le coach (topic LiveKit `marker`).
  final MarkerController markers = MarkerController();

  // ── Callbacks ──
  VoidCallback? _onDisconnected;

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

  // ── Participants ──
  List<ParticipantTrack> _participantTracks = [];
  final Map<String, RemotePosture> _remotePostures = {};
  final Map<String, RemoteTelemetry> _remoteTelemetry = {};

  // ── Posture visibility per remote participant ──
  final Set<String> _hiddenPostures = {};

  // ── Posture PIP & SideSheet ──
  bool _showPosePip = true;
  bool _showPosture = true;
  String? _selectedParticipantIdentity;
  bool _showSideSheet = false;

  // ── Getters ──
  Room? get room => _room;
  EventsListener<RoomEvent>? get listener => _listener;
  UserRole get role => _role;
  List<ParticipantTrack> get participantTracks => _participantTracks;
  int? get sensorHeartRate => _sensorHeartRate;
  int? get sensorCadence => _sensorCadence;
  SportMetrics? get bleMetrics => _bleMetrics;
  double get totalDistanceMiles => _totalDistanceMiles;
  bool get showPosePip => _showPosePip;
  bool get showPosture => _showPosture;
  ValueListenable<List<BallMarker>> get markerListenable => markers.listenable;
  double get poseSmoothingAlpha => poseViewModel.smoothingAlpha;
  String? get selectedParticipantIdentity => _selectedParticipantIdentity;
  bool get showSideSheet => _showSideSheet;

  void togglePosePip() {
    _showPosePip = !_showPosePip;
    notifyListeners();
  }

  void togglePosture() {
    _showPosture = !_showPosture;
    for (final track in _participantTracks) {
      track.showPosture = _showPosture;
    }
    notifyListeners();
  }

  Future<void> setPoseSmoothingAlpha(double alpha) async {
    await poseViewModel.setSmoothingAlpha(alpha);
    notifyListeners();
  }

  void selectParticipant(String? identity) {
    if (_selectedParticipantIdentity == identity) {
      _showSideSheet = !_showSideSheet;
    } else {
      _selectedParticipantIdentity = identity;
      _showSideSheet = identity != null;
    }
    notifyListeners();
  }

  void closeSideSheet() {
    _showSideSheet = false;
    notifyListeners();
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
    // Le flux principal est celui du dernier participant distant arrivé.
    // S'il n'y a personne d'autre, on affiche le participant local.
    ParticipantTrack? latestRemote;
    for (final track in _participantTracks) {
      if (track.type != ParticipantTrackType.kUserMedia ||
          track.participant is! RemoteParticipant) {
        continue;
      }
      if (latestRemote == null ||
          track.participant.joinedAt.isAfter(
            latestRemote.participant.joinedAt,
          )) {
        latestRemote = track;
      }
    }
    if (latestRemote != null) return latestRemote;

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

  // ── Init ──
  Future<void> init(Room room, EventsListener<RoomEvent> listener,
      {UserRole role = UserRole.trainee, VoidCallback? onDisconnected}) async {
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

    controlsViewModel = ControlsViewModel();
    controlsViewModel.init(
      participant: room.localParticipant!,
      room: room,
      bleService: bleService,
      sensorService: sensorService,
      onBleConnected: onBleConnected,
      onBleDisconnected: onBleDisconnected,
    );

    room.addListener(_onRoomDidUpdate);
    _setUpListeners();
    _sortParticipants();

    await poseViewModel.init();

    _startTelemetry();
    // Le coach est observateur : il ne publie pas de posture.
    if (_role.isTrainee) {
      poseViewModel.start(room);
      _updatePoseDestinations();
    }
    _startGps();
    _startSensorListeners();
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
      ..on<ParticipantEvent>((event) => _sortParticipants())
      ..on<LocalTrackPublishedEvent>((_) => _sortParticipants())
      ..on<LocalTrackUnpublishedEvent>((_) => _sortParticipants())
      ..on<TrackSubscribedEvent>((_) => _sortParticipants())
      ..on<TrackUnsubscribedEvent>((_) => _sortParticipants())
      ..on<ParticipantConnectedEvent>((event) => _sortParticipants())
      ..on<ParticipantDisconnectedEvent>((event) {
        _remotePostures.remove(event.participant.identity);
        _remoteTelemetry.remove(event.participant.identity);
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

        // Chemin rapide temps réel : paquet binaire compact sur le topic posture.
        /*if (event.topic == 'posture') {
          final posture = RemotePosture.tryParseBinary(event.data);
          if (posture != null) {
            _remotePostures[participant.identity] = posture;
            _sortParticipants();
            return;
          }
        }*/

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

  /// Le sportif dessine les ballons du coach sur sa propre vidéo.
  void _handleMarker(Object? data) {
    if (!_role.isTrainee) return;
    final marker = BallMarker.tryParse(data, receivedAt: DateTime.now());
    if (marker == null) return; // Message invalide : ignoré sans erreur.
    markers.add(marker);
  }

  void _onRoomDidUpdate() => _sortParticipants();

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
      _refreshTrackTelemetry(localIdentity, localTelemetry);
    }
    notifyListeners();

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

    // Use actual distance; calories only when a heart-rate sensor is present
    final dist = _totalDistanceMiles;
    final kcal = heartRate != null
        ? (heartRate * 0.05 * _simT / 60).round().clamp(0, 9999)
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
    if (!serviceEnabled) {
      debugPrint('⚠️ GPS: Location services are disabled');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
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
      _sensorHeartRate = bpm;
      notifyListeners();
    });

    _cadenceSub = sensorService.cadenceStream.listen((rpm) {
      _sensorCadence = rpm;
      notifyListeners();
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
    _bleMetricsSub?.cancel();
    _bleMetricsSub = bleService.metricsStream.listen((data) {
      _bleMetrics = data;
      notifyListeners();
    });
    notifyListeners();
  }

  void onBleDisconnected() {
    _bleMetrics = null;
    notifyListeners();
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

      /*if (topic == 'posture' || map['type'] == 'posture') {
        final posture = RemotePosture.tryParse(map);
        if (posture != null) {
          _remotePostures[participant.identity] = posture;
          _sortParticipants();
        }
        return;
      }*/
    } catch (error) {
      debugPrint('⚠️ Invalid incoming data: $error');
    }
  }

  void _updateRemoteTelemetry(String identity, RemoteTelemetry telemetry) {
    _remoteTelemetry[identity] = telemetry;
    _refreshTrackTelemetry(identity, telemetry);
    _updatePoseDestinations();
    notifyListeners();
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

  void _refreshTrackTelemetry(String identity, RemoteTelemetry telemetry) {
    for (final track in _participantTracks) {
      if (track.type == ParticipantTrackType.kUserMedia &&
          track.participant.identity == identity) {
        track.telemetry = telemetry;
      }
    }
  }

  void _sortParticipants() {
    final room = _room;
    if (room == null) return;

    final activeIdentities = <String>{
      if (room.localParticipant != null) room.localParticipant!.identity,
      ...room.remoteParticipants.values.map((p) => p.identity),
    };
    _remotePostures.removeWhere(
      (identity, _) => !activeIdentities.contains(identity),
    );

    final userMediaTracks = <ParticipantTrack>[];
    final screenTracks = <ParticipantTrack>[];

    for (var participant in room.remoteParticipants.values) {
      for (var t in participant.videoTrackPublications) {
        if (t.isScreenShare) {
          screenTracks.add(ParticipantTrack(
            participant: participant,
            type: ParticipantTrackType.kScreenShare,
          ));
        } else {
          userMediaTracks.add(ParticipantTrack(
            participant: participant,
            //posture: _remotePostures[participant.identity],
            telemetry: _remoteTelemetry[participant.identity],
            //showPosture: _showPosePip && isPostureVisible(participant.identity),
            //onTogglePosture: () => togglePostureVisibility(participant.identity),
          ));
        }
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

    final localTracks = room.localParticipant?.videoTrackPublications;
    if (localTracks != null) {
      for (var t in localTracks) {
        if (t.isScreenShare) {
          screenTracks.add(ParticipantTrack(
            participant: room.localParticipant!,
            type: ParticipantTrackType.kScreenShare,
          ));
        } else {
          userMediaTracks.add(ParticipantTrack(
            participant: room.localParticipant!,
            //posture: poseViewModel.currentPosture,
            telemetry: localTelemetry,
            poseListenable: poseViewModel.frameNotifier,
            markers: _role.isTrainee ? markerListenable : null,
            showPosture: _showPosture,
          ));
        }
      }
    }

    _participantTracks = [...screenTracks, ...userMediaTracks];
    notifyListeners();
  }

  // ── Cleanup ──
  @override
  void dispose() {
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
    _room?.removeListener(_onRoomDidUpdate);
    unawaited(_listener?.dispose());
    unawaited(_room?.dispose());
    super.dispose();
  }
}
