import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/pip_service.dart';
import '../../core/recording_controller.dart';
import '../../data/remote_telemetry.dart';
import '../../data/user_role.dart';
import '../../exts.dart';
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
  final ValueNotifier<bool> _showControls = ValueNotifier<bool>(true);
  Timer? _controlsHideTimer;

  static const Duration _controlsAutoHideDuration = Duration(seconds: 4);
  static const double _galleryHeight = 180;
  static const double _galleryHudSpacing = 4;
  static const double _galleryHudHeight = 36;

  void _scheduleControlsAutoHide() {
    _controlsHideTimer?.cancel();
    if (!_showControls.value) return;
    _controlsHideTimer = Timer(_controlsAutoHideDuration, () {
      if (mounted) {
        _showControls.value = false;
      }
    });
  }

  void _toggleControls() {
    _showControls.value = !_showControls.value;
    if (_showControls.value) {
      _scheduleControlsAutoHide();
    } else {
      _controlsHideTimer?.cancel();
    }
  }

  @override
  void initState() {
    super.initState();
    _vm = RoomViewModel();
    _scheduleControlsAutoHide();

    final recordingRoomName = widget.roomName ?? widget.room.name;
    if (recordingRoomName != null && recordingRoomName.isNotEmpty) {
      _recordingController = RecordingController(
        roomName: recordingRoomName,
        canControl: widget.canControlRecording,
      );
      unawaited(_recordingController!.load());
    }

    PipService.initialize();
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
      unawaited(widget.room.setSpeakerOn(true, forceSpeakerOutput: false));
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

  @override
  void dispose() {
    _controlsHideTimer?.cancel();
    unawaited(PipService.disableAutoEnter());
    _recordingController?.dispose();
    _vm.dispose();
    _showControls.dispose();
    onWindowShouldClose = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PipService.isInPip,
      builder: (context, inPip, _) {
        final orientation = MediaQuery.orientationOf(context);
        final size = MediaQuery.sizeOf(context);
        final isLandscape = orientation == Orientation.landscape;
        final isTabletOrDesktop = size.shortestSide >= 600 || size.width >= 720;
        final useTwoColumns = (isLandscape || isTabletOrDesktop) && !inPip;

        return Scaffold(
          extendBody: true,
          extendBodyBehindAppBar: true,
          backgroundColor: LKColors.background,
          body: Stack(
            children: [
              // ========================================================================
              // VUE PRINCIPALE (Adaptative 2 colonnes paysage / iPad OU pile portrait)
              // ========================================================================
              Positioned.fill(
                child: useTwoColumns
                    ? _buildLandscapeLayout(context)
                    : _buildPortraitLayout(context, inPip: inPip),
              ),

              // ========================================================================
              // INDICATEUR DE CHARGEMENT
              // ========================================================================
              if (!inPip)
                Positioned.fill(
                  child: ListenableBuilder(
                    listenable: _vm,
                    builder: (context, _) {
                      final isConnected =
                          _vm.room?.connectionState == ConnectionState.connected;
                      if (isConnected) {
                        return const IgnorePointer(child: SizedBox.shrink());
                      }
                      return Container(
                        color: LKColors.background.withValues(alpha: 0.8),
                        child: const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              LKColors.primary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Vue Portrait : vidéo plein écran + overlay bas (galerie horizontale + contrôles).
  Widget _buildPortraitLayout(BuildContext context, {required bool inPip}) {
    return Stack(
      children: [
        Positioned.fill(
          child: _buildPrimaryVideo(context, inPip: inPip),
        ),
        if (!inPip)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSecondaryHorizontalGallery(context),
                  _buildPortraitControls(context),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Vue Paysage / iPad adaptative deux colonnes :
  /// - 70% Gauche : Flux vidéo principal, calque de pose et télémétrie sportive.
  /// - 30% Droite : Colonne d'analyse verticale (galerie secondaire + console de contrôles).
  Widget _buildLandscapeLayout(BuildContext context) {
    return Row(
      children: [
        // ── 70% Colonne Gauche : Vidéo Principale + Pose ──
        Expanded(
          flex: 7,
          child: Stack(
            children: [
              Positioned.fill(
                child: _buildPrimaryVideo(context, inPip: false),
              ),
              // Barre d'en-tête discrète (bouton retour et nom de session)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: UIUtils.md,
                      vertical: UIUtils.xs,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          onPressed: () async {
                            final result = await context.showDisconnectDialog();
                            if (result == true) await widget.room.disconnect();
                          },
                          style: IconButton.styleFrom(
                            backgroundColor:
                                LKColors.lkDarkBlue.withValues(alpha: 0.85),
                            shape: const CircleBorder(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: LKColors.lkDarkBlue.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Text(
                            widget.roomName ?? widget.room.name ?? 'Session',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── 30% Colonne Droite : Galerie Verticale & Contrôles ──
        Container(
          width: 330,
          decoration: BoxDecoration(
            color: LKColors.surface,
            border: Border(
              left: BorderSide(
                color: LKColors.border.withValues(alpha: 0.7),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            left: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSidebarHeader(context),
                const Divider(height: 1, color: LKColors.border),
                Expanded(
                  child: _buildSecondaryVerticalGallery(context),
                ),
                const Divider(height: 1, color: LKColors.border),
                _buildControlsPanel(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Flux vidéo principal enveloppé dans un RepaintBoundary dédié.
  Widget _buildPrimaryVideo(BuildContext context, {required bool inPip}) {
    return RepaintBoundary(
      child: ListenableBuilder(
        listenable: _vm,
        builder: (context, _) {
          final primaryTrack = _vm.primaryTrack;
          return Container(
            color: LKColors.surface,
            child: primaryTrack != null
                ? ParticipantWidget.widgetFor(
                    primaryTrack,
                    showStatsLayer: !inPip,
                    infoAtTop: !inPip,
                    recordingController: _recordingController,
                    onTap: _toggleControls,
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleControls,
                    child: _buildEmptyState('Aucun participant principal'),
                  ),
          );
        },
      ),
    );
  }

  /// Galerie horizontale pour le mode portrait.
  Widget _buildSecondaryHorizontalGallery(BuildContext context) {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final secondaryTracks = _vm.secondaryTracks;
        if (secondaryTracks.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: EdgeInsets.only(bottom: UIUtils.sm),
          child: RepaintBoundary(
            child: SizedBox(
              height:
                  _galleryHeight + _galleryHudHeight + _galleryHudSpacing,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: UIUtils.md),
                itemCount: secondaryTracks.length,
                separatorBuilder: (_, _) => SizedBox(width: UIUtils.sm),
                itemBuilder: (BuildContext context, int index) {
                  final track = secondaryTracks[index];
                  void selectTrack() => _vm.setPrimaryTrack(track);
                  return SizedBox(
                    key: ValueKey(
                      '${track.participant.identity}_${track.type.name}',
                    ),
                    width: _galleryHeight,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (track.telemetryListenable != null)
                          ValueListenableBuilder(
                            valueListenable: track.telemetryListenable!,
                            builder: (context, telemetry, _) {
                              if (telemetry?.hasData != true) {
                                return const SizedBox.shrink();
                              }
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: selectTrack,
                                    child: DataHud(
                                      telemetry: telemetry,
                                      showValues: false,
                                      compact: true,
                                      showToggle: false,
                                    ),
                                  ),
                                  const SizedBox(height: _galleryHudSpacing),
                                ],
                              );
                            },
                          )
                        else if (track.telemetry?.hasData == true) ...[
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: selectTrack,
                            child: DataHud(
                              telemetry: track.telemetry,
                              showValues: false,
                              compact: true,
                              showToggle: false,
                            ),
                          ),
                          const SizedBox(height: _galleryHudSpacing),
                        ],
                        SizedBox(
                          width: _galleryHeight,
                          height: _galleryHeight,
                          child: ParticipantWidget.widgetFor(
                            track,
                            showDataHud: false,
                            recordingController: _recordingController,
                            onTap: selectTrack,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// Contrôles portrait masquables automatiquement.
  Widget _buildPortraitControls(BuildContext context) {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final localParticipant = _vm.room?.localParticipant;
        if (localParticipant == null) {
          return const SizedBox.shrink();
        }
        return ValueListenableBuilder<bool>(
          valueListenable: _showControls,
          builder: (context, showControls, _) => AnimatedSize(
            duration: UIUtils.animationDuration,
            curve: UIUtils.animationCurve,
            child: showControls
                ? Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) => _scheduleControlsAutoHide(),
                    onPointerUp: (_) => _scheduleControlsAutoHide(),
                    child: _buildControlsPanel(context),
                  )
                : const SizedBox.shrink(),
          ),
        );
      },
    );
  }

  /// En-tête de la barre latérale en mode paysage.
  Widget _buildSidebarHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: UIUtils.md,
        vertical: UIUtils.sm,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.analytics_rounded,
            color: LKColors.primary,
            size: 20,
          ),
          SizedBox(width: UIUtils.sm),
          Expanded(
            child: Text(
              'Participants & Télémétrie',
              style: UIUtils.titleSmall(context).copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          ListenableBuilder(
            listenable: _vm,
            builder: (context, _) {
              final count = _vm.secondaryTracks.length +
                  (_vm.primaryTrack != null ? 1 : 0);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: LKColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: LKColors.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: LKColors.primary,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Galerie verticale des participants secondaires pour l'analyse iPad / Paysage.
  Widget _buildSecondaryVerticalGallery(BuildContext context) {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final secondaryTracks = _vm.secondaryTracks;
        if (secondaryTracks.isEmpty) {
          return Center(
            child: Padding(
              padding: UIUtils.paddingLG,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.people_outline_rounded,
                    size: 36,
                    color: LKColors.textHint,
                  ),
                  SizedBox(height: UIUtils.sm),
                  Text(
                    'Aucun autre participant',
                    style: UIUtils.bodySmall(context).copyWith(
                      color: LKColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: EdgeInsets.all(UIUtils.sm),
          itemCount: secondaryTracks.length,
          separatorBuilder: (_, _) => SizedBox(height: UIUtils.sm),
          itemBuilder: (context, index) {
            final track = secondaryTracks[index];
            void selectTrack() => _vm.setPrimaryTrack(track);

            return InkWell(
              onTap: selectTrack,
              borderRadius: UIUtils.borderRadiusAllMD,
              child: Container(
                decoration: BoxDecoration(
                  color: LKColors.surfaceElevated,
                  borderRadius: UIUtils.borderRadiusAllMD,
                  border: Border.all(
                    color: LKColors.border.withValues(alpha: 0.6),
                    width: 0.8,
                  ),
                ),
                padding: EdgeInsets.all(UIUtils.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: UIUtils.borderRadiusAllSM,
                      child: SizedBox(
                        height: 120,
                        child: RepaintBoundary(
                          child: ParticipantWidget.widgetFor(
                            track,
                            showDataHud: false,
                            recordingController: _recordingController,
                            onTap: selectTrack,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: UIUtils.xs),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayNameForIdentity(track.participant.identity),
                            style: UIUtils.labelMedium(context).copyWith(
                              fontWeight: FontWeight.bold,
                              color: LKColors.textPrimary,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(
                          Icons.touch_app_rounded,
                          size: 13,
                          color: LKColors.textHint,
                        ),
                      ],
                    ),
                    if (track.telemetryListenable != null) ...[
                      SizedBox(height: UIUtils.xs),
                      ValueListenableBuilder<RemoteTelemetry?>(
                        valueListenable: track.telemetryListenable!,
                        builder: (context, telemetry, _) {
                          if (telemetry?.hasData != true) {
                            return const SizedBox.shrink();
                          }
                          return DataHud(
                            telemetry: telemetry,
                            showValues: true,
                            compact: true,
                            showToggle: false,
                          );
                        },
                      ),
                    ] else if (track.telemetry?.hasData == true) ...[
                      SizedBox(height: UIUtils.xs),
                      DataHud(
                        telemetry: track.telemetry,
                        showValues: true,
                        compact: true,
                        showToggle: false,
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Panneau de contrôles réutilisable.
  Widget _buildControlsPanel(BuildContext context) {
    final localParticipant = _vm.room?.localParticipant;
    if (localParticipant == null) return const SizedBox.shrink();

    return ValueListenableBuilder<bool>(
      valueListenable: _vm.showPostureListenable,
      builder: (context, showPosture, _) => ControlsWidget(
        _vm.room!,
        localParticipant,
        bleService: _vm.bleService,
        sensorService: _vm.sensorService,
        controlsViewModel: _vm.controlsViewModel,
        onBleConnected: _vm.onBleConnected,
        onBleDisconnected: _vm.onBleDisconnected,
        showPosture: showPosture,
        onTogglePosture: _vm.togglePosture,
        postureSmoothingAlpha: _vm.poseSmoothingAlpha,
        onSetPostureSmoothingAlpha:
            widget.role.isTrainee ? _vm.setPoseSmoothingAlpha : null,
        recordingController: _recordingController,
      ),
    );
  }

  /// Construit un état vide avec un message
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
