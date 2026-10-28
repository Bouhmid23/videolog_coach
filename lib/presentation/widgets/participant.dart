import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:videolog_coach/presentation/widgets/participant_info.dart';
import 'dart:async';

import '../../core/recording_controller.dart';
import '../../data/ball_marker.dart';
import '../../data/frame_geometry.dart';
import '../../data/remote_posture.dart';
import '../../data/remote_telemetry.dart';
import '../../theme.dart';
import '../../utils.dart';
import '../../viewmodels/pose_detection_viewmodel.dart';
import '../utils/ui_utils.dart';
import 'marker_overlay.dart';
import 'no_video.dart';
import 'pose_overlay.dart';
import 'recording_controls.dart';

/// Classe reprÃ©sentant une piste de participant avec ses donnÃ©es associÃ©es
abstract class ParticipantWidget extends StatefulWidget {
  static ParticipantWidget widgetFor(
    ParticipantTrack participantTrack, {
    bool showStatsLayer = false,
    bool poseAside = false,
    bool showDataHud = true,
    bool infoAtTop = false,
    RecordingController? recordingController,
  }) {
    if (participantTrack.participant is LocalParticipant) {
      return LocalParticipantWidget(
        participantTrack.participant as LocalParticipant,
        participantTrack.type,
        showStatsLayer,
        //posture: participantTrack.posture,
        telemetry: participantTrack.telemetry,
        //pose: participantTrack.pose,
        //poseFrameSize: participantTrack.poseFrameSize,
        //avatarOnly: participantTrack.avatarOnly,
        //showPosePip: participantTrack.showPosePip,
        poseListenable: participantTrack.poseListenable,
        markers: participantTrack.markers,
        showPosture: participantTrack.showPosture,
        poseAside: poseAside,
        showDataHud: showDataHud,
        infoAtTop: infoAtTop,
        recordingController: recordingController,
      );
    } else if (participantTrack.participant is RemoteParticipant) {
      return RemoteParticipantWidget(
        participantTrack.participant as RemoteParticipant,
        participantTrack.type,
        showStatsLayer,
        //posture: participantTrack.posture,
        telemetry: participantTrack.telemetry,
        //pose: participantTrack.pose,
        //poseFrameSize: participantTrack.poseFrameSize,
        //avatarOnly: participantTrack.avatarOnly,
        //showPosePip: participantTrack.showPosePip,
        poseListenable: participantTrack.poseListenable,
        markers: participantTrack.markers,
        showPosture: participantTrack.showPosture,
        //onTogglePosture: participantTrack.onTogglePosture,
        poseAside: poseAside,
        showDataHud: showDataHud,
        infoAtTop: infoAtTop,
      );
    }
    throw UnimplementedError('Unknown participant type');
  }

  abstract final Participant participant;
  abstract final ParticipantTrackType type;
  abstract final bool showStatsLayer;
  final RemotePosture? posture;
  final RemoteTelemetry? telemetry;
  final ValueListenable<PoseFrame?>? poseListenable;

  /// Ballons du coach (topic LiveKit `marker`).
  final ValueListenable<List<BallMarker>>? markers;
  final Pose? pose;
  final Size? poseFrameSize;
  final bool avatarOnly;
  final bool showPosePip;
  final bool showPosture;
  final bool poseAside;
  final bool showDataHud;
  final bool infoAtTop;
  final VoidCallback? onTogglePosture;
  final VideoQuality quality;
  final RecordingController? recordingController;

  const ParticipantWidget({
    this.posture,
    this.telemetry,
    this.markers,
    this.poseListenable,
    this.pose,
    this.poseFrameSize,
    this.avatarOnly = false,
    this.showPosePip = true,
    this.showPosture = true,
    this.poseAside = false,
    this.showDataHud = true,
    this.infoAtTop = false,
    this.onTogglePosture,
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
    super.poseListenable,
    super.markers,
    super.pose,
    super.poseFrameSize,
    super.avatarOnly,
    super.showPosePip,
    super.showPosture,
    super.poseAside,
    super.showDataHud,
    super.infoAtTop,
    super.recordingController,
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
    super.poseListenable,
    super.markers,
    super.pose,
    super.poseFrameSize,
    super.avatarOnly,
    super.showPosePip,
    super.showPosture,
    super.onTogglePosture,
    super.poseAside,
    super.showDataHud,
    super.infoAtTop,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _RemoteParticipantWidgetState();
}

/// Ã‰tat partagÃ© pour tous les widgets de participant
abstract class _ParticipantWidgetState<T extends ParticipantWidget>
    extends State<T>
    with SingleTickerProviderStateMixin {
  bool _visible = true;
  VideoTrack? get activeVideoTrack;
  AudioTrack? get activeAudioTrack;
  TrackPublication? get videoPublication;
  TrackPublication? get audioPublication;
  bool get isScreenShare => widget.type == ParticipantTrackType.kScreenShare;

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
    final poseSize = widget.poseListenable?.value?.frameSize;
    if (poseSize != null && !poseSize.isEmpty) return poseSize;

    final published = _publishedFrameSize();
    if (published == null) return null;
    return orientFrameToScreen(
      published,
      portraitScreen: MediaQuery.of(context).orientation == Orientation.portrait,
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

  EventsListener<ParticipantEvent>? _listener;

  // Animation pour l'apparition
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _listener = widget.participant.createListener();
    widget.participant.addListener(_onParticipantChanged);

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

    // DÃ©marrer l'animation
    _animationController.forward();

    _onParticipantChanged();
  }

  @override
  void dispose() {
    widget.participant.removeListener(_onParticipantChanged);
    _animationController.dispose();
    unawaited(_listener?.dispose());
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    oldWidget.participant.removeListener(_onParticipantChanged);
    widget.participant.addListener(_onParticipantChanged);
    _onParticipantChanged();
    super.didUpdateWidget(oldWidget);
  }

  void _onParticipantChanged() => setState(() {});

  List<Widget> extraWidgets(bool isScreenShare) => [];

  @override
  Widget build(BuildContext ctx) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: FadeTransition(
        opacity: _opacityAnimation,
        child: Container(
          foregroundDecoration: BoxDecoration(
            border: widget.participant.isSpeaking && !isScreenShare
                ? Border.all(width: 3, color: LKColors.primary)
                : null,
            borderRadius: BorderRadius.circular(UIUtils.borderRadiusLG),
          ),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(UIUtils.borderRadiusLG),
            boxShadow: widget.participant.isSpeaking && !isScreenShare
                ? [
                    BoxShadow(
                      color: LKColors.primary.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 0),
                      spreadRadius: 2,
                    ),
                  ]
                : null,
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
        InkWell(
          onTap: () => setState(() => _visible = !_visible),
          borderRadius: UIUtils.borderRadiusAllLG,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: activeVideoTrack != null && !activeVideoTrack!.muted
              ? VideoTrackRenderer(
                  renderMode: VideoRenderMode.auto,
                  activeVideoTrack!,
                  fit: VideoViewFit.cover,
                )
              : NoVideoWidget(
                  state: isScreenShare
                      ? NoVideoState.screenShare
                      : (activeVideoTrack?.muted == true
                            ? NoVideoState.videoMuted
                            : NoVideoState.noVideo),
                  participantName: widget.participant.name.isNotEmpty
                      ? displayNameForIdentity(widget.participant.name)
                      : null,
                ),
        ),

        // 2. Squelette de posture (pose locale)
        if (widget.showPosture && widget.poseListenable != null)
          Positioned.fill(
            child: ValueListenableBuilder<PoseFrame?>(
              valueListenable: widget.poseListenable!,
              builder: (context, frame, _) =>
                  PoseOverlay(frame: frame, mirrorX: _mirrorVideo),
            ),
          ),

        // 3. Ballons du coach : uniquement sur la vidéo locale du sportif.
        if (widget.participant is LocalParticipant &&
            !isScreenShare &&
            widget.markers != null)
          Positioned.fill(
            // Reconstruit à chaque pose : la taille d'image du squelette arrive après le premier
            // rendu, et le ballon doit s'y aligner dès qu'elle est connue.
            child: widget.poseListenable == null
                ? MarkerOverlay(
                    markers: widget.markers!,
                    frameSize: _videoFrameSize,
                    mirrorX: _mirrorVideo,
                  )
                : ValueListenableBuilder<PoseFrame?>(
                    valueListenable: widget.poseListenable!,
                    builder: (context, _, __) => MarkerOverlay(
                      markers: widget.markers!,
                      frameSize: _videoFrameSize,
                      mirrorX: _mirrorVideo,
                    ),
                  ),
          ),

        // 3. Barre d'identite et valeurs du participant principal
        Align(
          alignment: widget.infoAtTop
              ? Alignment.topCenter
              : Alignment.bottomCenter,
          child: _buildParticipantInfo(isScreenShare),
        ),

        // 5. Widgets supplÃ©mentaires (pour les participants distants)
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
                showValues: true,
                transparent: true,
                compact: true,
                showToggle: false,
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
          final showRecording =
              controller.canControl ||
              controller.isRecording ||
              controller.isPending;
          return buildInfo(
            trailing: showRecording
                ? RecordingControls(controller: controller)
                : null,
            showConnectionStatus: !showRecording,
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

class DataHud extends StatefulWidget {
  final RemoteTelemetry? telemetry;
  final bool showValues;
  final bool transparent;
  final bool compact;
  final bool showToggle;

  const DataHud({
    this.telemetry,
    this.showValues = true,
    this.transparent = false,
    this.compact = false,
    this.showToggle = true,
    super.key,
  });

  @override
  State<DataHud> createState() => _DataHudState();
}

class _DataHudState extends State<DataHud> {
  bool _expanded = true;
  static const double _compactWidth = 320;

  List<(IconData, Color, String, String)> _buildItems() {
    final items = <(IconData, Color, String, String)>[];
    final telemetry = widget.telemetry;
    if (telemetry == null) return items;

    if (telemetry.hasHrm) {
      items.add((
        Icons.favorite_rounded,
        LKColors.danger,
        '${telemetry.heartRate} bpm',
        '',
      ));
    }
    if (telemetry.speed != null) {
      items.add((
        Icons.speed_rounded,
        LKColors.warning,
        '${telemetry.speed!.toStringAsFixed(1)} km/h',
        '',
      ));
    }
    if (telemetry.cadence != null) {
      items.add((
        Icons.pedal_bike_rounded,
        LKColors.success,
        '${telemetry.cadence!.toStringAsFixed(0)} rpm',
        '',
      ));
    }
    if (telemetry.altitude != null) {
      items.add((
        Icons.height_rounded,
        LKColors.secondary,
        '${telemetry.altitude!.toStringAsFixed(0)} m',
        '',
      ));
    }
    if (telemetry.bearing != null) {
      items.add((
      Icons.explore_rounded,
      LKColors.warning,
      '${telemetry.bearing!.toStringAsFixed(0)} deg',
      '',
      ));
    }
    if (telemetry.lat != null || telemetry.lng != null) {
      items.add((
        Icons.location_on_rounded,
        LKColors.primary,
        'Position',
        '',
      ));
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildItems();
    if (items.isEmpty) {
      if (!widget.transparent) return const SizedBox.shrink();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.sensors_off_rounded,
            size: 13,
            color: LKColors.textHint,
          ),
          const SizedBox(width: 5),
          Text(
            'Aucune donnée capteur',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: LKColors.textHint,
              fontSize: 9,
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = widget.compact || constraints.maxWidth < _compactWidth;
        final content = Wrap(
          spacing: compact ? UIUtils.xs : UIUtils.sm,
          runSpacing: compact ? 0 : UIUtils.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final item in items)
              _HudChip(
                icon: item.$1,
                color: item.$2,
                text: widget.showValues ? item.$3 : item.$4,
                compact: compact,
                transparent: widget.transparent,
              ),
            if (widget.showToggle && !compact && !widget.transparent)
              _HudChip(
                icon: _expanded
                    ? Icons.unfold_less_rounded
                    : Icons.unfold_more_rounded,
                color: LKColors.textSecondary,
                text: _expanded ? 'Reduire' : 'Details',
                showText: _expanded,
                onTap: () => setState(() => _expanded = !_expanded),
              ),
          ],
        );

        if (widget.transparent) {
          return Align(alignment: Alignment.centerLeft, child: content);
        }

        return Align(
          alignment: Alignment.topLeft,
          child: ClipRRect(
            borderRadius: UIUtils.borderRadiusAllMD,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: UIUtils.sm,
                  vertical: UIUtils.xs,
                ),
                decoration: BoxDecoration(
                  color: LKColors.surface.withValues(alpha: 0.85),
                  borderRadius: UIUtils.borderRadiusAllMD,
                  border: Border.all(color: LKColors.border, width: 0.5),
                  boxShadow: UIUtils.shadowSM,
                ),
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HudChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final bool showText;
  final bool compact;
  final bool transparent;
  final VoidCallback? onTap;

  const _HudChip({
    required this.icon,
    required this.color,
    required this.text,
    this.showText = true,
    this.compact = false,
    this.transparent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chip = AnimatedContainer(
      duration: UIUtils.animationDuration,
      curve: UIUtils.animationCurve,
      padding: EdgeInsets.symmetric(
        horizontal: transparent
            ? 2
            : compact
            ? UIUtils.xs + 2
            : UIUtils.sm,
        vertical: transparent
            ? 1
            : compact
            ? UIUtils.xs - 1
            : UIUtils.xs + 1,
      ),
      decoration: transparent
          ? null
          : BoxDecoration(
              color: LKColors.surfaceElevated,
              borderRadius: UIUtils.borderRadiusAllSM,
              border: Border.all(
                color: onTap != null
                    ? LKColors.border.withValues(alpha: 0.8)
                    : LKColors.border,
                width: 0.3,
              ),
            ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: compact ? 13 : 12),
          AnimatedSize(
            duration: UIUtils.animationDuration,
            curve: UIUtils.animationCurve,
            child: !showText
                ? const SizedBox(width: 0)
                : Padding(
                    padding: EdgeInsets.only(left: UIUtils.xs - 2),
                    child: Text(
                      text,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: transparent
                            ? 11
                            : compact
                            ? 9
                            : 10,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );

    if (onTap == null) return chip;
    return InkWell(
      onTap: onTap,
      borderRadius: UIUtils.borderRadiusAllSM,
      child: chip,
    );
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

/// Ã‰tat pour un participant distant
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
