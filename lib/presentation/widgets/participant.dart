import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:videolog_coach/presentation/widgets/participant_info.dart';

import 'data_hud.dart';
export 'data_hud.dart';

import '../../core/recording_controller.dart';
import '../../data/ball_marker.dart';
import '../../data/frame_geometry.dart';
import '../../data/remote_posture.dart';
import '../../data/remote_telemetry.dart';
import '../../utils.dart';
import '../../viewmodels/pose_detection_viewmodel.dart';
import '../utils/ui_utils.dart';
import 'marker_overlay.dart';
import 'no_video.dart';
import 'pose_overlay.dart';
import 'recording_controls.dart';

/// Classe représentant une piste de participant avec ses données associées
abstract class ParticipantWidget extends StatefulWidget {
  static ParticipantWidget widgetFor(
    ParticipantTrack participantTrack, {
    bool showStatsLayer = false,
    bool poseAside = false,
    bool showDataHud = true,
    bool infoAtTop = false,
    RecordingController? recordingController,
    VoidCallback? onTap,
    VoidCallback? onDoubleTap,
    VoidCallback? onSwipeLeft,
    VoidCallback? onSwipeRight,
    bool outdoorSunMode = false,
  }) {
    final key = ValueKey(
      '${participantTrack.participant.identity}_${participantTrack.type.name}',
    );
    if (participantTrack.participant is LocalParticipant) {
      return LocalParticipantWidget(
        participantTrack.participant as LocalParticipant,
        participantTrack.type,
        showStatsLayer,
        key: key,
        telemetry: participantTrack.telemetry,
        telemetryListenable: participantTrack.telemetryListenable,
        poseListenable: participantTrack.poseListenable,
        markers: participantTrack.markers,
        showPosture: participantTrack.showPosture,
        showPostureListenable: participantTrack.showPostureListenable,
        poseAside: poseAside,
        showDataHud: showDataHud,
        infoAtTop: infoAtTop,
        recordingController: recordingController,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onSwipeLeft: onSwipeLeft,
        onSwipeRight: onSwipeRight,
        outdoorSunMode: outdoorSunMode,
      );
    } else if (participantTrack.participant is RemoteParticipant) {
      return RemoteParticipantWidget(
        participantTrack.participant as RemoteParticipant,
        participantTrack.type,
        showStatsLayer,
        key: key,
        telemetry: participantTrack.telemetry,
        telemetryListenable: participantTrack.telemetryListenable,
        poseListenable: participantTrack.poseListenable,
        markers: participantTrack.markers,
        showPosture: participantTrack.showPosture,
        showPostureListenable: participantTrack.showPostureListenable,
        poseAside: poseAside,
        showDataHud: showDataHud,
        infoAtTop: infoAtTop,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onSwipeLeft: onSwipeLeft,
        onSwipeRight: onSwipeRight,
        outdoorSunMode: outdoorSunMode,
      );
    }
    throw UnimplementedError('Unknown participant type');
  }

  abstract final Participant participant;
  abstract final ParticipantTrackType type;
  abstract final bool showStatsLayer;
  final RemotePosture? posture;
  final RemoteTelemetry? telemetry;
  final ValueListenable<RemoteTelemetry?>? telemetryListenable;
  final ValueListenable<PoseFrame?>? poseListenable;

  /// Ballons du coach (topic LiveKit `marker`).
  final ValueListenable<List<BallMarker>>? markers;
  final Pose? pose;
  final Size? poseFrameSize;
  final bool avatarOnly;
  final bool showPosePip;
  final bool showPosture;
  final ValueListenable<bool>? showPostureListenable;
  final bool poseAside;
  final bool showDataHud;
  final bool infoAtTop;
  final VoidCallback? onTogglePosture;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;
  final bool outdoorSunMode;
  final VideoQuality quality;
  final RecordingController? recordingController;

  const ParticipantWidget({
    this.posture,
    this.telemetry,
    this.telemetryListenable,
    this.markers,
    this.poseListenable,
    this.pose,
    this.poseFrameSize,
    this.avatarOnly = false,
    this.showPosePip = true,
    this.showPosture = true,
    this.showPostureListenable,
    this.poseAside = false,
    this.showDataHud = true,
    this.infoAtTop = false,
    this.onTogglePosture,
    this.onTap,
    this.onDoubleTap,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.outdoorSunMode = false,
    this.quality = VideoQuality.HIGH,
    this.recordingController,
    super.key,
  });
}

/// Widget pour le participant local
class LocalParticipantWidget extends ParticipantWidget {
  @override
  final LocalParticipant participant;
  @override
  final ParticipantTrackType type;
  @override
  final bool showStatsLayer;

  const LocalParticipantWidget(
    this.participant,
    this.type,
    this.showStatsLayer, {
    super.posture,
    super.telemetry,
    super.telemetryListenable,
    super.poseListenable,
    super.markers,
    super.pose,
    super.poseFrameSize,
    super.avatarOnly,
    super.showPosePip,
    super.showPosture,
    super.showPostureListenable,
    super.poseAside,
    super.showDataHud,
    super.infoAtTop,
    super.recordingController,
    super.onTap,
    super.onDoubleTap,
    super.onSwipeLeft,
    super.onSwipeRight,
    super.outdoorSunMode,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _LocalParticipantWidgetState();
}

/// Widget pour un participant distant
class RemoteParticipantWidget extends ParticipantWidget {
  @override
  final RemoteParticipant participant;
  @override
  final ParticipantTrackType type;
  @override
  final bool showStatsLayer;

  const RemoteParticipantWidget(
    this.participant,
    this.type,
    this.showStatsLayer, {
    super.posture,
    super.telemetry,
    super.telemetryListenable,
    super.poseListenable,
    super.markers,
    super.pose,
    super.poseFrameSize,
    super.avatarOnly,
    super.showPosePip,
    super.showPosture,
    super.showPostureListenable,
    super.onTogglePosture,
    super.poseAside,
    super.showDataHud,
    super.infoAtTop,
    super.onTap,
    super.onDoubleTap,
    super.onSwipeLeft,
    super.onSwipeRight,
    super.outdoorSunMode,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _RemoteParticipantWidgetState();
}

/// État partagé pour tous les widgets de participant
abstract class _ParticipantWidgetState<T extends ParticipantWidget>
    extends State<T>
    with SingleTickerProviderStateMixin {
  bool _visible = true;
  VideoTrack? get activeVideoTrack;
  AudioTrack? get activeAudioTrack;
  TrackPublication? get videoPublication;
  TrackPublication? get audioPublication;
  bool get isScreenShare => widget.type == ParticipantTrackType.kScreenShare;

  String? _activeVideoTrackSid;
  bool? _videoMuted;
  bool? _audioAvailable;
  ConnectionQuality? _connectionQuality;
  String? _participantName;
  final ValueNotifier<Size?> _poseFrameSizeNotifier = ValueNotifier<Size?>(null);

  /// Le renderer LiveKit miroite la caméra frontale locale. Le squelette doit
  /// suivre exactement le même miroir pour rester aligné sur l'image affichée.
  bool get _mirrorVideo {
    final track = activeVideoTrack;
    if (track is! LocalVideoTrack) return false;
    final options = track.currentOptions;
    if (options is CameraCaptureOptions) {
      return options.cameraPosition == CameraPosition.front;
    }
    final facingMode = track.mediaStreamTrack.getSettings()['facingMode'];
    return facingMode == 'user' || facingMode == 'front';
  }

  /// Résolution de l'image caméra, nécessaire pour reprojeter les positions
  /// normalisées (ballons du coach) exactement comme le squelette.
  ///
  /// Priorité à la taille des images de pose : c'est celle du squelette, déjà alignée sur
  /// l'image affichée (portrait). Les dimensions publiées par LiveKit sont toujours annoncées
  /// en paysage (640×480) : elles ne servent qu'en repli, remises dans le sens de l'écran.
  Size? get _videoFrameSize {
    final poseSize = _poseFrameSizeNotifier.value ??
        widget.poseListenable?.value?.frameSize;
    if (poseSize != null && !poseSize.isEmpty) return poseSize;

    final published = _publishedFrameSize();
    if (published == null) return null;
    return orientFrameToScreen(
      published,
      portraitScreen: MediaQuery.orientationOf(context) == Orientation.portrait,
    );
  }

  Size? _publishedFrameSize() {
    final dimensions = videoPublication?.dimensions;
    if (dimensions != null &&
        dimensions.width > 0 &&
        dimensions.height > 0) {
      return Size(dimensions.width.toDouble(), dimensions.height.toDouble());
    }

    final track = activeVideoTrack;
    if (track is LocalVideoTrack) {
      final requested = track.currentOptions.params.dimensions;
      if (requested.width > 0 && requested.height > 0) {
        return Size(requested.width.toDouble(), requested.height.toDouble());
      }
    }

    if (track == null) return null;
    try {
      final settings = track.mediaStreamTrack.getSettings();
      final width = settings['width'];
      final height = settings['height'];
      if (width is num && height is num && width > 0 && height > 0) {
        return Size(width.toDouble(), height.toDouble());
      }
    } catch (_) {
      // Piste déjà libérée : on retombera sur le prochain rebuild.
    }
    return null;
  }

  // Animation pour l'apparition
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    widget.participant.addListener(_onParticipantChanged);
    widget.poseListenable?.addListener(_onPoseFrameChanged);
    _poseFrameSizeNotifier.value = widget.poseListenable?.value?.frameSize;

    // Initialiser les animations
    _animationController = AnimationController(
      vsync: this,
      duration: UIUtils.animationDuration,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: UIUtils.animationCurveBounce,
    );

    _opacityAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    // Démarrer l'animation
    _animationController.forward();

    _syncSnapshot();
  }

  @override
  void dispose() {
    widget.participant.removeListener(_onParticipantChanged);
    widget.poseListenable?.removeListener(_onPoseFrameChanged);
    _poseFrameSizeNotifier.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    if (oldWidget.participant != widget.participant) {
      oldWidget.participant.removeListener(_onParticipantChanged);
      widget.participant.addListener(_onParticipantChanged);
    }
    if (oldWidget.poseListenable != widget.poseListenable) {
      oldWidget.poseListenable?.removeListener(_onPoseFrameChanged);
      widget.poseListenable?.addListener(_onPoseFrameChanged);
      _onPoseFrameChanged();
    }
    _syncSnapshot();
    super.didUpdateWidget(oldWidget);
  }

  void _onPoseFrameChanged() {
    final size = widget.poseListenable?.value?.frameSize;
    if (size != _poseFrameSizeNotifier.value) {
      _poseFrameSizeNotifier.value = size;
    }
  }

  bool _syncSnapshot() {
    final nextVideoSid = videoPublication?.sid;
    final nextVideoMuted = activeVideoTrack?.muted ?? videoPublication?.muted;
    final nextAudioAvailable =
        audioPublication?.muted == false &&
        audioPublication?.subscribed == true;
    final nextQuality = widget.participant.connectionQuality;
    final nextName = widget.participant.name;

    final changed =
        nextVideoSid != _activeVideoTrackSid ||
        nextVideoMuted != _videoMuted ||
        nextAudioAvailable != _audioAvailable ||
        nextQuality != _connectionQuality ||
        nextName != _participantName;

    _activeVideoTrackSid = nextVideoSid;
    _videoMuted = nextVideoMuted;
    _audioAvailable = nextAudioAvailable;
    _connectionQuality = nextQuality;
    _participantName = nextName;
    return changed;
  }

  void _onParticipantChanged() {
    if (_syncSnapshot() && mounted) {
      setState(() {});
    }
  }

  List<Widget> extraWidgets(bool isScreenShare) => [];

  @override
  Widget build(BuildContext ctx) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: FadeTransition(
        opacity: _opacityAnimation,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(UIUtils.borderRadiusLG),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [Expanded(child: _buildBody())],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return _buildVideoStack();
  }

  Widget _buildVideoStack() {
    return Stack(
      children: [
        // 1. FLUX VIDEO PRINCIPAL
        Positioned.fill(
          child: RepaintBoundary(
            child: activeVideoTrack != null && !activeVideoTrack!.muted
                ? VideoTrackRenderer(
                    renderMode: VideoRenderMode.auto,
                    activeVideoTrack!,
                    fit: VideoViewFit.cover,
                  )
                : NoVideoWidget(
                    state: isScreenShare
                        ? NoVideoState.screenShare
                        : (activeVideoTrack?.muted == true ||
                                videoPublication?.muted == true
                            ? NoVideoState.videoMuted
                            : NoVideoState.videoDisabled),
                    participantName: widget.participant.name.isNotEmpty
                        ? displayNameForIdentity(widget.participant.name)
                        : displayNameForIdentity(widget.participant.identity),
                  ),
          ),
        ),

        // 2. Squelette de posture (pose locale) — reconstruit uniquement l'overlay
        if (widget.poseListenable != null)
          Positioned.fill(
            child: RepaintBoundary(
              child: widget.showPostureListenable != null
                  ? ValueListenableBuilder<bool>(
                      valueListenable: widget.showPostureListenable!,
                      builder: (context, showPosture, _) {
                        if (!showPosture) return const SizedBox.shrink();
                        return ValueListenableBuilder<PoseFrame?>(
                          valueListenable: widget.poseListenable!,
                          builder: (context, frame, _) =>
                              PoseOverlay(frame: frame, mirrorX: _mirrorVideo),
                        );
                      },
                    )
                  : widget.showPosture
                  ? ValueListenableBuilder<PoseFrame?>(
                      valueListenable: widget.poseListenable!,
                      builder: (context, frame, _) =>
                          PoseOverlay(frame: frame, mirrorX: _mirrorVideo),
                    )
                  : const SizedBox.shrink(),
            ),
          ),

        // 3. Ballons du coach : uniquement sur la vidéo locale du sportif.
        // N'écoute que les changements de taille de frame (pas chaque pose à 30 fps).
        if (widget.participant is LocalParticipant &&
            !isScreenShare &&
            widget.markers != null)
          Positioned.fill(
            child: RepaintBoundary(
              child: ValueListenableBuilder<Size?>(
                valueListenable: _poseFrameSizeNotifier,
                builder: (context, _, _) => MarkerOverlay(
                  markers: widget.markers!,
                  frameSize: _videoFrameSize,
                  mirrorX: _mirrorVideo,
                ),
              ),
            ),
          ),

        // 4. Couche de détection des gestes directs AU-DESSUS de VideoTrackRenderer
        // (balayage horizontal pour switcher de participant, double-tap pour le micro, tap pour HUD)
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap ?? () => setState(() => _visible = !_visible),
            onDoubleTap: widget.onDoubleTap,
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -250) {
                widget.onSwipeLeft?.call();
              } else if (velocity > 250) {
                widget.onSwipeRight?.call();
              }
            },
          ),
        ),

        // 5. Barre d'identité et valeurs du participant principal
        Align(
          alignment: widget.infoAtTop
              ? Alignment.topCenter
              : Alignment.bottomCenter,
          child: widget.onTap != null && !widget.infoAtTop
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTap,
                  child: _buildParticipantInfo(isScreenShare),
                )
              : _buildParticipantInfo(isScreenShare),
        ),

        // 6. Widgets supplémentaires (pour les participants distants)
        ...extraWidgets(isScreenShare),
      ],
    );
  }

  Widget _buildParticipantInfo(bool isScreenShare) {
    final controller = widget.recordingController;
    final isLocal = widget.participant is LocalParticipant;

    Widget buildInfo({Widget? trailing, bool showConnectionStatus = true}) {
      final usePrimaryDataHud = widget.showDataHud && !isScreenShare;
      return ParticipantInfoWidget(
        title: widget.participant.name.isNotEmpty
            ? displayNameForIdentity(widget.participant.name)
            : displayNameForIdentity(widget.participant.identity),
        titleContent: usePrimaryDataHud
            ? DataHud(
                telemetry: widget.telemetry,
                telemetryListenable: widget.telemetryListenable,
                showValues: true,
                transparent: true,
                compact: true,
                showToggle: false,
                outdoorSunMode: widget.outdoorSunMode,
              )
            : null,
        audioAvailable:
            audioPublication?.muted == false &&
            audioPublication?.subscribed == true,
        connectionQuality: widget.participant.connectionQuality,
        isScreenShare: isScreenShare,
        enabledE2EE: widget.participant.isEncrypted,
        isLocal: isLocal,
        isTop: widget.infoAtTop,
        trailing: trailing,
        showConnectionStatus: showConnectionStatus,
      );
    }

    final Widget info;
    if (isLocal && controller != null) {
      info = AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final showRecordingBadge =
              controller.isRecording ||
              controller.isPending ||
              controller.loading;
          return buildInfo(
            trailing: showRecordingBadge
                ? RecordingControls(controller: controller, showActions: false)
                : null,
            showConnectionStatus: true,
          );
        },
      );
    } else {
      info = buildInfo();
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [info],
    );

    if (!widget.infoAtTop) return content;
    return SafeArea(bottom: false, child: content);
  }
}

class _LocalParticipantWidgetState
    extends _ParticipantWidgetState<LocalParticipantWidget> {
  @override
  LocalTrackPublication<LocalVideoTrack>? get videoPublication => widget
      .participant
      .videoTrackPublications
      .where((e) => e.source == widget.type.lkVideoSourceType)
      .firstOrNull;

  @override
  LocalTrackPublication<LocalAudioTrack>? get audioPublication => widget
      .participant
      .audioTrackPublications
      .where((e) => e.source == widget.type.lkAudioSourceType)
      .firstOrNull;

  @override
  VideoTrack? get activeVideoTrack => videoPublication?.track;

  @override
  AudioTrack? get activeAudioTrack => audioPublication?.track;
}

/// État pour un participant distant
class _RemoteParticipantWidgetState
    extends _ParticipantWidgetState<RemoteParticipantWidget> {
  @override
  RemoteTrackPublication<RemoteVideoTrack>? get videoPublication => widget
      .participant
      .videoTrackPublications
      .where((e) => e.source == widget.type.lkVideoSourceType)
      .firstOrNull;

  @override
  RemoteTrackPublication<RemoteAudioTrack>? get audioPublication => widget
      .participant
      .audioTrackPublications
      .where((e) => e.source == widget.type.lkAudioSourceType)
      .firstOrNull;

  @override
  VideoTrack? get activeVideoTrack => videoPublication?.track;

  @override
  AudioTrack? get activeAudioTrack => audioPublication?.track;
}
