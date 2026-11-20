import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show EventChannel, HapticFeedback;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/account_controller.dart';
import '../../core/api_service.dart';
import '../../core/athletic_haptics.dart';
import '../../core/auth_service.dart';
import '../../core/gravity_service.dart';
import '../../data/livekit_token.dart';
import '../../data/mobile_room.dart';
import '../../data/room_lobby.dart';
import '../../data/user_role.dart';
import '../../exts.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';
import '../widgets/connect/connect_cards.dart';
import '../widgets/connect/connect_media_preview_card.dart';
import '../widgets/connect/connect_sensors_status_card.dart';
import '../widgets/room_lobby_card.dart';

// Config POC
const String kDefaultRoom = 'poc-room';

/// Arguments passés à l'écran de session.
class RoomRouteArgs {
  const RoomRouteArgs({
    required this.room,
    required this.listener,
    required this.role,
    required this.roomName,
    required this.canControlRecording,
    this.knownParticipantNames = const {},
  });

  final Room room;
  final EventsListener<RoomEvent> listener;
  final UserRole role;
  final String roomName;
  final bool canControlRecording;
  final Map<String, String> knownParticipantNames;
}

enum _ConnectStage { idle, preparing, connecting, media }

// -----------------------------------------------------------------------------
// ConnectPage
// -----------------------------------------------------------------------------

class ConnectPage extends StatefulWidget {
  const ConnectPage({
    super.key,
    this.roomName = kDefaultRoom,
    this.canControlRecording = false,
    this.room,
  });

  final String roomName;
  final bool canControlRecording;
  final MobileRoom? room;

  @override
  State<StatefulWidget> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  static const EventChannel _micMeterStreamChannel = EventChannel(
    'videolog/mic_meter_stream',
  );

  bool _busy = false;
  _ConnectStage _stage = _ConnectStage.idle;
  final UserRole _role = UserRole.trainee;

  // ── Prévisualisation Caméra & Micro ──
  LocalVideoTrack? _previewVideoTrack;
  bool _previewInitializing = false;
  bool _cameraEnabled = true;
  bool _micEnabled = true;
  CameraPosition _cameraPosition = CameraPosition.front;
  final ValueNotifier<double> _micLevel = ValueNotifier<double>(0.0);
  StreamSubscription<double>? _micMeterSub;

  // ── État Capteurs BLE & GPS ──
  StreamSubscription<BleStatus>? _bleStatusSub;
  BleStatus _bleStatus = BleStatus.unknown;
  GpsCheckState _gpsState = GpsCheckState.checking;
  double? _gpsAccuracyMeters;
  bool _hasPermanentlyDeniedPermissions = false;

  // ── Lobby (participants invités / connectés) ──
  RoomLobby? _lobby;
  bool _lobbyLoading = true;
  String? _lobbyError;

  String get _accountDisplayLabel {
    final full = AccountController.instance.displayName.trim();
    if (full.isNotEmpty) return full;
    return AuthService.instance.email ?? AuthService.instance.displayName;
  }

  String get _initials {
    final source = _accountDisplayLabel.trim();
    if (source.isEmpty) return '?';
    final parts = source
        .split(RegExp(r'[\s@._-]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return source.substring(0, 1).toUpperCase();
  }

  String get _stageLabel {
    switch (_stage) {
      case _ConnectStage.preparing:
        return 'PRÉPARATION...';
      case _ConnectStage.connecting:
        return 'CONNEXION...';
      case _ConnectStage.media:
        return 'ACTIVATION MÉDIA...';
      case _ConnectStage.idle:
        return 'REJOINDRE MAINTENANT';
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadLobby());
    unawaited(_initPreConnectChecks());
  }

  Future<void> _loadLobby({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _lobbyLoading = true;
        _lobbyError = null;
      });
    }
    try {
      final fetched = await ApiService.getRoomLobby(widget.roomName);
      if (!mounted) return;
      setState(() {
        _lobby = fetched;
        _lobbyLoading = false;
        _lobbyError = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _lobbyLoading = false;
        _lobbyError = error.detail ?? error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lobbyLoading = false;
        _lobbyError = 'Liste des participants indisponible pour le moment.';
      });
    }
  }

  @override
  void dispose() {
    unawaited(_micMeterSub?.cancel());
    unawaited(_bleStatusSub?.cancel());
    unawaited(_stopPreviewMedia());
    _micLevel.dispose();
    super.dispose();
  }

  Future<void> _initPreConnectChecks() async {
    if (lkPlatformIsMobile()) {
      await _checkPermissions();
    }
    if (!mounted) return;
    _startBleStatusMonitor();
    unawaited(_refreshGpsStatus());
    if (_cameraEnabled) {
      unawaited(_startCameraPreview());
    }
    if (_micEnabled) {
      unawaited(_startMicMeter());
    }
  }

  List<Permission> _requiredPermissions() => [
    Permission.camera,
    Permission.microphone,
    if (lkPlatformIs(PlatformType.android)) ...[
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ] else if (lkPlatformIs(PlatformType.iOS)) ...[
      Permission.bluetooth,
    ],
    Permission.locationWhenInUse,
  ];

  Future<void> _checkPermissions() async {
    final permissions = _requiredPermissions();
    final pending = <Permission>[];
    var permanentlyDenied = false;

    for (final perm in permissions) {
      final status = await perm.status;
      if (status.isPermanentlyDenied) {
        permanentlyDenied = true;
      } else if (!status.isGranted && !status.isLimited) {
        pending.add(perm);
      }
    }

    if (mounted) {
      setState(() => _hasPermanentlyDeniedPermissions = permanentlyDenied);
    }
    if (pending.isEmpty || !mounted) return;

    final shouldRequest = await showConnectPrePermissionRationaleSheet(context);
    if (shouldRequest != true || !mounted) return;

    var anyPermanentlyDenied = permanentlyDenied;
    for (final perm in pending) {
      final status = await perm.request();
      if (status.isPermanentlyDenied) {
        anyPermanentlyDenied = true;
        debugPrint('Permission $perm refusée définitivement');
      }
    }
    if (mounted) {
      setState(() => _hasPermanentlyDeniedPermissions = anyPermanentlyDenied);
    }
  }

  // ── Aperçu caméra ──────────────────────────────────────────────────────────
  Future<void> _startCameraPreview() async {
    if (_previewInitializing || _busy || !mounted) return;
    setState(() => _previewInitializing = true);
    try {
      final oldTrack = _previewVideoTrack;
      _previewVideoTrack = null;
      if (oldTrack != null) {
        await oldTrack.stop();
        await oldTrack.dispose();
      }
      final track = await LocalVideoTrack.createCameraTrack(
        CameraCaptureOptions(
          cameraPosition: _cameraPosition,
          maxFrameRate: 30,
          params: const VideoParameters(dimensions: VideoDimensions(1280, 720)),
        ),
      );
      if (!mounted || !_cameraEnabled || _busy) {
        await track.stop();
        await track.dispose();
        return;
      }
      GravityService.instance.frontCamera =
          _cameraPosition == CameraPosition.front;
      setState(() => _previewVideoTrack = track);
    } catch (e) {
      debugPrint('[ConnectPage] Aperçu caméra indisponible: $e');
    } finally {
      if (mounted) {
        setState(() => _previewInitializing = false);
      }
    }
  }

  Future<void> _stopCameraPreview() async {
    final track = _previewVideoTrack;
    _previewVideoTrack = null;
    if (mounted) setState(() {});
    if (track != null) {
      try {
        await track.stop();
      } catch (_) {}
      try {
        await track.dispose();
      } catch (_) {}
    }
  }

  Future<void> _togglePreviewCamera() async {
    unawaited(HapticFeedback.lightImpact());
    setState(() => _cameraEnabled = !_cameraEnabled);
    if (_cameraEnabled) {
      await _startCameraPreview();
    } else {
      await _stopCameraPreview();
    }
  }

  Future<void> _switchPreviewCamera() async {
    unawaited(AthleticHaptics.participantSwitched());
    final nextPosition = _cameraPosition.switched();
    setState(() => _cameraPosition = nextPosition);
    GravityService.instance.frontCamera = nextPosition == CameraPosition.front;
    final track = _previewVideoTrack;
    if (track != null) {
      try {
        await track.setCameraPosition(nextPosition);
        if (mounted) setState(() {});
        return;
      } catch (_) {}
    }
    if (_cameraEnabled) {
      await _startCameraPreview();
    }
  }

  // ── Jauge microphone ───────────────────────────────────────────────────────
  Future<void> _startMicMeter() async {
    await _stopMicMeter();
    if (kIsWeb || !lkPlatformIsMobile() || !_micEnabled) {
      _micLevel.value = 0.0;
      return;
    }
    try {
      _micMeterSub = _micMeterStreamChannel
          .receiveBroadcastStream()
          .map((dynamic event) => (event as num).toDouble())
          .listen(
            (level) {
              if (mounted && _micEnabled && !_busy) {
                _micLevel.value = level.clamp(0.0, 1.0);
              }
            },
            onError: (Object error) {
              debugPrint('[ConnectPage] Jauge micro flux erreur: $error');
              if (mounted) _micLevel.value = 0.0;
            },
          );
    } catch (e) {
      debugPrint('[ConnectPage] Jauge micro indisponible: $e');
    }
  }

  Future<void> _stopMicMeter() async {
    await _micMeterSub?.cancel();
    _micMeterSub = null;
    _micLevel.value = 0.0;
  }

  Future<void> _togglePreviewMic() async {
    final next = !_micEnabled;
    unawaited(AthleticHaptics.micToggled(muted: !next));
    setState(() => _micEnabled = next);
    if (_micEnabled) {
      await _startMicMeter();
    } else {
      await _stopMicMeter();
    }
  }

  Future<void> _stopPreviewMedia() async {
    await Future.wait([_stopMicMeter(), _stopCameraPreview()]);
  }

  // ── État Capteurs BLE & GPS ────────────────────────────────────────────────
  void _startBleStatusMonitor() {
    if (kIsWeb || !lkPlatformIsMobile()) return;
    unawaited(_bleStatusSub?.cancel());
    try {
      final ble = FlutterReactiveBle();
      _bleStatus = ble.status;
      _bleStatusSub = ble.statusStream.listen((status) {
        if (!mounted) return;
        setState(() => _bleStatus = status);
      }, onError: (_) {});
    } catch (e) {
      debugPrint('[ConnectPage] BLE status indisponible: $e');
    }
  }

  Future<void> _refreshGpsStatus() async {
    if (!mounted) return;
    setState(() => _gpsState = GpsCheckState.checking);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) setState(() => _gpsState = GpsCheckState.disabled);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _gpsState = GpsCheckState.denied);
        return;
      }

      Position? pos = await Geolocator.getLastKnownPosition();
      pos ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 4),
        ),
      );
      if (!mounted) return;
      setState(() {
        _gpsAccuracyMeters = pos?.accuracy;
        _gpsState = GpsCheckState.ready;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _gpsState = GpsCheckState.searching);
    } catch (_) {
      if (!mounted) return;
      setState(() => _gpsState = GpsCheckState.searching);
    }
  }

  Future<LiveKitToken> _fetchToken() {
    return ApiService.getLiveKitToken(widget.roomName);
  }

  Future<void> _connect(BuildContext ctx) async {
    if (_busy) return;
    unawaited(HapticFeedback.mediumImpact());
    setState(() {
      _busy = true;
      _stage = _ConnectStage.preparing;
    });

    await _stopPreviewMedia();

    Room? room;
    EventsListener<RoomEvent>? listener;

    try {
      final tokenResult = await _fetchToken();

      if (mounted) setState(() => _stage = _ConnectStage.connecting);

      room = _createRoom();
      listener = room.createListener();

      try {
        await room.prepareConnection(tokenResult.url, tokenResult.token);
        await room.connect(tokenResult.url, tokenResult.token);
      } catch (_) {
        await room.disconnect();
        final refreshed = await _fetchToken();
        await room.prepareConnection(refreshed.url, refreshed.token);
        await room.connect(refreshed.url, refreshed.token);
      }

      if (mounted) setState(() => _stage = _ConnectStage.media);

      await _publishDefaultDevices(room);

      if (!ctx.mounted) {
        await room.disconnect();
        await listener.dispose();
        return;
      }

      ctx.pushReplacement(
        '/room',
        extra: RoomRouteArgs(
          room: room,
          listener: listener,
          role: _role,
          roomName: widget.roomName,
          canControlRecording: widget.canControlRecording,
          knownParticipantNames: _lobby?.namesByUid ?? const {},
        ),
      );
    } on ApiException catch (error) {
      debugPrint('Erreur API connexion (${error.statusCode}): $error');
      await room?.disconnect();
      await listener?.dispose();
      if (!ctx.mounted) return;
      if (error.isGone || error.isNotFound) {
        await showDialog<void>(
          context: ctx,
          builder: (dCtx) => AlertDialog(
            title: Text(
              error.isGone ? 'Session expirée' : 'Session terminée',
            ),
            content: Text(error.detail ?? error.message),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dCtx).pop(),
                child: const Text('Retour aux sessions'),
              ),
            ],
          ),
        );
        if (ctx.mounted) {
          ctx.pop(true);
        }
        return;
      }
      if (mounted) {
        if (_cameraEnabled) unawaited(_startCameraPreview());
        if (_micEnabled) unawaited(_startMicMeter());
      }
      await ctx.showErrorDialog(error);
    } catch (error) {
      debugPrint('Erreur connexion: $error');
      await room?.disconnect();
      await listener?.dispose();
      if (mounted) {
        if (_cameraEnabled) unawaited(_startCameraPreview());
        if (_micEnabled) unawaited(_startMicMeter());
      }
      if (!ctx.mounted) return;
      await ctx.showErrorDialog(error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _stage = _ConnectStage.idle;
        });
      }
    }
  }

  Room _createRoom() {
    const cameraEncoding = VideoEncoding(
      maxBitrate: 2 * 1000 * 1000,
      maxFramerate: 30,
    );
    const screenEncoding = VideoEncoding(
      maxBitrate: 3 * 1000 * 1000,
      maxFramerate: 15,
    );

    return Room(
      roomOptions: RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultCameraCaptureOptions: CameraCaptureOptions(
          cameraPosition: _cameraPosition,
          maxFrameRate: 30,
          params: const VideoParameters(dimensions: VideoDimensions(1280, 720)),
        ),
        defaultAudioPublishOptions: const AudioPublishOptions(
          name: 'custom_audio_track_name',
        ),
        defaultVideoPublishOptions: const VideoPublishOptions(
          simulcast: true,
          videoCodec: 'H264',
          backupVideoCodec: BackupVideoCodec(enabled: true),
          videoEncoding: cameraEncoding,
          screenShareEncoding: screenEncoding,
        ),
      ),
    );
  }

  Future<void> _publishDefaultDevices(Room room) async {
    final local = room.localParticipant;
    if (local == null) return;

    if (_micEnabled) {
      try {
        await local.setMicrophoneEnabled(true);
      } catch (error) {
        debugPrint('Microphone indisponible: $error');
      }
    }

    if (_cameraEnabled) {
      try {
        await local.setCameraEnabled(
          true,
          cameraCaptureOptions: CameraCaptureOptions(
            cameraPosition: _cameraPosition,
            maxFrameRate: 30,
            params: const VideoParameters(
              dimensions: VideoDimensions(1280, 720),
            ),
          ),
        );
      } catch (error) {
        debugPrint('Caméra indisponible: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LKColors.background,
      appBar: AppBar(
        backgroundColor: LKColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: LKColors.textPrimary,
        elevation: 0,
        title: Text(
          'Rejoindre la session',
          style: UIUtils.titleMedium(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  UIUtils.lg,
                  UIUtils.sm,
                  UIUtils.lg,
                  UIUtils.xl,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ConnectHeroCard(
                          title: _lobby?.displayTitle ??
                              widget.room?.displayTitle ??
                              widget.roomName,
                          orgName: _lobby?.orgName,
                        ),
                        if (_hasPermanentlyDeniedPermissions) ...[
                          SizedBox(height: UIUtils.md),
                          const ConnectPermissionSettingsBanner(),
                        ],
                        SizedBox(height: UIUtils.md),
                        RoomLobbyCard(
                          lobby: _lobby,
                          loading: _lobbyLoading,
                          error: _lobbyError,
                          currentUid: AccountController.instance.uid,
                          onRefresh: () {
                            unawaited(HapticFeedback.lightImpact());
                            unawaited(_loadLobby());
                          },
                        ),
                        SizedBox(height: UIUtils.md),
                        ConnectMediaPreviewCard(
                          previewVideoTrack: _previewVideoTrack,
                          previewInitializing: _previewInitializing,
                          cameraEnabled: _cameraEnabled,
                          micEnabled: _micEnabled,
                          busy: _busy,
                          micLevelListenable: _micLevel,
                          onToggleMic: _togglePreviewMic,
                          onToggleCamera: _togglePreviewCamera,
                          onSwitchCamera: _switchPreviewCamera,
                        ),
                        SizedBox(height: UIUtils.md),
                        ConnectSensorsStatusCard(
                          bleStatus: _bleStatus,
                          gpsState: _gpsState,
                          gpsAccuracyMeters: _gpsAccuracyMeters,
                          onRefresh: () {
                            unawaited(HapticFeedback.lightImpact());
                            _startBleStatusMonitor();
                            unawaited(_refreshGpsStatus());
                          },
                        ),
                        SizedBox(height: UIUtils.md),
                        ConnectAccountCard(
                          initials: _initials,
                          displayLabel: _accountDisplayLabel,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ConnectBottomBar(
              busy: _busy,
              stageLabel: _stageLabel,
              onConnect: (_busy || (_lobby != null && !_lobby!.accessible))
                  ? null
                  : () => _connect(context),
            ),
          ],
        ),
      ),
    );
  }
}
