import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:livekit_client/livekit_client.dart';
import '../../core/ble_sensor_service.dart';
import '../../core/ble_telemetry_service.dart';
import '../../exts.dart';
import '../../theme.dart';
import '../../viewmodels/controls_viewmodel.dart';
import '../utils/ui_utils.dart';

class ControlsWidget extends StatefulWidget {
  final Room room;
  final LocalParticipant participant;

  final BleTelemetryService bleService;
  final BleSensorService sensorService;
  final ControlsViewModel controlsViewModel;
  final VoidCallback onBleConnected;
  final VoidCallback onBleDisconnected;
  final bool showPosture;
  final VoidCallback? onTogglePosture;
  final double postureSmoothingAlpha;
  final Future<void> Function(double alpha)? onSetPostureSmoothingAlpha;

  const ControlsWidget(
    this.room,
    this.participant, {
    required this.bleService,
    required this.sensorService,
    required this.controlsViewModel,
    required this.onBleConnected,
    required this.onBleDisconnected,
    this.showPosture = true,
    this.onTogglePosture,
    this.postureSmoothingAlpha = 1.0,
    this.onSetPostureSmoothingAlpha,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _ControlsWidgetState();
}

class _ControlsWidgetState extends State<ControlsWidget>
    with SingleTickerProviderStateMixin {
  ControlsViewModel get _vm => widget.controlsViewModel;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onViewModelChanged);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _vm.removeListener(_onViewModelChanged);
    _pulseController.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openBleSheet() async {
    await _vm.openBleSheet();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _BleSheetContent(
        bleService: widget.bleService,
        onConnect: (deviceId) async {
          await _vm.connectBleDevice(deviceId);
          widget.onBleConnected();
          if (mounted) setState(() {});
        },
        onDisconnect: () async {
          await _vm.disconnectBleDevice();
          widget.onBleDisconnected();
          if (mounted) setState(() {});
        },
        onToggleDisplay: _vm.toggleDisplaySession,
      ),
    );
    await _vm.closeBleSheet();
  }

  Future<void> _openSensorSheet() async {
    await _vm.openSensorSheet();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, _) =>
            _SensorSheetContent(sensorService: widget.sensorService),
      ),
    );
    await _vm.closeSensorSheet();
  }

  Future<void> _openPostureSmoothingDialog() async {
    final onChange = widget.onSetPostureSmoothingAlpha;
    if (onChange == null) return;
    var pendingAlpha = widget.postureSmoothingAlpha;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Lissage de la posture'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                pendingAlpha >= 1.0
                    ? '1,00 · points bruts, sans lissage'
                    : '${pendingAlpha.toStringAsFixed(2)} · lissage appliqué',
              ),
              Slider(
                value: pendingAlpha,
                min: 0,
                max: 1,
                divisions: 20,
                label: pendingAlpha.toStringAsFixed(2),
                onChanged: (value) => setDialogState(() {
                  pendingAlpha = value;
                }),
              ),
              const Text(
                'Le réglage est mémorisé sur cet appareil. '
                'À 1,00, image et worldLandmarks sont envoyés sans lissage.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                unawaited(onChange(pendingAlpha));
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Appliquer'),
            ),
          ],
        ),
      ),
    );
  }

  void _onTapDisconnect() async {
    final result = await context.showDisconnectDialog();
    if (result == true) await widget.room.disconnect();
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    Color? iconColor,
    double iconSize = 24,
    bool isActive = false,
    Widget? badge,
    Widget? iconWidget,
  }) {
    final iconChild =
        iconWidget ?? Icon(icon, size: iconSize, color: iconColor);
    return AnimatedScale(
      duration: UIUtils.animationDurationFast,
      scale: isActive ? 1.05 : 1.0,
      child: Tooltip(
        message: tooltip,
        decoration: BoxDecoration(
          color: LKColors.surfaceElevated,
          borderRadius: UIUtils.borderRadiusAllSM,
          border: Border.all(color: LKColors.border, width: 0.5),
        ),
        textStyle: TextStyle(
          color: LKColors.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
        padding: UIUtils.paddingHorizontalSM.add(UIUtils.paddingVerticalSM),
        margin: UIUtils.paddingXS,
        child: IconButton(
          onPressed: onPressed,
          icon: badge != null
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    iconChild,
                    Positioned.fill(child: badge),
                  ],
                )
              : iconChild,
          tooltip: tooltip,
          style: IconButton.styleFrom(
            foregroundColor: LKColors.textPrimary,
            backgroundColor: Colors.transparent,
            hoverColor: LKColors.primary.withValues(alpha: 0.1),
            disabledForegroundColor: LKColors.textHint,
            padding: UIUtils.paddingSM,
            shape: RoundedRectangleBorder(
              borderRadius: UIUtils.borderRadiusAllSM,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBleBadge(int battery) {
    return Positioned(
      bottom: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: LKColors.success.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: LKColors.success.withValues(alpha: 0.3)),
        ),
        child: Text(
          '$battery%',
          style: TextStyle(
            fontSize: 9,
            color: LKColors.success,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildSensorBadge() {
    return Positioned(
      bottom: 0,
      right: 0,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: LKColors.success,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: LKColors.success.withValues(alpha: 0.4),
              blurRadius: 4,
              offset: Offset(0, 0),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      //borderRadius: UIUtils.borderRadiusAllSM,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: UIUtils.paddingVerticalSM.add(UIUtils.paddingHorizontalMD),
          decoration: BoxDecoration(
            color: LKColors.surface.withValues(alpha: 0.85),
            borderRadius: UIUtils.noBorderRadius,
            border: Border.all(
              color: LKColors.border.withValues(alpha: 0.3),
              width: 0.5,
            ),
            boxShadow: UIUtils.shadowMD,
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 2,
            runSpacing: 2,
            children: [
              // ── Microphone ──
              if (widget.participant.isMicrophoneEnabled())
                if (lkPlatformIs(PlatformType.android))
                  _buildControlButton(
                    icon: Icons.mic_rounded,
                    onPressed: _vm.disableAudio,
                    tooltip: 'Désactiver le microphone',
                    iconColor: LKColors.textPrimary,
                  )
                else
                  PopupMenuButton<MediaDevice>(
                    icon: UIUtils.textPrimaryIcon(Icons.mic_rounded, size: 24),
                    offset: const Offset(0, -90),
                    tooltip: 'Options microphone',
                    itemBuilder: (BuildContext context) {
                      return [
                        PopupMenuItem<MediaDevice>(
                          value: null,
                          onTap: _vm.toggleMicrophone,
                          child: ListTile(
                            leading: Icon(
                              Icons.mic_off_rounded,
                              color: LKColors.danger,
                            ),
                            title: Text(
                              'Désactiver le microphone',
                              style: UIUtils.labelMedium(context),
                            ),
                            contentPadding: UIUtils.paddingHorizontalSM,
                          ),
                        ),
                        if (_vm.audioInputs != null)
                          ..._vm.audioInputs!.map((device) {
                            return PopupMenuItem<MediaDevice>(
                              value: device,
                              child: ListTile(
                                leading:
                                    device.deviceId ==
                                        widget.room.selectedAudioInputDeviceId
                                    ? Icon(
                                        Icons.check_circle_rounded,
                                        color: LKColors.success,
                                      )
                                    : Icon(
                                        Icons.radio_button_unchecked_rounded,
                                        color: LKColors.textHint,
                                      ),
                                title: Text(
                                  device.label,
                                  style: UIUtils.labelMedium(context),
                                ),
                                contentPadding: UIUtils.paddingHorizontalSM,
                              ),
                              onTap: () => _vm.selectAudioInput(device),
                            );
                          }),
                      ];
                    },
                    shape: RoundedRectangleBorder(
                      borderRadius: UIUtils.borderRadiusAllMD,
                    ),
                    color: LKColors.surfaceElevated,
                    surfaceTintColor: Colors.transparent,
                    elevation: 4,
                    shadowColor: Colors.black.withValues(alpha: 0.3),
                  )
              else
                _buildControlButton(
                  icon: Icons.mic_off_rounded,
                  onPressed: _vm.enableAudio,
                  tooltip: 'Activer le microphone',
                  iconColor: LKColors.danger,
                ),

              // ── Audio output (desktop) ──
              if (!lkPlatformIsMobile())
                PopupMenuButton<MediaDevice>(
                  icon: UIUtils.textPrimaryIcon(
                    Icons.volume_up_rounded,
                    size: 24,
                  ),
                  tooltip: 'Sélectionner la sortie audio',
                  itemBuilder: (BuildContext context) {
                    return [
                      PopupMenuItem<MediaDevice>(
                        value: null,
                        child: ListTile(
                          leading: Icon(
                            Icons.speaker_rounded,
                            color: LKColors.textSecondary,
                          ),
                          title: Text(
                            'Sélectionner la sortie audio',
                            style: UIUtils.labelMedium(context),
                          ),
                          contentPadding: UIUtils.paddingHorizontalSM,
                        ),
                      ),
                      if (_vm.audioOutputs != null)
                        ..._vm.audioOutputs!.map((device) {
                          return PopupMenuItem<MediaDevice>(
                            value: device,
                            child: ListTile(
                              leading:
                                  device.deviceId ==
                                      widget.room.selectedAudioOutputDeviceId
                                  ? Icon(
                                      Icons.check_circle_rounded,
                                      color: LKColors.success,
                                    )
                                  : Icon(
                                      Icons.radio_button_unchecked_rounded,
                                      color: LKColors.textHint,
                                    ),
                              title: Text(
                                device.label,
                                style: UIUtils.labelMedium(context),
                              ),
                              contentPadding: UIUtils.paddingHorizontalSM,
                            ),
                            onTap: () => _vm.selectAudioOutput(device),
                          );
                        }),
                    ];
                  },
                  shape: RoundedRectangleBorder(
                    borderRadius: UIUtils.borderRadiusAllMD,
                  ),
                  color: LKColors.surfaceElevated,
                  surfaceTintColor: Colors.transparent,
                  elevation: 4,
                  shadowColor: Colors.black.withValues(alpha: 0.3),
                ),

              // ── Speakerphone ──
              if (!kIsWeb && lkPlatformIsMobile())
                _buildControlButton(
                  icon: _vm.speakerphoneOn
                      ? Icons.speaker_rounded
                      : Icons.headphones_rounded,
                  onPressed: _vm.toggleSpeakerphone,
                  tooltip: _vm.speakerphoneOn
                      ? 'Passer en haut-parleur'
                      : 'Passer en écouteur',
                  iconColor: _vm.speakerphoneOn
                      ? LKColors.secondary
                      : LKColors.textPrimary,
                ),

              // ── Camera ──
              if (widget.participant.isCameraEnabled())
                _buildControlButton(
                  icon: Icons.videocam_rounded,
                  onPressed: _vm.disableVideo,
                  tooltip: 'Désactiver la caméra',
                  iconColor: LKColors.textPrimary,
                )
              else
                _buildControlButton(
                  icon: Icons.videocam_off_rounded,
                  onPressed: _vm.enableVideo,
                  tooltip: 'Activer la caméra',
                  iconColor: LKColors.danger,
                ),
              _buildControlButton(
                icon: Icons.cameraswitch_rounded,
                onPressed: _vm.switchCamera,
                tooltip: 'Changer de caméra',
                iconColor: LKColors.textPrimary,
              ),

              // ── BLE glasses ──
              _buildControlButton(
                icon: Icons.visibility_rounded,
                iconWidget: _GlassesIcon(
                  size: 24,
                  color: _vm.bleGlassesConnected
                      ? LKColors.success
                      : LKColors.textSecondary,
                ),
                onPressed: _openBleSheet,
                tooltip: _vm.bleGlassesConnected
                    ? 'Lunettes Engo connectées'
                    : 'Connecter les lunettes Engo',
                badge: _vm.bleBattery != null
                    ? _buildBleBadge(_vm.bleBattery!)
                    : null,
                isActive: _vm.bleGlassesConnected,
              ),

              // ── Sensors (HRM + Cadence) ──
              _buildControlButton(
                icon: _vm.sensorHrConnected || _vm.sensorCadenceConnected
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                onPressed: _openSensorSheet,
                tooltip: _vm.sensorHrConnected || _vm.sensorCadenceConnected
                    ? 'Capteurs connectés'
                    : 'Connecter capteurs sport',
                iconColor: _vm.sensorHrConnected
                    ? LKColors.danger
                    : _vm.sensorCadenceConnected
                    ? LKColors.secondary
                    : LKColors.textSecondary,
                badge: (_vm.sensorHrConnected || _vm.sensorCadenceConnected)
                    ? _buildSensorBadge()
                    : null,
                isActive: _vm.sensorHrConnected || _vm.sensorCadenceConnected,
              ),

              // ── Posture ──
              _buildControlButton(
                icon: Icons.accessibility_new_rounded,
                onPressed: widget.onTogglePosture,
                tooltip: widget.showPosture
                    ? 'Masquer la posture'
                    : 'Afficher la posture',
                iconColor: widget.showPosture
                    ? LKColors.success
                    : LKColors.textSecondary,
                isActive: widget.showPosture,
              ),
              if (widget.onSetPostureSmoothingAlpha != null)
                _buildControlButton(
                  icon: Icons.tune_rounded,
                  onPressed: _openPostureSmoothingDialog,
                  tooltip: 'Régler le lissage de la posture',
                ),

              // ── Disconnect ──
              _buildControlButton(
                icon: Icons.call_end_rounded,
                onPressed: _onTapDisconnect,
                tooltip: 'Quitter l\'appel',
                iconColor: LKColors.danger,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── BLE Glasses Bottom Sheet ─────────────────────────────────────────────────
class _BleSheetContent extends StatefulWidget {
  final BleTelemetryService bleService;
  final Future<void> Function(String deviceId) onConnect;
  final Future<void> Function() onDisconnect;
  final Future<void> Function() onToggleDisplay;

  const _BleSheetContent({
    required this.bleService,
    required this.onConnect,
    required this.onDisconnect,
    required this.onToggleDisplay,
  });

  @override
  State<_BleSheetContent> createState() => _BleSheetContentState();
}

class _BleSheetContentState extends State<_BleSheetContent> {
  StreamSubscription<BleConnectionStatus>? _statusSub;
  StreamSubscription<List<DiscoveredDevice>>? _devicesSub;
  BleConnectionStatus _status = BleConnectionStatus.idle();
  List<DiscoveredDevice> _devices = const [];

  @override
  void initState() {
    super.initState();
    _status = widget.bleService.connectionStatus;
    _statusSub = widget.bleService.connectionStatusStream.listen((s) {
      if (!mounted) return;
      setState(() => _status = s);
    });
    _devicesSub = widget.bleService.devicesStream.listen((d) {
      if (!mounted) return;
      setState(() => _devices = d);
    });
  }

  @override
  void dispose() {
    unawaited(_statusSub?.cancel());
    unawaited(_devicesSub?.cancel());
    super.dispose();
  }

  String? get _connectedDeviceId => widget.bleService.connectedDeviceId;
  bool get _isDisplaySessionActive => widget.bleService.isDisplaySessionActive;
  bool get _isBusy =>
      _status.isBusy || _status.phase == BleConnectionPhase.ready;
  List<DiscoveredDevice> get _engoDevices =>
      _devices.where(widget.bleService.isEngoDevice).toList();

  IconData _phaseIcon(BleConnectionPhase phase) {
    switch (phase) {
      case BleConnectionPhase.ready:
        return Icons.check_circle_rounded;
      case BleConnectionPhase.failed:
        return Icons.error_outline_rounded;
      case BleConnectionPhase.disconnected:
        return Icons.link_off_rounded;
      default:
        return Icons.visibility_rounded;
    }
  }

  Color _phaseColor(BleConnectionPhase phase) {
    switch (phase) {
      case BleConnectionPhase.ready:
        return LKColors.success;
      case BleConnectionPhase.failed:
        return LKColors.danger;
      case BleConnectionPhase.disconnected:
        return LKColors.textHint;
      default:
        return LKColors.warning;
    }
  }

  String _statusLabel(BleConnectionPhase phase) {
    switch (phase) {
      case BleConnectionPhase.idle:
        return 'Prêt';
      case BleConnectionPhase.connecting:
        return 'Connexion en cours...';
      case BleConnectionPhase.connected:
        return 'Connexion établie';
      case BleConnectionPhase.initializing:
        return 'Initialisation...';
      case BleConnectionPhase.ready:
        return 'Connecté ✓';
      case BleConnectionPhase.disconnecting:
        return 'Déconnexion...';
      case BleConnectionPhase.disconnected:
        return 'Déconnecté';
      case BleConnectionPhase.failed:
        return 'Échec de connexion';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final hasActiveStatus =
        status.phase != BleConnectionPhase.idle &&
        status.phase != BleConnectionPhase.disconnected;

    return SafeArea(
      child: Container(
        margin: UIUtils.paddingHorizontalLG.add(UIUtils.paddingVerticalLG),
        child: ClipRRect(
          borderRadius: UIUtils.borderRadiusAllLG,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: UIUtils.paddingLG,
              decoration: BoxDecoration(
                color: LKColors.surfaceElevated,
                borderRadius: UIUtils.borderRadiusAllLG,
                border: Border.all(color: LKColors.border, width: 0.5),
                boxShadow: UIUtils.shadowXL,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _GlassesIcon(size: 24, color: LKColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Lunettes Engo',
                        style: UIUtils.titleMedium(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Connectez vos lunettes Engo ActiveLook pour afficher la télémétrie.',
                    style: UIUtils.bodySmall(
                      context,
                    ).copyWith(color: LKColors.textHint),
                  ),
                  const SizedBox(height: 12),
                  if (hasActiveStatus) _buildStatusCard(status),
                  if (hasActiveStatus) const SizedBox(height: 12),
                  Flexible(child: _buildDeviceList(status)),
                  if (_connectedDeviceId != null) ...[
                    const SizedBox(height: 8),
                    _buildSessionSection(),
                  ],
                  const SizedBox(height: 16),
                  _buildActionRow(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(BleConnectionStatus status) {
    final phase = status.phase;
    final isProgress =
        phase == BleConnectionPhase.connecting ||
        phase == BleConnectionPhase.initializing ||
        phase == BleConnectionPhase.disconnecting;
    final sessionMsg =
        phase == BleConnectionPhase.ready && status.message.isNotEmpty
        ? status.message
        : null;

    return AnimatedContainer(
      duration: UIUtils.animationDuration,
      width: double.infinity,
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: _phaseColor(phase).withValues(alpha: 0.08),
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(color: _phaseColor(phase).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: isProgress
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _phaseColor(phase),
                      ),
                    ),
                  )
                : Icon(_phaseIcon(phase), size: 18, color: _phaseColor(phase)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusLabel(phase),
                  style: TextStyle(
                    color: _phaseColor(phase),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (sessionMsg != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sessionMsg,
                    style: TextStyle(
                      color: _phaseColor(phase).withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
                if (status.message.isNotEmpty &&
                    phase != BleConnectionPhase.ready &&
                    !isProgress) ...[
                  const SizedBox(height: 2),
                  Text(
                    status.message,
                    style: TextStyle(color: LKColors.textHint, fontSize: 12),
                  ),
                ],
                if (status.error != null && status.error!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    status.error!,
                    style: TextStyle(color: LKColors.danger, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(BleConnectionStatus status) {
    final engoDevices = _engoDevices;
    if (engoDevices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GlassesIcon(size: 30, color: LKColors.textHint),
            const SizedBox(height: 8),
            Text(
              'Recherche de lunettes Engo...',
              style: UIUtils.bodySmall(context),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: engoDevices.length,
      itemBuilder: (context, i) {
        final device = engoDevices[i];
        final name = device.name.isEmpty
            ? 'Inconnu (${device.id})'
            : device.name;
        final isConnected = _connectedDeviceId == device.id;
        final isConnectingThis =
            status.deviceId == device.id &&
            (status.phase == BleConnectionPhase.connecting ||
                status.phase == BleConnectionPhase.connected ||
                status.phase == BleConnectionPhase.initializing);

        return AnimatedPadding(
          duration: UIUtils.animationDuration,
          padding: UIUtils.paddingVerticalSM,
          child: Card(
            color: LKColors.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: UIUtils.borderRadiusAllMD,
              side: BorderSide(color: LKColors.border, width: 0.5),
            ),
            child: ListTile(
              title: Text(name, style: UIUtils.labelMedium(context)),
              subtitle: Text(
                'RSSI ${device.rssi}',
                style: UIUtils.bodySmall(context),
              ),
              trailing: isConnected
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: LKColors.success.withValues(alpha: 0.1),
                        borderRadius: UIUtils.borderRadiusAllSM,
                      ),
                      child: Text(
                        'Connecté',
                        style: TextStyle(
                          fontSize: 11,
                          color: LKColors.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : isConnectingThis
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          LKColors.primary,
                        ),
                      ),
                    )
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: UIUtils.borderRadiusAllSM,
                        ),
                        side: BorderSide(color: LKColors.border, width: 0.5),
                      ),
                      onPressed: _isBusy
                          ? null
                          : () => widget.onConnect(device.id),
                      child: Text(
                        'Connecter',
                        style: TextStyle(
                          fontSize: 11,
                          color: _isBusy
                              ? LKColors.textHint
                              : LKColors.textPrimary,
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSessionSection() {
    return AnimatedContainer(
      duration: UIUtils.animationDuration,
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: LKColors.surface.withValues(alpha: 0.5),
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(color: LKColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(
            _isDisplaySessionActive
                ? Icons.stop_circle_rounded
                : Icons.play_circle_fill_rounded,
            color: _isDisplaySessionActive ? LKColors.danger : LKColors.success,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _isDisplaySessionActive ? 'Session en cours' : 'Session arrêtée',
              style: UIUtils.labelMedium(context),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            icon: Icon(
              _isDisplaySessionActive
                  ? Icons.stop_rounded
                  : Icons.play_arrow_rounded,
              size: 16,
            ),
            onPressed: widget.onToggleDisplay,
            label: Text(
              _isDisplaySessionActive ? 'Arrêter' : 'Démarrer',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              padding: UIUtils.paddingHorizontalMD.add(
                UIUtils.paddingVerticalSM,
              ),
              backgroundColor: _isDisplaySessionActive
                  ? LKColors.danger
                  : LKColors.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: UIUtils.borderRadiusAllSM,
              ),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => widget.onDisconnect(),
            style: OutlinedButton.styleFrom(
              foregroundColor: LKColors.textPrimary,
              padding: UIUtils.paddingVerticalSM,
              shape: RoundedRectangleBorder(
                borderRadius: UIUtils.borderRadiusAllSM,
              ),
              side: BorderSide(color: LKColors.border, width: 0.5),
            ),
            child: Text('Déconnecter', style: UIUtils.labelMedium(context)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: LKColors.primary,
              foregroundColor: Colors.white,
              padding: UIUtils.paddingVerticalSM,
              shape: RoundedRectangleBorder(
                borderRadius: UIUtils.borderRadiusAllSM,
              ),
            ),
            child: Text(
              'Fermer',
              style: UIUtils.labelMedium(context).copyWith(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Sensor Bottom Sheet ────────────────────────────────────────────────────
class _SensorSheetContent extends StatefulWidget {
  final BleSensorService sensorService;
  const _SensorSheetContent({required this.sensorService});
  @override
  State<_SensorSheetContent> createState() => _SensorSheetContentState();
}

class _SensorSheetContentState extends State<_SensorSheetContent> {
  StreamSubscription<List<DiscoveredDevice>>? _devicesSub;
  StreamSubscription<SensorStatus>? _hrmStatusSub;
  StreamSubscription<SensorStatus>? _cscStatusSub;
  List<DiscoveredDevice> _devices = [];
  SensorStatus _hrmStatus = const SensorStatus(
    type: SensorType.hrm,
    state: SensorConnectionState.disconnected,
  );
  SensorStatus _cscStatus = const SensorStatus(
    type: SensorType.cadence,
    state: SensorConnectionState.disconnected,
  );

  @override
  void initState() {
    super.initState();
    _hrmStatus = widget.sensorService.hrmStatus;
    _cscStatus = widget.sensorService.cscStatus;
    _devices = widget.sensorService.discoveredDevices;
    _devicesSub = widget.sensorService.devicesStream.listen((d) {
      if (!mounted) return;
      setState(() => _devices = d);
    });
    _hrmStatusSub = widget.sensorService.hrmStatusStream.listen((s) {
      if (!mounted) return;
      setState(() => _hrmStatus = s);
    });
    _cscStatusSub = widget.sensorService.cscStatusStream.listen((s) {
      if (!mounted) return;
      setState(() => _cscStatus = s);
    });
  }

  @override
  void dispose() {
    unawaited(_devicesSub?.cancel());
    unawaited(_hrmStatusSub?.cancel());
    unawaited(_cscStatusSub?.cancel());
    super.dispose();
  }

  List<DiscoveredDevice> _devicesForType(SensorType type) => _devices
      .where((d) => widget.sensorService.classifyDevice(d) == type)
      .toList();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: UIUtils.paddingHorizontalLG.add(UIUtils.paddingVerticalLG),
        child: ClipRRect(
          borderRadius: UIUtils.borderRadiusAllLG,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: UIUtils.paddingLG,
              decoration: BoxDecoration(
                color: LKColors.surfaceElevated,
                borderRadius: UIUtils.borderRadiusAllLG,
                border: Border.all(color: LKColors.border, width: 0.5),
                boxShadow: UIUtils.shadowXL,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.favorite_rounded,
                        color: LKColors.danger,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.speed_rounded,
                        color: LKColors.secondary,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Capteurs Sport',
                        style: UIUtils.titleMedium(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Connectez un capteur cardiaque et/ou de cadence.',
                    style: UIUtils.bodySmall(
                      context,
                    ).copyWith(color: LKColors.textHint),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHrmSection(),
                          const SizedBox(height: 16),
                          _buildCscSection(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: LKColors.primary,
                        foregroundColor: Colors.white,
                        padding: UIUtils.paddingVerticalSM,
                        shape: RoundedRectangleBorder(
                          borderRadius: UIUtils.borderRadiusAllSM,
                        ),
                      ),
                      child: Text(
                        'Fermer',
                        style: UIUtils.labelMedium(
                          context,
                        ).copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHrmSection() {
    final devices = _devicesForType(SensorType.hrm);
    return _SensorCard(
      title: 'Fréquence Cardiaque',
      icon: Icons.favorite_rounded,
      iconColor: LKColors.danger,
      status: _hrmStatus,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hrmStatus.isConnected)
            _buildConnectedBanner(
              deviceId: _hrmStatus.deviceId,
              battery: _hrmStatus.battery,
              onDisconnect: () => widget.sensorService.disconnectHrm(),
            )
          else if (_hrmStatus.isBusy)
            Padding(
              padding: UIUtils.paddingVerticalSM,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: LKColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Connexion...', style: UIUtils.bodySmall(context)),
                ],
              ),
            )
          else if (devices.isEmpty)
            Padding(
              padding: UIUtils.paddingVerticalSM,
              child: Center(
                child: Text(
                  'Aucun capteur HRM trouvé',
                  style: UIUtils.bodySmall(
                    context,
                  ).copyWith(color: LKColors.textHint),
                ),
              ),
            )
          else
            ...devices.map(
              (d) => _buildDeviceTile(
                device: d,
                sensorType: SensorType.hrm,
                onConnect: () => widget.sensorService.connectHrm(d.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCscSection() {
    final devices = _devicesForType(SensorType.cadence);
    return _SensorCard(
      title: 'Cadence',
      icon: Icons.speed_rounded,
      iconColor: LKColors.secondary,
      status: _cscStatus,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_cscStatus.isConnected)
            _buildConnectedBanner(
              deviceId: _cscStatus.deviceId,
              battery: _cscStatus.battery,
              onDisconnect: () => widget.sensorService.disconnectCadence(),
            )
          else if (_cscStatus.isBusy)
            Padding(
              padding: UIUtils.paddingVerticalSM,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: LKColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Connexion...', style: UIUtils.bodySmall(context)),
                ],
              ),
            )
          else if (devices.isEmpty)
            Padding(
              padding: UIUtils.paddingVerticalSM,
              child: Center(
                child: Text(
                  'Aucun capteur cadence trouvé',
                  style: UIUtils.bodySmall(
                    context,
                  ).copyWith(color: LKColors.textHint),
                ),
              ),
            )
          else
            ...devices.map(
              (d) => _buildDeviceTile(
                device: d,
                sensorType: SensorType.cadence,
                onConnect: () => widget.sensorService.connectCadence(d.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConnectedBanner({
    String? deviceId,
    int? battery,
    required VoidCallback onDisconnect,
  }) {
    final displayId = deviceId != null && deviceId.length > 8
        ? deviceId.substring(0, 8)
        : deviceId ?? '\u2014';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: LKColors.success.withValues(alpha: 0.08),
        borderRadius: UIUtils.borderRadiusAllSM,
        border: Border.all(color: LKColors.success.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.bluetooth_connected_rounded,
            size: 16,
            color: LKColors.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayId,
                  style: UIUtils.labelMedium(context).copyWith(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (battery != null)
                  Text(
                    'Batterie: $battery%',
                    style: UIUtils.bodySmall(
                      context,
                    ).copyWith(fontSize: 10, color: LKColors.textHint),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: onDisconnect,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              'Déconnecter',
              style: TextStyle(fontSize: 11, color: LKColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTile({
    required DiscoveredDevice device,
    required SensorType sensorType,
    required VoidCallback onConnect,
  }) {
    final name = device.name.isEmpty
        ? 'Inconnu (${device.id.substring(0, math.min(8, device.id.length))})'
        : device.name;
    return AnimatedPadding(
      duration: UIUtils.animationDuration,
      padding: UIUtils.paddingVerticalSM,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          sensorType == SensorType.hrm
              ? Icons.favorite_rounded
              : Icons.speed_rounded,
          size: 18,
          color: sensorType == SensorType.hrm
              ? LKColors.danger
              : LKColors.secondary,
        ),
        title: Text(name, style: UIUtils.bodySmall(context)),
        subtitle: Text(
          'RSSI ${device.rssi}',
          style: UIUtils.bodySmall(
            context,
          ).copyWith(color: LKColors.textHint, fontSize: 10),
        ),
        trailing: OutlinedButton(
          onPressed: onConnect,
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            shape: RoundedRectangleBorder(
              borderRadius: UIUtils.borderRadiusAllSM,
            ),
            side: BorderSide(color: LKColors.border, width: 0.5),
          ),
          child: Text(
            'Connecter',
            style: TextStyle(fontSize: 11, color: LKColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

// ─── Sensor Card widget ─────────────────────────────────────────────────────
class _SensorCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final SensorStatus status;
  final Widget child;

  const _SensorCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.status,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isConnected = status.isConnected;
    return Container(
      width: double.infinity,
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: isConnected
            ? LKColors.success.withValues(alpha: 0.04)
            : LKColors.surface.withValues(alpha: 0.3),
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(
          color: isConnected
              ? LKColors.success.withValues(alpha: 0.3)
              : LKColors.border.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: isConnected ? LKColors.success : iconColor,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isConnected ? LKColors.success : LKColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (isConnected)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: LKColors.success.withValues(alpha: 0.15),
                    borderRadius: UIUtils.borderRadiusAllSM,
                  ),
                  child: Text(
                    'CONNECTÉ',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: LKColors.success,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _GlassesIcon extends StatelessWidget {
  const _GlassesIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GlassesPainter(color: color),
    );
  }
}

class _GlassesPainter extends CustomPainter {
  const _GlassesPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final radius = size.width * 0.23;
    final lensY = size.height * 0.54;
    final left = Offset(size.width * 0.28, lensY);
    final right = Offset(size.width * 0.72, lensY);

    canvas.drawCircle(left, radius, paint);
    canvas.drawCircle(right, radius, paint);
    canvas.drawLine(
      Offset(left.dx + radius, lensY),
      Offset(right.dx - radius, lensY),
      paint,
    );
    canvas.drawLine(
      Offset(left.dx - radius, lensY),
      Offset(size.width * 0.06, lensY - size.height * 0.06),
      paint,
    );
    canvas.drawLine(
      Offset(right.dx + radius, lensY),
      Offset(size.width * 0.94, lensY - size.height * 0.06),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _GlassesPainter oldDelegate) =>
      color != oldDelegate.color;
}
