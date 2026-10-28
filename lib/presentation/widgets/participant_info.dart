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
    this.poseListenable,
    this.markers,
    this.showPosture = false,
  });
  Participant participant;
  final ParticipantTrackType type;
  RemoteTelemetry? telemetry;
  ValueListenable<PoseFrame?>? poseListenable;

  /// Ballons du coach. Renseigné uniquement sur la vidéo locale du sportif.
  ValueListenable<List<BallMarker>>? markers;
  bool showPosture;
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
    super.key,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withValues(alpha: 0.8),
          Colors.black.withValues(alpha: 0.6),
        ],
      ),
      borderRadius: isTop
          ? BorderRadius.only(
              bottomLeft: Radius.circular(UIUtils.borderRadiusLG),
              bottomRight: Radius.circular(UIUtils.borderRadiusLG),
            )
          : BorderRadius.only(
              topLeft: Radius.circular(UIUtils.borderRadiusLG),
              topRight: Radius.circular(UIUtils.borderRadiusLG),
            ),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.1),
        width: 0.5,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          blurRadius: 8,
          offset: const Offset(0, -2),
          spreadRadius: 0,
        ),
      ],
    ),
    padding: EdgeInsets.symmetric(vertical: UIUtils.sm, horizontal: UIUtils.md),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Nom du participant
        if (titleContent != null)
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(right: UIUtils.sm),
              child: titleContent,
            ),
          )
        else if (title != null)
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(right: UIUtils.sm),
              child: Text(
                title!,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
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
                padding: EdgeInsets.only(left: UIUtils.sm),
                child: trailing,
              ),


          ],
        ),
      ],
    ),
  );

  /// Construit une icône d'état avec son tooltip
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
        padding: EdgeInsets.only(left: UIUtils.sm),
        child: Icon(icon, color: color ?? Colors.white, size: 16),
      ),
    );
  }

  /// Retourne l'icône de connexion appropriée
  IconData _getConnectionIcon(ConnectionQuality quality) {
    switch (quality) {
      case ConnectionQuality.excellent:
        return Icons.wifi;
      case ConnectionQuality.good:
        return Icons.wifi_1_bar;
      case ConnectionQuality.poor:
        return Icons.wifi_off_outlined;
      case ConnectionQuality.lost:
        return Icons.signal_wifi_off;
      case ConnectionQuality.unknown:
        return Icons.help_outline;
    }
  }

  /// Retourne la couleur de connexion appropriée
  Color? _getConnectionColor(ConnectionQuality quality) {
    switch (quality) {
      case ConnectionQuality.excellent:
        return Colors.green;
      case ConnectionQuality.good:
        return Colors.amber;
      case ConnectionQuality.poor:
        return Colors.red;
      case ConnectionQuality.lost:
        return Colors.redAccent;
      case ConnectionQuality.unknown:
        return Colors.grey;
    }
  }

  /// Retourne le tooltip de connexion approprié
  String _getConnectionTooltip(ConnectionQuality quality) {
    switch (quality) {
      case ConnectionQuality.excellent:
        return 'Connexion excellente';
      case ConnectionQuality.good:
        return 'Connexion bonne';
      case ConnectionQuality.poor:
        return 'Connexion faible';
      case ConnectionQuality.lost:
        return 'Connexion perdue';
      case ConnectionQuality.unknown:
        return 'Connexion inconnue';
    }
  }
}
