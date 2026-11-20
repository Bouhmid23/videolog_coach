import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/athletic_haptics.dart';
import '../../core/beep_service.dart';
import '../../core/mediapipe_pose_detector.dart' show PoseModelVariant;
import '../../core/pip_service.dart';
import '../../core/recording_controller.dart';
import '../../core/remote_shutter_service.dart';
import '../../data/user_role.dart';
import '../../exts.dart';
import '../../theme.dart';
import '../../utils.dart';
import '../../viewmodels/room_viewmodel.dart';
import '../utils/ui_utils.dart';
import '../widgets/controls.dart';
import '../widgets/participant.dart';
import '../widgets/recording_controls.dart';
import '../widgets/room/room_galleries.dart';
import '../widgets/room/room_overlays.dart';
import '../widgets/sweat_lock_overlay.dart';

class RoomPage extends StatefulWidget {
  final Room room;
  final EventsListener<RoomEvent> listener;
  final UserRole role;
  final bool fastConnection;
  final String? roomName;
  final bool canControlRecording;
  final Map<String, String> knownParticipantNames;

  const RoomPage(
    this.room,
    this.listener, {
    this.role = UserRole.trainee,
    this.fastConnection = false,
    this.roomName,
    this.canControlRecording = false,
    this.knownParticipantNames = const {},
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> with WidgetsBindingObserver {
  late final RoomViewModel _vm;
  RecordingController? _recordingController;
  StreamSubscription<void>? _shutterSubscription;
  final ValueNotifier<bool> _showControls = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _isScreenLocked = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isOutdoorSunMode = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _showLandscapeSidebar = ValueNotifier<bool>(true);
  Timer? _controlsHideTimer;
  String? _gestureFeedbackMessage;
  IconData? _gestureFeedbackIcon;
  Timer? _gestureFeedbackTimer;
  bool _allowPop = false;
  bool _isConfirmingExit = false;

  static const Duration _controlsAutoHideDuration = Duration(seconds: 4);

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
      final name = primary != null
          ? _vm.displayNameForParticipant(primary.participant)
          : '';
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
      final name = primary != null
          ? _vm.displayNameForParticipant(primary.participant)
          : '';
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

  /// Basculement de l'affichage du panneau latéral en mode paysage
  void _toggleLandscapeSidebar() {
    _showLandscapeSidebar.value = !_showLandscapeSidebar.value;
    unawaited(HapticFeedback.lightImpact());
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

      if (widget.canControlRecording) {
        unawaited(RemoteShutterService.instance.enable());
        _shutterSubscription =
            RemoteShutterService.instance.onShutterPressed.listen((_) {
          _handleRemoteShutterTrigger();
        });
      }
    }

    PipService.initialize();
    unawaited(PipService.enableAutoEnter());

    WidgetsBindingCompatible.instance?.addPostFrameCallback((_) async {
      await _vm.init(
        widget.room,
        widget.listener,
        role: widget.role,
        knownParticipantNames: widget.knownParticipantNames,
        onDisconnected: (reason) {
          if (!mounted) return;
          _allowPop = true;
          final messenger = ScaffoldMessenger.maybeOf(context);
          if (reason == DisconnectReason.roomDeleted ||
              reason == DisconnectReason.roomClosed) {
            messenger?.showSnackBar(
              const SnackBar(
                content: Text('La session a été fermée par le coach.'),
              ),
            );
          } else if (reason == DisconnectReason.participantRemoved) {
            messenger?.showSnackBar(
              const SnackBar(
                content: Text('Vous avez été retiré de la session.'),
              ),
            );
          }
          context.pop();
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
    _shutterSubscription?.cancel();
    unawaited(RemoteShutterService.instance.disable());
    unawaited(PipService.disableAutoEnter());
    _recordingController?.dispose();
    _vm.dispose();
    _showControls.dispose();
    _isScreenLocked.dispose();
    _isOutdoorSunMode.dispose();
    _showLandscapeSidebar.dispose();
    onWindowShouldClose = null;
    super.dispose();
  }

  void _handleRemoteShutterTrigger() {
    final controller = _recordingController;
    if (controller == null || !mounted || !widget.canControlRecording) return;

    if (controller.loading || controller.isPending) {
      debugPrint(
        '[RemoteShutter] Clic ignoré car opération en cours (loading/pending)',
      );
      return;
    }

    if (controller.isRecording) {
      if (controller.canStop) {
        unawaited(BeepService.doubleBeep());
        _showGestureFeedback('REC Arrêt (K28)', Icons.stop_circle_rounded);
        unawaited(RecordingControls.stopWithFeedback(context, controller));
      } else {
        final reason = controller.stopBlockReason;
        if (reason != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(reason),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } else {
      if (controller.canStart) {
        unawaited(BeepService.beep());
        _showGestureFeedback(
          'REC Démarrage (K28)',
          Icons.fiber_manual_record_rounded,
        );
        unawaited(
          RecordingControls.startWithFeedback(
            context,
            controller,
            controller.layout,
          ),
        );
      } else {
        final reason = controller.startBlockReason;
        if (reason != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(reason),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  Future<void> _handleBackAttempt() async {
    if (_isScreenLocked.value) {
      unawaited(HapticFeedback.heavyImpact());
      _showGestureFeedback(
        'Écran verrouillé — maintenez 1,5 s',
        Icons.lock_rounded,
      );
      return;
    }
    if (_isConfirmingExit) return;
    _isConfirmingExit = true;
    try {
      final shouldLeave = await context.showDisconnectDialog();
      if (shouldLeave == true && mounted) {
        setState(() => _allowPop = true);
        if (widget.room.connectionState == ConnectionState.disconnected) {
          context.pop();
        } else {
          await widget.room.disconnect();
        }
      }
    } finally {
      _isConfirmingExit = false;
    }
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
                final isLandscape = orientation == Orientation.landscape;
                final useTwoColumns = isLandscape && !inPip;

                return PopScope(
                  canPop: _allowPop,
                  onPopInvokedWithResult: (didPop, _) {
                    if (didPop) return;
                    unawaited(_handleBackAttempt());
                  },
                  child: Scaffold(
                    extendBody: true,
                    extendBodyBehindAppBar: true,
                    backgroundColor:
                        outdoorSunMode ? Colors.black : LKColors.background,
                    body: Stack(
                      children: [
                        Positioned.fill(
                          child: useTwoColumns
                              ? _buildLandscapeLayout(context)
                              : _buildPortraitLayout(context, inPip: inPip),
                        ),
                        if (_gestureFeedbackMessage != null && !inPip)
                          RoomGestureFeedbackBanner(
                            message: _gestureFeedbackMessage!,
                            icon: _gestureFeedbackIcon,
                            outdoorSunMode: outdoorSunMode,
                          ),
                        if (isLocked && !inPip)
                          SweatLockOverlay(
                            onUnlock: _toggleSweatLock,
                            outdoorSunMode: outdoorSunMode,
                          ),
                        if (!inPip)
                          Positioned.fill(
                            child: ListenableBuilder(
                              listenable: _vm,
                              builder: (context, _) {
                                final isConnected =
                                    _vm.room?.connectionState ==
                                    ConnectionState.connected;
                                if (isConnected) {
                                  return const IgnorePointer(
                                    child: SizedBox.shrink(),
                                  );
                                }
                                return Container(
                                  color: outdoorSunMode
                                      ? Colors.black.withValues(alpha: 0.9)
                                      : LKColors.background.withValues(
                                          alpha: 0.8,
                                        ),
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
        Positioned.fill(child: _buildPrimaryVideo(context, inPip: inPip)),
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
                  ListenableBuilder(
                    listenable: _vm,
                    builder: (context, _) => RoomSecondaryHorizontalGallery(
                      secondaryTracks: _vm.secondaryTracks,
                      recordingController: _recordingController,
                      outdoorSunMode: _isOutdoorSunMode.value,
                      onSelectTrack: _vm.setPrimaryTrack,
                      displayNameFor: _vm.displayNameForParticipant,
                    ),
                  ),
                  _buildPortraitControls(context),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Vue Paysage adaptative :
  /// - Colonne Gauche : Flux vidéo principal, calque de pose et poignée chevron.
  /// - Colonne Droite (Repliable) : Galerie secondaire + console de contrôles.
  Widget _buildLandscapeLayout(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _showLandscapeSidebar,
      builder: (context, showSidebar, _) {
        return Row(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _buildPrimaryVideo(context, inPip: false),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: RoomSidebarToggleButton(
                        isExpanded: showSidebar,
                        outdoorSunMode: _isOutdoorSunMode.value,
                        onToggle: _toggleLandscapeSidebar,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: UIUtils.animationDuration,
              curve: UIUtils.animationCurve,
              child: showSidebar
                  ? Container(
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
                            const RoomSidebarHeader(),
                            const Divider(height: 1, color: LKColors.border),
                            Expanded(
                              child: ListenableBuilder(
                                listenable: _vm,
                                builder: (context, _) =>
                                    RoomSecondaryVerticalGallery(
                                      secondaryTracks: _vm.secondaryTracks,
                                      recordingController: _recordingController,
                                      outdoorSunMode: _isOutdoorSunMode.value,
                                      onSelectTrack: _vm.setPrimaryTrack,
                                      displayNameFor:
                                          _vm.displayNameForParticipant,
                                    ),
                              ),
                            ),
                            const Divider(height: 1, color: LKColors.border),
                            _buildControlsPanel(context),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
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
                    onDoubleTap:
                        _isScreenLocked.value ? null : _onDoubleTapVideo,
                    onSwipeLeft: _isScreenLocked.value ? null : _onSwipeLeft,
                    onSwipeRight: _isScreenLocked.value ? null : _onSwipeRight,
                    outdoorSunMode: _isOutdoorSunMode.value,
                    displayName: _vm.displayNameForParticipant(
                      primaryTrack.participant,
                    ),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _isScreenLocked.value ? null : _toggleControls,
                    child: const RoomEmptyParticipantState(
                      message: 'Aucun participant principal',
                    ),
                  ),
          );
        },
      ),
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

  /// Panneau de contrôles réutilisable.
  Widget _buildControlsPanel(BuildContext context) {
    final localParticipant = _vm.room?.localParticipant;
    if (localParticipant == null) return const SizedBox.shrink();

    return ValueListenableBuilder<bool>(
      valueListenable: _vm.showPostureListenable,
      builder: (context, showPosture, _) =>
          ValueListenableBuilder<PoseModelVariant>(
        valueListenable: _vm.poseModelVariantListenable,
        builder: (context, poseModelVariant, _) => ControlsWidget(
          _vm.room!,
          localParticipant,
          bleService: _vm.bleService,
          sensorService: _vm.sensorService,
          controlsViewModel: _vm.controlsViewModel,
          onBleConnected: _vm.onBleConnected,
          onBleDisconnected: _vm.onBleDisconnected,
          showPosture: showPosture,
          onTogglePosture: _vm.togglePosture,
          poseModelVariant: poseModelVariant,
          onTogglePoseModel: widget.role.isTrainee
              ? () => unawaited(_vm.togglePoseModelVariant())
              : null,
          recordingController: _recordingController,
          isScreenLocked: _isScreenLocked.value,
          onToggleSweatLock: _toggleSweatLock,
          isOutdoorSunMode: _isOutdoorSunMode.value,
          onToggleOutdoorSunMode: _toggleOutdoorSunMode,
        ),
      ),
    );
  }
}
