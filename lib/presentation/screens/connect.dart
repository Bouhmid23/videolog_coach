import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, MethodChannel;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/api_service.dart';
import '../../core/auth_service.dart';
import '../../core/gravity_service.dart';
import '../../data/livekit_token.dart';
import '../../data/mobile_room.dart';
import '../../data/user_role.dart';
import '../../exts.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

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
  });

  final Room room;
  final EventsListener<RoomEvent> listener;
  final UserRole role;
  final String roomName;
  final bool canControlRecording;
}

enum _ConnectStage { idle, preparing, connecting, media }

enum _GpsCheckState { checking, ready, searching, disabled, denied }

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
  static const MethodChannel _micMeterChannel = MethodChannel(
    'videolog/mic_meter',
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
  Timer? _micPollTimer;

  // ── État Capteurs BLE & GPS ──
  StreamSubscription<BleStatus>? _bleStatusSub;
  BleStatus _bleStatus = BleStatus.unknown;
  _GpsCheckState _gpsState = _GpsCheckState.checking;
  double? _gpsAccuracyMeters;

  String get _accountEmail =>
      AuthService.instance.email ?? AuthService.instance.displayName;

  String get _initials {
    final source = _accountEmail.trim();
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
    unawaited(_initPreConnectChecks());
  }

  @override
  void dispose() {
    _micPollTimer?.cancel();
    unawaited(_bleStatusSub?.cancel());
    unawaited(_stopPreviewMedia());
    _micLevel.dispose();
    super.dispose();
  }

  Future<void> _initPreConnectChecks() async {
    if (lkPlatformIs(PlatformType.android)) {
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

  Future<void> _checkPermissions() async {
    for (final perm in [
      Permission.camera,
      Permission.microphone,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ]) {
      final status = await perm.request();
      if (status.isPermanentlyDenied) {
        debugPrint('Permission $perm refusée définitivement');
      }
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
          params: const VideoParameters(dimensions: VideoDimensions(640, 480)),
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
    unawaited(HapticFeedback.lightImpact());
    final nextPosition = _cameraPosition.switched();
    setState(() => _cameraPosition = nextPosition);
    GravityService.instance.frontCamera = nextPosition == CameraPosition.front;
    final track = _previewVideoTrack;
    if (track != null) {
      try {
        await track.setCameraPosition(nextPosition);
        if (mounted) setState(() {});
        return;
      } catch (_) {
        // Recréation de piste en repli si le changement à chaud échoue.
      }
    }
    if (_cameraEnabled) {
      await _startCameraPreview();
    }
  }

  // ── Jauge microphone ───────────────────────────────────────────────────────
  Future<void> _startMicMeter() async {
    _micPollTimer?.cancel();
    if (kIsWeb || !lkPlatformIs(PlatformType.android) || !_micEnabled) {
      _micLevel.value = 0.0;
      return;
    }
    try {
      final started =
          await _micMeterChannel.invokeMethod<bool>('start') ?? false;
      if (!started || !mounted || !_micEnabled) return;
      _micPollTimer = Timer.periodic(const Duration(milliseconds: 90), (_) async {
        if (!mounted || !_micEnabled || _busy) return;
        try {
          final level =
              await _micMeterChannel.invokeMethod<double>('getLevel') ?? 0.0;
          _micLevel.value = level.clamp(0.0, 1.0);
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('[ConnectPage] Jauge micro indisponible: $e');
    }
  }

  Future<void> _stopMicMeter() async {
    _micPollTimer?.cancel();
    _micPollTimer = null;
    _micLevel.value = 0.0;
    if (kIsWeb || !lkPlatformIs(PlatformType.android)) return;
    try {
      await _micMeterChannel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  Future<void> _togglePreviewMic() async {
    unawaited(HapticFeedback.lightImpact());
    setState(() => _micEnabled = !_micEnabled);
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
    setState(() => _gpsState = _GpsCheckState.checking);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) setState(() => _gpsState = _GpsCheckState.disabled);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _gpsState = _GpsCheckState.denied);
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
        _gpsState = _GpsCheckState.ready;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _gpsState = _GpsCheckState.searching);
    } catch (_) {
      if (!mounted) return;
      setState(() => _gpsState = _GpsCheckState.searching);
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

    // Libère la caméra et le micro de prévisualisation avant que WebRTC ne les ouvre.
    await _stopPreviewMedia();

    Room? room;
    EventsListener<RoomEvent>? listener;

    try {
      // L'identité LiveKit est dérivée du UID Firebase par le serveur.
      final tokenResult = await _fetchToken();

      if (mounted) setState(() => _stage = _ConnectStage.connecting);

      room = _createRoom();
      listener = room.createListener();

      try {
        await room.prepareConnection(tokenResult.url, tokenResult.token);
        await room.connect(tokenResult.url, tokenResult.token);
      } catch (_) {
        // Une tentative de connexion peut consommer ou expirer le JWT.
        // Redemander un token avant l'unique nouvelle tentative.
        await room.disconnect();
        final refreshed = await _fetchToken();
        await room.prepareConnection(refreshed.url, refreshed.token);
        await room.connect(refreshed.url, refreshed.token);
      }

      if (mounted) setState(() => _stage = _ConnectStage.media);

      // Publie micro et caméra selon les choix validés sur l'aperçu.
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
        ),
      );
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
          params: const VideoParameters(dimensions: VideoDimensions(640, 480)),
        ),
        defaultAudioPublishOptions: const AudioPublishOptions(
          name: 'custom_audio_track_name',
        ),
        defaultVideoPublishOptions: const VideoPublishOptions(
          simulcast: false,
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
              dimensions: VideoDimensions(640, 480),
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
                        _buildHeroCard(context),
                        SizedBox(height: UIUtils.md),
                        _buildMediaPreviewCard(context),
                        SizedBox(height: UIUtils.md),
                        _buildSensorsStatusCard(context),
                        SizedBox(height: UIUtils.md),
                        _buildAccountCard(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  // ── Mini Aperçu Caméra + Jauge Micro ──────────────────────────────────────
  Widget _buildMediaPreviewCard(BuildContext context) {
    final previewTrack = _previewVideoTrack;

    return Container(
      padding: UIUtils.paddingLG,
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllLG,
        border: Border.all(color: LKColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.center_focus_strong_rounded,
                size: 18,
                color: LKColors.primary,
              ),
              SizedBox(width: UIUtils.sm),
              Expanded(
                child: Text(
                  'Aperçu cadrage & audio',
                  style: UIUtils.labelLarge(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          SizedBox(height: UIUtils.md),
          ClipRRect(
            borderRadius: UIUtils.borderRadiusAllMD,
            child: SizedBox(
              height: 210,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: LKColors.background),
                  if (_cameraEnabled && previewTrack != null)
                    RepaintBoundary(
                      child: VideoTrackRenderer(
                        previewTrack,
                        fit: VideoViewFit.cover,
                        renderMode: VideoRenderMode.auto,
                      ),
                    )
                  else if (_previewInitializing)
                    const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          LKColors.primary,
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Icon(
                        _cameraEnabled
                            ? Icons.videocam_rounded
                            : Icons.videocam_off_rounded,
                        size: 40,
                        color: LKColors.textHint,
                      ),
                    ),
                  // Repères discrets de cadrage (tiers) lorsque la caméra est active
                  if (_cameraEnabled && previewTrack != null)
                    const IgnorePointer(child: _FramingGridOverlay()),

                  // Boutons rapides : Caméra on/off, Switch avant/arrière, Micro on/off
                  Positioned(
                      left: UIUtils.sm,
                      right: UIUtils.sm,
                      bottom: UIUtils.sm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: UIUtils.borderRadiusAllFull,
                        ),
                        child: Text(
                          'Vérifiez votre recul pour la détection de posture',
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: UIUtils.bodySmall(context).copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ),
                  Positioned(
                    //left: UIUtils.sm,
                    right: UIUtils.sm,
                    top: UIUtils.sm,
                    child:
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildPreviewIconButton(
                              icon: _micEnabled
                                  ? Icons.mic_rounded
                                  : Icons.mic_off_rounded,
                              color: _micEnabled
                                  ? Colors.white
                                  : LKColors.danger,
                              tooltip: _micEnabled
                                  ? 'Couper le micro'
                                  : 'Activer le micro',
                              onTap: _busy ? null : _togglePreviewMic,
                            ),
                            const SizedBox(height: 3),
                            _buildPreviewIconButton(
                              icon: _cameraEnabled
                                  ? Icons.videocam_rounded
                                  : Icons.videocam_off_rounded,
                              color: _cameraEnabled
                                  ? Colors.white
                                  : LKColors.danger,
                              tooltip: _cameraEnabled
                                  ? 'Couper la caméra'
                                  : 'Activer la caméra',
                              onTap: _busy ? null : _togglePreviewCamera,
                            ),
                            const SizedBox(height: 3),
                            _buildPreviewIconButton(
                              icon: Icons.cameraswitch_rounded,
                              color: Colors.white,
                              tooltip: 'Basculer avant / arrière',
                              onTap: _busy ? null : _switchPreviewCamera,
                            ),
                          ],
                        ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: UIUtils.md),
          // Jauge niveau microphone isolée par ValueListenableBuilder
          ValueListenableBuilder<double>(
            valueListenable: _micLevel,
            builder: (context, level, _) => _buildMicMeterRow(context, level),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: 0.65),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }

  Widget _buildMicMeterRow(BuildContext context, double level) {
    const int segments = 14;
    final int activeSegments = _micEnabled ? (level * segments).round() : 0;

    return Row(
      children: [
        Icon(
          _micEnabled ? Icons.graphic_eq_rounded : Icons.mic_off_rounded,
          size: 18,
          color: _micEnabled ? LKColors.secondary : LKColors.danger,
        ),
        SizedBox(width: UIUtils.sm),
        Text(
          _micEnabled ? 'Micro' : 'Micro coupé',
          style: UIUtils.bodySmall(context).copyWith(
            fontWeight: FontWeight.w600,
            color: _micEnabled ? LKColors.textPrimary : LKColors.danger,
          ),
        ),
        SizedBox(width: UIUtils.md),
        Expanded(
          child: SizedBox(
            height: 12,
            child: Row(
              children: List.generate(segments, (index) {
                final isLit = index < activeSegments;
                final Color barColor = index >= segments - 2
                    ? LKColors.danger
                    : index >= segments - 5
                    ? LKColors.warning
                    : LKColors.success;
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: isLit
                          ? barColor
                          : LKColors.border.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        SizedBox(width: UIUtils.sm),
        SizedBox(
          width: 38,
          child: Text(
            _micEnabled ? '${(level * 100).round()}%' : 'OFF',
            textAlign: TextAlign.right,
            style: UIUtils.bodySmall(context).copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _micEnabled ? LKColors.textSecondary : LKColors.danger,
            ),
          ),
        ),
      ],
    );
  }

  // ── État Capteurs BLE & GPS ────────────────────────────────────────────────
  Widget _buildSensorsStatusCard(BuildContext context) {
    final (bleLabel, bleSubtitle, bleColor, bleIcon) = _bleStatusPresentation();
    final (gpsLabel, gpsSubtitle, gpsColor, gpsIcon) = _gpsStatusPresentation();

    return Container(
      padding: UIUtils.paddingLG,
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllLG,
        border: Border.all(color: LKColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.sensors_rounded,
                size: 18,
                color: LKColors.secondary,
              ),
              SizedBox(width: UIUtils.sm),
              Expanded(
                child: Text(
                  'État des capteurs (BLE & GPS)',
                  style: UIUtils.labelLarge(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: () {
                  unawaited(HapticFeedback.lightImpact());
                  _startBleStatusMonitor();
                  unawaited(_refreshGpsStatus());
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                color: LKColors.textSecondary,
                tooltip: 'Actualiser l\'état des capteurs',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          SizedBox(height: UIUtils.sm),
          _buildSensorRow(
            context,
            icon: bleIcon,
            title: 'Bluetooth Low Energy (BLE)',
            subtitle: bleSubtitle,
            badgeLabel: bleLabel,
            color: bleColor,
          ),
          _buildConfigDivider(),
          _buildSensorRow(
            context,
            icon: gpsIcon,
            title: 'Géolocalisation GPS',
            subtitle: gpsSubtitle,
            badgeLabel: gpsLabel,
            color: gpsColor,
          ),
        ],
      ),
    );
  }

  (String, String, Color, IconData) _bleStatusPresentation() {
    switch (_bleStatus) {
      case BleStatus.ready:
        return (
          'Prêt',
          'Prêt pour lunettes Engo, cardio HRM et cadence',
          LKColors.success,
          Icons.bluetooth_connected_rounded,
        );
      case BleStatus.poweredOff:
        return (
          'Désactivé',
          'Activez le Bluetooth pour connecter vos capteurs',
          LKColors.danger,
          Icons.bluetooth_disabled_rounded,
        );
      case BleStatus.unauthorized:
        return (
          'Permission',
          'Autorisation Bluetooth requise dans les réglages',
          LKColors.warning,
          Icons.bluetooth_searching_rounded,
        );
      case BleStatus.locationServicesDisabled:
        return (
          'Localisation off',
          'La localisation est requise pour le scan BLE Android',
          LKColors.warning,
          Icons.location_disabled_rounded,
        );
      case BleStatus.unsupported:
        return (
          'Non supporté',
          'Bluetooth Low Energy non disponible sur cet appareil',
          LKColors.textHint,
          Icons.bluetooth_disabled_rounded,
        );
      case BleStatus.unknown:
        return (
          'Vérification…',
          'Initialisation de l\'adaptateur Bluetooth…',
          LKColors.secondary,
          Icons.bluetooth_rounded,
        );
    }
  }

  (String, String, Color, IconData) _gpsStatusPresentation() {
    switch (_gpsState) {
      case _GpsCheckState.ready:
        final acc = _gpsAccuracyMeters != null
            ? ' (±${_gpsAccuracyMeters!.round()} m)'
            : '';
        return (
          'Signal OK$acc',
          'Vitesse et télémétrie extérieure disponibles',
          LKColors.success,
          Icons.gps_fixed_rounded,
        );
      case _GpsCheckState.searching:
        return (
          'Recherche…',
          'GPS actif · Acquisition des satellites en cours',
          LKColors.secondary,
          Icons.gps_not_fixed_rounded,
        );
      case _GpsCheckState.disabled:
        return (
          'Désactivé',
          'Activez la localisation pour la vitesse GPS',
          LKColors.danger,
          Icons.location_disabled_rounded,
        );
      case _GpsCheckState.denied:
        return (
          'Permission',
          'Autorisation de localisation refusée',
          LKColors.warning,
          Icons.location_off_rounded,
        );
      case _GpsCheckState.checking:
        return (
          'Vérification…',
          'Test du capteur GPS…',
          LKColors.secondary,
          Icons.my_location_rounded,
        );
    }
  }

  Widget _buildSensorRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String badgeLabel,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: UIUtils.borderRadiusAllSM,
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        SizedBox(width: UIUtils.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: UIUtils.bodyMedium(
                  context,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                subtitle,
                style: UIUtils.bodySmall(
                  context,
                ).copyWith(color: LKColors.textHint, fontSize: 11),
              ),
            ],
          ),
        ),
        SizedBox(width: UIUtils.sm),
        _buildPill(
          context,
          icon: Icons.circle,
          label: badgeLabel,
          color: color,
        ),
      ],
    );
  }

  Widget _buildHeroCard(BuildContext context) {

    return Container(
      padding: UIUtils.paddingXL,
      decoration: BoxDecoration(
        borderRadius: UIUtils.borderRadiusAllXL,
        border: Border.all(
          color: LKColors.primary.withValues(alpha: 0.28),
          width: 0.5,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            LKColors.primary.withValues(alpha: 0.2),
            LKColors.secondary.withValues(alpha: 0.07),
            LKColors.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: LKColors.primary.withValues(alpha: 0.16),
                  borderRadius: UIUtils.borderRadiusAllLG,
                ),
                child: const Icon(
                  Icons.videocam_rounded,
                  color: LKColors.primary,
                  size: 25,
                ),
              ),
              SizedBox(width: UIUtils.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SESSION SÉLECTIONNÉE',
                      style: UIUtils.bodySmall(context).copyWith(
                        color: LKColors.textHint,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      widget.roomName,
                      style: UIUtils.titleLarge(
                        context,
                      ).copyWith(fontSize: 22, fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: UIUtils.sm, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: UIUtils.borderRadiusAllFull,
        border: Border.all(color: color.withValues(alpha: 0.22), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          SizedBox(width: 5),
          Text(
            label,
            style: UIUtils.bodySmall(
              context,
            ).copyWith(color: color, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(BuildContext context) {
    return Container(
      padding: UIUtils.paddingLG,
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllLG,
        border: Border.all(color: LKColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: LKColors.primary.withValues(alpha: 0.14),
              borderRadius: UIUtils.borderRadiusAllFull,
            ),
            child: Text(
              _initials,
              style: UIUtils.labelLarge(
                context,
              ).copyWith(color: LKColors.primary, fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(width: UIUtils.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _accountEmail,
                  style: UIUtils.bodyMedium(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: LKColors.success,
                        borderRadius: UIUtils.borderRadiusAllFull,
                      ),
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Compte authentifié',
                      style: UIUtils.bodySmall(
                        context,
                      ).copyWith(color: LKColors.textHint, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(
            Icons.verified_user_rounded,
            size: 20,
            color: LKColors.success.withValues(alpha: 0.8),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigDivider() {
    return Container(
      height: 0.5,
      margin: EdgeInsets.symmetric(vertical: UIUtils.sm),
      color: LKColors.border.withValues(alpha: 0.7),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        UIUtils.lg,
        UIUtils.md,
        UIUtils.lg,
        UIUtils.lg,
      ),
      decoration: BoxDecoration(
        color: LKColors.surfaceElevated,
        border: Border(
          top: BorderSide(
            color: LKColors.border.withValues(alpha: 0.7),
            width: 0.5,
          ),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSwitcher(
                duration: UIUtils.animationDuration,
                child: _busy
                    ? ClipRRect(
                        key: const ValueKey('progress'),
                        borderRadius: UIUtils.borderRadiusAllFull,
                        child: const LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: LKColors.border,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            LKColors.primary,
                          ),
                        ),
                      )
                    : const SizedBox(
                        key: ValueKey('progress-placeholder'),
                        height: 3,
                      ),
              ),
              SizedBox(height: UIUtils.md),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : () => _connect(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: LKColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: LKColors.primary.withValues(
                      alpha: 0.4,
                    ),
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: UIUtils.borderRadiusAllMD,
                    ),
                    elevation: 0,
                  ),
                  child: AnimatedSwitcher(
                    duration: UIUtils.animationDuration,
                    child: _busy
                        ? Row(
                            key: const ValueKey('connecting'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: UIUtils.md),
                              Text(
                                _stageLabel,
                                style: UIUtils.labelLarge(context).copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            key: const ValueKey('idle'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.login_rounded,
                                size: 20,
                                color: Colors.white,
                              ),
                              SizedBox(width: UIUtils.sm),
                              Text(
                                _stageLabel,
                                style: UIUtils.labelLarge(context).copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              SizedBox(height: UIUtils.sm),
              Text(
                _busy
                    ? 'Merci de patienter pendant la connexion.'
                    : 'Cadrage et réglages audio/caméra appliqués dès l\'entrée en session.',
                textAlign: TextAlign.center,
                style: UIUtils.bodySmall(
                  context,
                ).copyWith(color: LKColors.textHint, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grille de cadrage discrète (règle des tiers) pour aider le sportif à se positionner.
class _FramingGridOverlay extends StatelessWidget {
  const _FramingGridOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _FramingGridPainter());
  }
}

class _FramingGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = 0.8;

    final thirdW = size.width / 3;
    final thirdH = size.height / 3;

    canvas.drawLine(Offset(thirdW, 0), Offset(thirdW, size.height), paint);
    canvas.drawLine(
      Offset(thirdW * 2, 0),
      Offset(thirdW * 2, size.height),
      paint,
    );
    canvas.drawLine(Offset(0, thirdH), Offset(size.width, thirdH), paint);
    canvas.drawLine(
      Offset(0, thirdH * 2),
      Offset(size.width, thirdH * 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
