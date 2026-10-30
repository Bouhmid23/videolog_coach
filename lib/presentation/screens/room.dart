import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';
import '../../core/athletic_haptics.dart';
import '../../core/pip_service.dart';
import '../../core/recording_controller.dart';
import '../../data/remote_telemetry.dart';
import '../../data/user_role.dart';
import '../../theme.dart';
import '../../utils.dart';
import '../utils/ui_utils.dart';
import '../widgets/controls.dart';
import '../widgets/participant.dart';
import '../widgets/sweat_lock_overlay.dart';
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

class _RoomPageState extends State<RoomPage> with WidgetsBindingObserver {
  late final RoomViewModel _vm;
  RecordingController? _recordingController;
  final ValueNotifier<bool> _showControls = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _isScreenLocked = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isOutdoorSunMode = ValueNotifier<bool>(false);
  Timer? _controlsHideTimer;
  String? _gestureFeedbackMessage;
  IconData? _gestureFeedbackIcon;
  Timer? _gestureFeedbackTimer;

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
    if (_isScreenLocked.value) return;
    _showControls.value = !_showControls.value;
    if (_showControls.value) {
      _scheduleControlsAutoHide();
    } else {
      _controlsHideTimer?.cancel();
    }
  }

  void _showGestureFeedback(String message, IconData icon) {
    _gestureFeedbackTimer?.cancel();
    setState(() {
      _gestureFeedbackMessage = message;
      _gestureFeedbackIcon = icon;
    });
    _gestureFeedbackTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() {
          _gestureFeedbackMessage = null;
          _gestureFeedbackIcon = null;
        });
      }
    });
  }

  /// Balayage horizontal gauche : switcher vers le participant suivant
  void _onSwipeLeft() {
    if (_isScreenLocked.value) return;
    final switched = _vm.switchToNextParticipant();
    if (switched) {
      unawaited(AthleticHaptics.participantSwitched());
      final primary = _vm.primaryTrack;
      final name = primary?.participant.name.isNotEmpty == true
          ? displayNameForIdentity(primary!.participant.name)
          : displayNameForIdentity(primary?.participant.identity ?? '');
      _showGestureFeedback('Participant : $name', Icons.swap_horiz_rounded);
    }
  }

  /// Balayage horizontal droite : switcher vers le participant précédent
  void _onSwipeRight() {
    if (_isScreenLocked.value) return;
    final switched = _vm.switchToPreviousParticipant();
    if (switched) {
      unawaited(AthleticHaptics.participantSwitched());
      final primary = _vm.primaryTrack;
      final name = primary?.participant.name.isNotEmpty == true
          ? displayNameForIdentity(primary!.participant.name)
          : displayNameForIdentity(primary?.participant.identity ?? '');
      _showGestureFeedback('Participant : $name', Icons.swap_horiz_rounded);
    }
  }

  /// Double-tap direct sur la vidéo : activer / couper le micro
  void _onDoubleTapVideo() {
    if (_isScreenLocked.value) return;
    _vm.controlsViewModel.toggleMicrophone();
    final isMuted = _vm.room?.localParticipant?.isMuted ?? false;
    unawaited(AthleticHaptics.micToggled(muted: isMuted));
    _showGestureFeedback(
      isMuted ? 'Micro désactivé' : 'Micro activé',
      isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
    );
  }

  /// Basculement du verrouillage anti-sueur (Pocket & Sweat Lock)
  void _toggleSweatLock() {
    final next = !_isScreenLocked.value;
    _isScreenLocked.value = next;
    unawaited(AthleticHaptics.sweatLockToggled(locked: next));
    if (next) {
      _controlsHideTimer?.cancel();
      _showControls.value = false;
    }
    setState(() {});
  }

  /// Basculement du mode plein soleil à contraste maximal
  void _toggleOutdoorSunMode() {
    final next = !_isOutdoorSunMode.value;
    _isOutdoorSunMode.value = next;
    unawaited(AthleticHaptics.outdoorModeToggled(active: next));
    _showGestureFeedback(
      next ? 'Mode Plein Soleil (Contraste maximal)' : 'Mode Standard',
      next ? Icons.wb_sunny_rounded : Icons.nightlight_round,
    );
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      unawaited(AudioManager.instance.setSpeakerOutputPreferred(true));
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _vm.onAppLifecycleStateChanged(state);
    super.didChangeAppLifecycleState(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controlsHideTimer?.cancel();
    _gestureFeedbackTimer?.cancel();
    unawaited(PipService.disableAutoEnter());
    _recordingController?.dispose();
    _vm.dispose();
    _showControls.dispose();
    _isScreenLocked.dispose();
    _isOutdoorSunMode.dispose();
    onWindowShouldClose = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _isOutdoorSunMode,
      builder: (context, outdoorSunMode, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: _isScreenLocked,
          builder: (context, isLocked, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: PipService.isInPip,
              builder: (context, inPip, _) {
                final orientation = MediaQuery.orientationOf(context);
                final size = MediaQuery.sizeOf(context);
                final isLandscape = orientation == Orientation.landscape;
                final isTabletOrDesktop = size.shortestSide >= 700 || size.width >= 820;
                final useTwoColumns = (isLandscape || isTabletOrDesktop) && !inPip;

                return Scaffold(
                  extendBody: true,
                  extendBodyBehindAppBar: true,
                  backgroundColor: outdoorSunMode ? Colors.black : LKColors.background,
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
                      // BANNIÈRE FLOTTANTE DE RETOUR GESTUEL DIRECT
                      // ========================================================================
                      if (_gestureFeedbackMessage != null && !inPip)
                        Positioned(
                          top: 74,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: outdoorSunMode ? Colors.black : Colors.black.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: outdoorSunMode ? Colors.white : LKColors.primary,
                                  width: outdoorSunMode ? 1.5 : 1,
                                ),
                                boxShadow: UIUtils.shadowMD,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_gestureFeedbackIcon != null) ...[
                                    Icon(
                                      _gestureFeedbackIcon,
                                      color: outdoorSunMode ? const Color(0xFFFFB800) : LKColors.primary,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(
                                    _gestureFeedbackMessage!,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: outdoorSunMode ? FontWeight.w900 : FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // ========================================================================
                      // OVERLAY DE VERROUILLAGE SWEAT / POCKET LOCK
                      // ========================================================================
                      if (isLocked && !inPip)
                        SweatLockOverlay(
                          onUnlock: _toggleSweatLock,
                          outdoorSunMode: outdoorSunMode,
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
                                color: outdoorSunMode
                                    ? Colors.black.withValues(alpha: 0.9)
                                    : LKColors.background.withValues(alpha: 0.8),
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
          },
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
            color: _isOutdoorSunMode.value ? Colors.black : LKColors.surface,
            child: primaryTrack != null
                ? ParticipantWidget.widgetFor(
                    primaryTrack,
                    showStatsLayer: !inPip,
                    infoAtTop: !inPip,
                    recordingController: _recordingController,
                    onTap: _isScreenLocked.value ? null : _toggleControls,
                    onDoubleTap: _isScreenLocked.value ? null : _onDoubleTapVideo,
                    onSwipeLeft: _isScreenLocked.value ? null : _onSwipeLeft,
                    onSwipeRight: _isScreenLocked.value ? null : _onSwipeRight,
                    outdoorSunMode: _isOutdoorSunMode.value,
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _isScreenLocked.value ? null : _toggleControls,
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
                                      outdoorSunMode: _isOutdoorSunMode.value,
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
                              outdoorSunMode: _isOutdoorSunMode.value,
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
                            outdoorSunMode: _isOutdoorSunMode.value,
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
                        outdoorSunMode: _isOutdoorSunMode.value,
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
        //onSetPostureSmoothingAlpha: widget.role.isTrainee ? _vm.setPoseSmoothingAlpha : null,
        recordingController: _recordingController,
        isScreenLocked: _isScreenLocked.value,
        onToggleSweatLock: _toggleSweatLock,
        isOutdoorSunMode: _isOutdoorSunMode.value,
        onToggleOutdoorSunMode: _toggleOutdoorSunMode,
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
