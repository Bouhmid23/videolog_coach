import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:videolog_coach/presentation/widgets/participant_info.dart';
import 'dart:async';

import '../../data/remote_posture.dart';
import '../../data/remote_telemetry.dart';
import '../../theme.dart';
import '../../utils.dart';
import '../utils/ui_utils.dart';
import 'no_video.dart';

/// Classe reprÃ©sentant une piste de participant avec ses donnÃ©es associÃ©es
abstract class ParticipantWidget extends StatefulWidget {
  static ParticipantWidget widgetFor(
    ParticipantTrack participantTrack, {
    bool showStatsLayer = false,
    bool poseAside = false,
    bool showDataHud = true,
    bool infoAtTop = false,
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
        //showPosture: participantTrack.showPosture,
        poseAside: poseAside,
        showDataHud: showDataHud,
        infoAtTop: infoAtTop,
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
        //showPosture: participantTrack.showPosture,
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

  const ParticipantWidget({
    this.posture,
    this.telemetry,
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
    super.pose,
    super.poseFrameSize,
    super.avatarOnly,
    super.showPosePip,
    super.showPosture,
    super.poseAside,
    super.showDataHud,
    super.infoAtTop,
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
    extends State<T> with SingleTickerProviderStateMixin {
  bool _visible = true;
  VideoTrack? get activeVideoTrack;
  AudioTrack? get activeAudioTrack;
  TrackPublication? get videoPublication;
  TrackPublication? get audioPublication;
  bool get isScreenShare => widget.type == ParticipantTrackType.kScreenShare;
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
            children: [
              Expanded(child: _buildBody()),
            ],
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

        // 3. HUD de donnees (telemetrie)
        if (widget.showDataHud &&
            !isScreenShare &&
            (widget.telemetry != null || widget.posture != null))
          Positioned(
            top: widget.infoAtTop ? UIUtils.md + 25 : UIUtils.md,
            left: UIUtils.xs,
            right: UIUtils.md,
            child: SafeArea(
              bottom: false,
              left: false,
              right: false,
              child: DataHud(
                telemetry: widget.telemetry,
                //posture: widget.posture,
                //showPosture: widget.showPosture,
              ),
            ),
          ),

        // 4. Info du participant (en haut pour le flux principal, en bas sinon)
        Align(
          alignment:
              widget.infoAtTop ? Alignment.topCenter : Alignment.bottomCenter,
          child: _buildParticipantInfo(isScreenShare),
        ),

        // 5. Widgets supplÃ©mentaires (pour les participants distants)
        ...extraWidgets(isScreenShare),
      ],
    );
  }

  Widget _buildParticipantInfo(bool isScreenShare) {
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ParticipantInfoWidget(
          title: widget.participant.name.isNotEmpty
              ? displayNameForIdentity(widget.participant.name)
              : displayNameForIdentity(widget.participant.identity),
          audioAvailable: audioPublication?.muted == false &&
              audioPublication?.subscribed == true,
          connectionQuality: widget.participant.connectionQuality,
          isScreenShare: isScreenShare,
          enabledE2EE: widget.participant.isEncrypted,
          isLocal: widget.participant is LocalParticipant,
          isTop: widget.infoAtTop,
        ),
      ],
    );

    if (!widget.infoAtTop) return info;
    return SafeArea(bottom: false, child: info);
  }

}

class DataHud extends StatefulWidget {
  final RemoteTelemetry? telemetry;
  //final RemotePosture? posture;
  //final bool showPosture;

  const DataHud({
    this.telemetry,
    //this.posture,
    //required this.showPosture,
    super.key,
  });

  @override
  State<DataHud> createState() => _DataHudState();
}

class _DataHudState extends State<DataHud> {
  bool _expanded = true;

  /// Largeur sous laquelle le HUD bascule en mode compact (padding et police
  /// réduits) sur les tuiles de galerie.
  static const double _compactWidth = 320;

  List<(IconData, Color, String)> _buildItems() {
    final items = <(IconData, Color, String)>[];

    // Télémétrie
    final telemetry = widget.telemetry;
    if (telemetry != null) {
      if (telemetry.hasHrm) {
        items.add((Icons.favorite_rounded, LKColors.danger, '${telemetry.heartRate} bpm'));
      }
      if (telemetry.speed != null) {
        items.add((Icons.speed_rounded, LKColors.warning, '${telemetry.speed!.toStringAsFixed(1)} km/h'));
      }
      if (telemetry.cadence != null) {
        items.add((Icons.pedal_bike_rounded, LKColors.success, '${telemetry.cadence!.toStringAsFixed(0)} rpm'));
      }
      if (telemetry.altitude != null) {
        items.add((Icons.height_rounded, LKColors.secondary, '${telemetry.altitude!.toStringAsFixed(0)} m'));
      }
      if (telemetry.bearing != null) {
        items.add((Icons.explore_rounded, LKColors.warning, '${telemetry.bearing!.toStringAsFixed(0)}°'));
      }
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildItems();
    if (items.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Sur une tuile étroite, on conserve la taille compacte mais les
        // valeurs restent visibles (les chips passent sur plusieurs lignes).
        final compact = constraints.maxWidth < _compactWidth;
        final showText = _expanded;

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
                child: Wrap(
                  spacing: UIUtils.sm,
                  runSpacing: UIUtils.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Chips de données
                    for (final item in items)
                      _HudChip(
                        icon: item.$1,
                        color: item.$2,
                        text: item.$3,
                        showText: showText,
                        compact: compact,
                      ),
                    // Toggle extension / compression (uniquement en mode large)
                    if (!compact)
                      _HudChip(
                        icon: _expanded
                            ? Icons.unfold_less_rounded
                            : Icons.unfold_more_rounded,
                        color: LKColors.textSecondary,
                        text: _expanded ? 'Réduire' : 'Détails',
                        showText: _expanded,
                        onTap: () => setState(() => _expanded = !_expanded),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Puce pour afficher une information ( chip )
class _HudChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final bool showText;
  final bool compact;
  final VoidCallback? onTap;

  const _HudChip({
    required this.icon,
    required this.color,
    required this.text,
    this.showText = true,
    this.compact = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chip = AnimatedContainer(
      duration: UIUtils.animationDuration,
      curve: UIUtils.animationCurve,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? UIUtils.xs + 2 : UIUtils.sm,
        vertical: compact ? UIUtils.xs - 1 : UIUtils.xs + 1,
      ),
      decoration: BoxDecoration(
        color: LKColors.surfaceElevated,
        borderRadius: UIUtils.borderRadiusAllSM,
        border: Border.all(
          color: onTap != null ? LKColors.border.withValues(alpha: 0.8) : LKColors.border,
          width: 0.3,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: color,
            size: compact ? 13 : 12,
          ),
          AnimatedSize(
            duration: UIUtils.animationDuration,
            curve: UIUtils.animationCurve,
            child: !showText
                ? SizedBox(width: 0)
                : Padding(
                    padding: EdgeInsets.only(left: UIUtils.xs - 2),
                    child: Text(
                      text,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
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

/// Ã‰tat pour le participant local
class _LocalParticipantWidgetState extends _ParticipantWidgetState<LocalParticipantWidget> {
  @override
  LocalTrackPublication<LocalVideoTrack>? get videoPublication => 
      widget.participant.videoTrackPublications
          .where((e) => e.source == widget.type.lkVideoSourceType)
          .firstOrNull;
  
  @override
  LocalTrackPublication<LocalAudioTrack>? get audioPublication => 
      widget.participant.audioTrackPublications
          .where((e) => e.source == widget.type.lkAudioSourceType)
          .firstOrNull;
  
  @override
  VideoTrack? get activeVideoTrack => videoPublication?.track;
  
  @override
  AudioTrack? get activeAudioTrack => audioPublication?.track;
}

/// Ã‰tat pour un participant distant
class _RemoteParticipantWidgetState extends _ParticipantWidgetState<RemoteParticipantWidget> {
  @override
  RemoteTrackPublication<RemoteVideoTrack>? get videoPublication => 
      widget.participant.videoTrackPublications
          .where((e) => e.source == widget.type.lkVideoSourceType)
          .firstOrNull;
  
  @override
  RemoteTrackPublication<RemoteAudioTrack>? get audioPublication => 
      widget.participant.audioTrackPublications
          .where((e) => e.source == widget.type.lkAudioSourceType)
          .firstOrNull;
  
  @override
  VideoTrack? get activeVideoTrack => videoPublication?.track;
  
  @override
  AudioTrack? get activeAudioTrack => audioPublication?.track;
}
