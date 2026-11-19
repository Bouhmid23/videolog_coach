import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../data/ball_marker.dart';
import '../../data/remote_telemetry.dart';
import '../../theme.dart';
import '../../viewmodels/pose_detection_viewmodel.dart';
import '../utils/ui_utils.dart';

enum ParticipantTrackType { kUserMedia, kScreenShare }

extension ParticipantTrackTypeExt on ParticipantTrackType {
  TrackSource get lkVideoSourceType => {
    ParticipantTrackType.kUserMedia: TrackSource.camera,
    ParticipantTrackType.kScreenShare: TrackSource.screenShareVideo,
  }[this]!;

  TrackSource get lkAudioSourceType => {
    ParticipantTrackType.kUserMedia: TrackSource.microphone,
    ParticipantTrackType.kScreenShare: TrackSource.screenShareAudio,
  }[this]!;
}

class ParticipantTrack {
  ParticipantTrack({
    required this.participant,
    this.type = ParticipantTrackType.kUserMedia,
    this.telemetry,
    this.telemetryListenable,
    this.poseListenable,
    this.markers,
    this.showPosture = false,
    this.showPostureListenable,
  });
  Participant participant;
  final ParticipantTrackType type;
  RemoteTelemetry? telemetry;
  ValueListenable<RemoteTelemetry?>? telemetryListenable;
  ValueListenable<PoseFrame?>? poseListenable;

  /// Ballons du coach. Renseigné uniquement sur la vidéo locale du sportif.
  ValueListenable<List<BallMarker>>? markers;
  bool showPosture;
  ValueListenable<bool>? showPostureListenable;
}

/// Widget affichant les informations d'un participant (nom, audio, qualité, etc.)
///
/// Design moderne avec :
/// - Fond semi-transparent
/// - Icônes Material Design
/// - Animations subtiles
/// - Feedback visuel de l'état
class ParticipantInfoWidget extends StatelessWidget {
  final String? title;
  final Widget? titleContent;
  final bool audioAvailable;
  final ConnectionQuality connectionQuality;
  final bool isScreenShare;
  final bool enabledE2EE;
  final bool isLocal;
  final bool isTop;
  final Widget? trailing;
  final bool showConnectionStatus;
  final bool outdoorSunMode;

  const ParticipantInfoWidget({
    this.title,
    this.titleContent,
    this.audioAvailable = true,
    this.connectionQuality = ConnectionQuality.excellent,
    this.isScreenShare = false,
    this.enabledE2EE = false,
    this.isLocal = false,
    this.isTop = false,
    this.trailing,
    this.showConnectionStatus = true,
    this.outdoorSunMode = false,
    super.key,
  });

  Widget _buildNameBadge(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: outdoorSunMode
            ? Colors.black
            : LKColors.background.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: outdoorSunMode
              ? Colors.white
              : LKColors.border.withValues(alpha: 0.65),
          width: outdoorSunMode ? 1.2 : 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isScreenShare) ...[
            Icon(
              Icons.monitor_rounded,
              size: 13,
              color: outdoorSunMode ? Colors.white : LKColors.primary,
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: UIUtils.labelMedium(context).copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trimmedTitle = title?.trim() ?? '';
    final hasTitle = trimmedTitle.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: isTop
            ? BorderRadius.only(
                bottomLeft: Radius.circular(UIUtils.borderRadiusLG),
                bottomRight: Radius.circular(UIUtils.borderRadiusLG),
              )
            : BorderRadius.only(
                topLeft: Radius.circular(UIUtils.borderRadiusLG),
                topRight: Radius.circular(UIUtils.borderRadiusLG),
              ),
      ),
      padding: EdgeInsets.symmetric(
        vertical: UIUtils.sm,
        horizontal: UIUtils.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Nom du participant + télémétrie
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: UIUtils.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasTitle) _buildNameBadge(context, trimmedTitle),
                  if (hasTitle && titleContent != null)
                    const SizedBox(height: 4),
                  ?titleContent,
                ],
              ),
            ),
          ),

          // Icônes d'état
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icône audio
              _buildStatusIcon(
                context,
                audioAvailable ? Icons.mic : Icons.mic_off,
                audioAvailable ? null : Colors.red,
                !isScreenShare,
                audioAvailable ? 'Audio activé' : 'Audio désactivé',
              ),
              if (trailing != null)
                Padding(
                  padding: EdgeInsets.only(left: UIUtils.xs),
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: LKColors.background.withValues(alpha: 0.35),
                        width: 0.8,
                      ),
                    ),
                    child: trailing,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Construit une icône d'état avec son tooltip dans un conteneur circulaire
  Widget _buildStatusIcon(
    BuildContext context,
    IconData icon,
    Color? color,
    bool show,
    String tooltip,
  ) {
    if (!show) return const SizedBox.shrink();

    return Tooltip(
      message: tooltip,
      decoration: BoxDecoration(
        color: LKColors.surfaceElevated,
        borderRadius: UIUtils.borderRadiusAllSM,
        border: Border.all(color: LKColors.border, width: 0.5),
      ),
      textStyle: const TextStyle(color: LKColors.textPrimary, fontSize: 10),
      preferBelow: false,
      margin: EdgeInsets.all(UIUtils.xs),
      child: Padding(
        padding: EdgeInsets.only(left: UIUtils.xs),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: LKColors.background.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(
              color: LKColors.border.withValues(alpha: 0.5),
              width: 0.8,
            ),
          ),
          child: Icon(icon, color: color ?? Colors.white, size: 16),
        ),
      ),
    );
  }
}
