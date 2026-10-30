import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:livekit_client/livekit_client.dart';
import '../../core/ble_sensor_service.dart';
import '../../core/ble_telemetry_service.dart';
import '../../core/recording_controller.dart';
import '../../exts.dart';
import '../../theme.dart';
import '../../viewmodels/controls_viewmodel.dart';
import '../utils/ui_utils.dart';
import 'controls/ble_sheet_content.dart';
import 'controls/glasses_icon.dart';
import 'controls/sensor_sheet_content.dart';
import 'recording_controls.dart';
export 'controls/ble_sheet_content.dart';
export 'controls/glasses_icon.dart';
export 'controls/posture_smoothing_dialog.dart';
export 'controls/sensor_sheet_content.dart';

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
  //final Future<void> Function(double alpha)? onSetPostureSmoothingAlpha;
  final RecordingController? recordingController;

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
    this.postureSmoothingAlpha = 0.5,
    //this.onSetPostureSmoothingAlpha,
    this.recordingController,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _ControlsWidgetState();
}

class _ControlsWidgetState extends State<ControlsWidget> {
  ControlsViewModel get _vm => widget.controlsViewModel;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onViewModelChanged);
  }

  @override
  void dispose() {
    _vm.removeListener(_onViewModelChanged);
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
      builder: (_) => BleSheetContent(
        bleService: widget.bleService,
        onConnect: (deviceId) async {
          await _vm.connectBleDevice(deviceId);
          if (mounted) setState(() {});
        },
        onDisconnect: () async {
          await _vm.disconnectBleDevice();
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
      builder: (_) => SensorSheetContent(sensorService: widget.sensorService),
    );
    await _vm.closeSensorSheet();
  }

  /*Future<void> _openPostureSmoothingDialog() async {
    final onChange = widget.onSetPostureSmoothingAlpha;
    if (onChange == null) return;
    await PostureSmoothingDialog.show(
      context,
      initialAlpha: widget.postureSmoothingAlpha,
      onApply: onChange,
    );
  }*/

  void _onTapDisconnect() async {
    final result = await context.showDisconnectDialog();
    if (result == true) await widget.room.disconnect();
  }

  Widget _buildCircularBlurContainer({
    required Widget child,
    bool isActive = false,
    Widget? badge,
  }) {
    final circle = Container(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Enhanced outdoor/sunlight support: deeper contrast background and crisp border
        color: LKColors.lkDarkBlue.withValues(alpha: 0.92),
        border: Border.all(
          color: isActive
              ? LKColors.primary
              : Colors.white.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );

    if (badge == null) return circle;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        circle,
        badge,
      ],
    );
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
          color: LKColors.lkDarkBlue,
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
        child: _buildCircularBlurContainer(
          isActive: isActive,
          badge: badge,
          child: IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: onPressed == null
                ? null
                : () {
                    unawaited(HapticFeedback.lightImpact());
                    onPressed();
                  },
            icon: iconChild,
            tooltip: tooltip,
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              tapTargetSize: MaterialTapTargetSize.padded,
              foregroundColor: LKColors.textPrimary,
              backgroundColor: Colors.transparent,
              hoverColor: LKColors.primary.withValues(alpha: 0.2),
              disabledForegroundColor: LKColors.textHint,
              padding: UIUtils.paddingSM,
              shape: const CircleBorder(),
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
          color: LKColors.success.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 3,
            ),
          ],
        ),
        child: Text(
          '$battery%',
          style: const TextStyle(
            fontSize: 8.5,
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _buildSensorBadge() {
    return Positioned(
      bottom: 2,
      right: 2,
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

  Widget _buildRecBadge({String label = 'REC', Color color = LKColors.danger}) {
    return Positioned(
      bottom: -2,
      right: -2,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.55)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 8,
            color: color,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingButton(
    BuildContext context,
    RecordingController controller,
  ) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final isActive = controller.isRecording;
        final isPending = controller.isPending;
        final canControl = controller.canControl;
        if (!canControl && !isActive && !isPending && !controller.loading) {
          return const SizedBox.shrink();
        }

        if (controller.loading || (isPending && !controller.pendingTimedOut)) {
          final label = controller.loading
              ? controller.operationLabel
              : controller.pendingLabel;
          return _buildControlButton(
            icon: Icons.fiber_manual_record_rounded,
            iconWidget: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isPending ? LKColors.warning : LKColors.textSecondary,
                ),
              ),
            ),
            onPressed: controller.error != null
                ? () => RecordingControls.showErrorDialog(context, controller)
                : null,
            tooltip: label,
            badge: _buildRecBadge(label: '…', color: LKColors.warning),
          );
        }

        if (controller.pendingTimedOut ||
            (canControl && controller.state == null)) {
          return _buildControlButton(
            icon: Icons.refresh_rounded,
            iconColor: LKColors.warning,
            onPressed: () => unawaited(controller.load()),
            tooltip: controller.pendingTimedOut
                ? "Vérifier l'état de l'enregistrement auprès du serveur"
                : 'État d\'enregistrement indisponible · Réessayer',
            badge: _buildRecBadge(label: '!', color: LKColors.warning),
          );
        }

        if (isActive) {
          return _buildControlButton(
            icon: canControl
                ? Icons.stop_circle_rounded
                : Icons.fiber_manual_record_rounded,
            iconColor: LKColors.danger,
            isActive: true,
            badge: _buildRecBadge(),
            tooltip: canControl
                ? 'Arrêter l\'enregistrement'
                : 'Enregistrement en cours',
            onPressed: canControl
                ? () =>
                      RecordingControls.stopWithFeedback(context, controller)
                : null,
          );
        }

        if (!canControl) return const SizedBox.shrink();

        final hasFailed = controller.state?.status == 'failed';
        final hasError = controller.error != null;

        return _buildCircularBlurContainer(
          badge: (hasFailed || hasError)
              ? _buildRecBadge(label: '!', color: LKColors.danger)
              : null,
          child: PopupMenuButton<String>(
            tooltip: 'Démarrer l\'enregistrement',
            offset: const Offset(0, -140),
            color: LKColors.lkDarkBlue,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: UIUtils.borderRadiusAllMD,
            ),
            icon: const Icon(
              Icons.fiber_manual_record_rounded,
              size: 24,
              color: LKColors.danger,
            ),
            onSelected: (value) {
              if (value == '__error__') {
                RecordingControls.showErrorDialog(context, controller);
                return;
              }
              if (value == '__failed__') {
                RecordingControls.showServerFailureDialog(context, controller);
                return;
              }
              unawaited(
                RecordingControls.startWithFeedback(context, controller, value),
              );
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'grid',
                child: ListTile(
                  leading: Icon(Icons.grid_view_rounded, size: 20),
                  title: Text('Grille'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'speaker',
                child: ListTile(
                  leading: Icon(Icons.record_voice_over_rounded, size: 20),
                  title: Text('Intervenant actif'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'single-speaker',
                child: ListTile(
                  leading: Icon(Icons.person_rounded, size: 20),
                  title: Text('Intervenant unique'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (hasFailed)
                const PopupMenuItem(
                  value: '__failed__',
                  child: ListTile(
                    leading: Icon(
                      Icons.error_outline_rounded,
                      size: 20,
                      color: LKColors.danger,
                    ),
                    title: Text('Voir la raison de l\'échec'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (hasError)
                const PopupMenuItem(
                  value: '__error__',
                  child: ListTile(
                    leading: Icon(
                      Icons.info_outline_rounded,
                      size: 20,
                      color: LKColors.warning,
                    ),
                    title: Text('Diagnostic d\'enregistrement'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.transparent,
      padding: UIUtils.paddingVerticalSM.add(UIUtils.paddingHorizontalMD),
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        spacing: 6,
        runSpacing: 6,
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
              _buildCircularBlurContainer(
                child: PopupMenuButton<MediaDevice>(
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
                  color: LKColors.lkDarkBlue,
                  surfaceTintColor: Colors.transparent,
                  elevation: 4,
                  shadowColor: Colors.black.withValues(alpha: 0.3),
                ),
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
            _buildCircularBlurContainer(
              child: PopupMenuButton<MediaDevice>(
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
                color: LKColors.lkDarkBlue,
                surfaceTintColor: Colors.transparent,
                elevation: 4,
                shadowColor: Colors.black.withValues(alpha: 0.3),
              ),
            ),

              // ── Speakerphone ──
              if (!kIsWeb && lkPlatformIsMobile())
                _buildControlButton(
                  icon: _vm.speakerphoneOn
                      ? Icons.volume_up
                      : Icons.headphones_rounded,
                  onPressed: _vm.toggleSpeakerphone,
                  tooltip: _vm.speakerphoneOn
                      ? 'Passer en haut-parleur'
                      : 'Passer en écouteur',
                  iconColor: LKColors.textPrimary,
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
                iconWidget: GlassesIcon(
                  size: 24,
                  color: _vm.bleGlassesConnected
                      ? LKColors.success
                      : LKColors.textSecondary,
                ),
                onPressed: _openBleSheet,
                tooltip: _vm.bleGlassesConnected
                    ? 'Lunettes Engo connectées'
                    : 'Connecter les lunettes Engo',
                badge: (_vm.bleGlassesConnected && _vm.bleBattery != null)
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
                    ? LKColors.primary
                    : LKColors.textSecondary,
                isActive: widget.showPosture,
              ),
              /*if (widget.onSetPostureSmoothingAlpha != null)
                _buildControlButton(
                  icon: Icons.tune_rounded,
                  onPressed: _openPostureSmoothingDialog,
                  tooltip: 'Régler le lissage de la posture',
                ),*/

              // ── Recording (Egress) ──
              if (widget.recordingController != null)
                _buildRecordingButton(context, widget.recordingController!),

              // ── Disconnect ──
              _buildControlButton(
                icon: Icons.call_end_rounded,
                onPressed: _onTapDisconnect,
                tooltip: 'Quitter l\'appel',
                iconColor: LKColors.danger,
              ),
            ],
          ),
        );
  }
}

