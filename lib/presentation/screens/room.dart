import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/pip_service.dart';
import '../../core/recording_controller.dart';
import '../../data/user_role.dart';
import '../../theme.dart';
import '../../utils.dart';
import '../utils/ui_utils.dart';
import '../widgets/controls.dart';
import '../widgets/participant.dart';
import '../../viewmodels/room_viewmodel.dart';

class RoomPage extends StatefulWidget {
  final Room room;
  final EventsListener<RoomEvent> listener;
  final UserRole role;
  final bool fastConnection;
  final String? roomName;
  final bool canControlRecording;

  const RoomPage(
    this.room,
    this.listener, {
    this.role = UserRole.trainee,
    this.fastConnection = false,
    this.roomName,
    this.canControlRecording = false,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  late final RoomViewModel _vm;
  RecordingController? _recordingController;

  static const double _galleryHeight = 180;
  static const double _galleryHudSpacing = 4;
  static const double _galleryHudHeight = 36;

  @override
  void initState() {
    super.initState();
    _vm = RoomViewModel();
    _vm.addListener(_onStateChanged);

    final recordingRoomName = widget.roomName ?? widget.room.name;
    if (recordingRoomName != null && recordingRoomName.isNotEmpty) {
      _recordingController = RecordingController(
        roomName: recordingRoomName,
        canControl: widget.canControlRecording,
      );
      unawaited(_recordingController!.load());
    }

    PipService.initialize();
    PipService.isInPip.addListener(_onStateChanged);
    unawaited(PipService.enableAutoEnter());

    WidgetsBindingCompatible.instance?.addPostFrameCallback((_) async {
      await _vm.init(
        widget.room,
        widget.listener,
        role: widget.role,
        onDisconnected: () {
          if (mounted) {
            context.pop();
          }
        },
      );
      if (mounted) setState(() {});
    });

    if (lkPlatformIs(PlatformType.android)) {
      unawaited(Hardware.instance.setSpeakerphoneOn(true));
    }

    if (lkPlatformIsDesktop()) {
      onWindowShouldClose = () async {
        await _vm.forceQuit();
      };
    }
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PipService.isInPip.removeListener(_onStateChanged);
    unawaited(PipService.disableAutoEnter());
    _recordingController?.dispose();
    _vm.removeListener(_onStateChanged);
    _vm.dispose();
    onWindowShouldClose = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryTrack = _vm.primaryTrack;
    final secondaryTracks = _vm.secondaryTracks;
    final inPip = PipService.isInPip.value;

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      backgroundColor: LKColors.background,
      body: Stack(
        children: [
          // ========================================================================
          // FLUX VIDEO PRINCIPAL EN ARRIERE-PLAN (plein Ã©cran)
          // ========================================================================
          Positioned.fill(
            child: Container(
              color: LKColors.surface,
              child: primaryTrack != null
                  ? ParticipantWidget.widgetFor(
                      primaryTrack,
                      showStatsLayer: !inPip,
                      infoAtTop: !inPip,
                      recordingController: _recordingController,
                    )
                  : _buildEmptyState('Aucun participant principal'),
            ),
          ),

          // ========================================================================
          // OVERLAY BAS : autres users -> contr��les
          // ========================================================================
          if (!inPip)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ===========================================================
                  // GALERIE DES PARTICIPANTS SECONDAIRES (scrollable horizontalement)
                  // ===========================================================
                  if (secondaryTracks.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(bottom: UIUtils.sm),
                      child: SizedBox(
                        height: _galleryHeight + _galleryHudHeight + _galleryHudSpacing,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(horizontal: UIUtils.md),
                          itemCount: secondaryTracks.length,
                          separatorBuilder: (_, _) =>
                              SizedBox(width: UIUtils.sm),
                          itemBuilder: (BuildContext context, int index) {
                            final track = secondaryTracks[index];
                            final hasHud = track.telemetry?.hasData == true;
                            return SizedBox(
                              width: _galleryHeight,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // HUD de télémétrie au-dessus de la tuile
                                  if (hasHud) ...[
                                    DataHud(
                                      telemetry: track.telemetry,
                                      showValues: false,
                                      compact: true,
                                      showToggle: false,
                                      //posture: track.posture,
                                      //showPosture: track.showPosture,
                                    ),
                                    const SizedBox(height: _galleryHudSpacing),
                                  ],
                                  // Tuile vidéo du participant (HUD interne désactivé)
                                  SizedBox(
                                    width: _galleryHeight,
                                    height: _galleryHeight,
                                    child: ParticipantWidget.widgetFor(
                                      track,
                                      showDataHud: false,
                                      recordingController: _recordingController,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                  // ===========================================================
                  // CONTROLES = LIMITE BASSE DU WIDGET
                  // ===========================================================
                  if (_vm.room?.localParticipant != null)
                    SafeArea(
                      top: false,
                      child: ControlsWidget(
                        _vm.room!,
                        _vm.room!.localParticipant!,
                        bleService: _vm.bleService,
                        sensorService: _vm.sensorService,
                        controlsViewModel: _vm.controlsViewModel,
                        onBleConnected: _vm.onBleConnected,
                        onBleDisconnected: _vm.onBleDisconnected,
                        showPosture: _vm.showPosture,
                        onTogglePosture: _vm.togglePosture,
                        postureSmoothingAlpha: _vm.poseSmoothingAlpha,
                        onSetPostureSmoothingAlpha: widget.role.isTrainee
                            ? _vm.setPoseSmoothingAlpha
                            : null,
                        onDebugMarkers: widget.role.isTrainee
                            ? _vm.injectDebugMarkers
                            : null,
                        onQuit: _vm.forceQuit,
                      ),
                    ),
                ],
              ),
            ),

          // ========================================================================
          // BANDEAU DE RECONNEXION (non bloquant, avec sortie forcée)
          // ========================================================================
          if (!inPip &&
              _vm.room?.connectionState == ConnectionState.reconnecting)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _ReconnectingBanner(
                onQuit: () => unawaited(_vm.forceQuit()),
              ),
            ),

          // ========================================================================
          // INDICATEUR DE CHARGEMENT (connexion initiale uniquement : pendant
          // une reconnexion, les contrôles doivent rester accessibles)
          // ========================================================================
          if (!inPip &&
              _vm.room?.connectionState != ConnectionState.connected &&
              _vm.room?.connectionState != ConnectionState.reconnecting)
            Positioned.fill(
              child: Container(
                color: LKColors.background.withValues(alpha: 0.8),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(LKColors.primary),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Construit un Ã©tat vide avec un message
  Widget _buildEmptyState(String message) {
    return Container(
      color: LKColors.surface,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_off_rounded,
              size: 64,
              color: LKColors.textSecondary,
            ),
            SizedBox(height: UIUtils.md),
            Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: LKColors.textSecondary),
            ),
            SizedBox(height: UIUtils.sm),
            Text(
              'En attente des participants...',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: LKColors.textHint),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bandeau affiché pendant une reconnexion SDK.
///
/// Non bloquant : il laisse les contrôles du bas accessibles et propose une
/// sortie forcée (`disconnect()` + `dispose()`) si la reconnexion s'éternise.
class _ReconnectingBanner extends StatelessWidget {
  const _ReconnectingBanner({required this.onQuit});

  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.all(UIUtils.sm),
        child: Material(
          color: LKColors.surfaceElevated.withValues(alpha: 0.95),
          borderRadius: UIUtils.borderRadiusAllMD,
          elevation: 6,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: UIUtils.md,
              vertical: UIUtils.xs,
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      LKColors.secondary,
                    ),
                  ),
                ),
                SizedBox(width: UIUtils.sm),
                Expanded(
                  child: Text(
                    'Reconnexion en cours…',
                    style: UIUtils.labelMedium(context),
                  ),
                ),
                TextButton.icon(
                  onPressed: onQuit,
                  icon: const Icon(
                    Icons.call_end_rounded,
                    size: 18,
                    color: LKColors.danger,
                  ),
                  label: Text(
                    'Quitter',
                    style: UIUtils.labelMedium(
                      context,
                    ).copyWith(color: LKColors.danger),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
