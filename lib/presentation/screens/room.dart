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
  static const double _galleryHudHeight =
      84; // Valeurs visibles sur plusieurs lignes

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
        unawaited(widget.room.disconnect());
        await widget.listener.waitFor<RoomDisconnectedEvent>(
          duration: const Duration(seconds: 5),
        );
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
                        height: _galleryHeight + _galleryHudHeight,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(horizontal: UIUtils.md),
                          itemCount: secondaryTracks.length,
                          separatorBuilder: (_, _) =>
                              SizedBox(width: UIUtils.sm),
                          itemBuilder: (BuildContext context, int index) {
                            final track = secondaryTracks[index];
                            final hasHud = track.telemetry != null;
                            return SizedBox(
                              width: _galleryHeight,
                              height: _galleryHeight + _galleryHudHeight,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // HUD de télémétrie au-dessus de la tuile
                                  SizedBox(
                                    height: _galleryHudHeight,
                                    child: hasHud
                                        ? DataHud(
                                            telemetry: track.telemetry,
                                            //posture: track.posture,
                                            //showPosture: track.showPosture,
                                          )
                                        : const SizedBox.shrink(),
                                  ),
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
                      ),
                    ),
                ],
              ),
            ),

          // ========================================================================
          // INDICATEUR DE CHARGEMENT (si necessaire)
          // ========================================================================
          if (!inPip && _vm.room?.connectionState != ConnectionState.connected)
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
