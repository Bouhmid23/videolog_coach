import 'package:flutter/material.dart';

import '../../theme.dart';
import '../utils/ui_utils.dart';

/// Widget affichant un état "pas de vidéo" avec un design moderne et ergonomique.
///
/// Peut afficher différents états :
/// - No video (caméra éteinte)
/// - Video muted (vidéo désactivée)
/// - Video disabled (vidéo non disponible)
/// - Loading (chargement en cours)
class NoVideoWidget extends StatelessWidget {
  final NoVideoState state;
  final String? participantName;
  final bool showIcon;
  final bool showLabel;

  const NoVideoWidget({
    super.key,
    this.state = NoVideoState.noVideo,
    this.participantName,
    this.showIcon = true,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            LKColors.surfaceElevated,
            LKColors.surface,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showIcon) _buildIcon(state),
            if (showIcon && showLabel) SizedBox(height: UIUtils.sm),
            if (showLabel) _buildLabel(context, state),
            if (participantName != null && showLabel)
              Padding(
                padding: EdgeInsets.only(top: UIUtils.xs),
                child: Text(
                  participantName!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: LKColors.textHint,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(NoVideoState state) {
    final icon = _getIcon(state);
    final color = _getIconColor(state);
    
    return Icon(
      icon,
      color: color,
      size: 48,
      shadows: [
        Shadow(
          color: color.withValues(alpha: 0.3),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  Widget _buildLabel(BuildContext context, NoVideoState state) {
    final label = _getLabel(state);
    
    return Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: LKColors.textSecondary,
        fontWeight: FontWeight.w500,
      ),
      textAlign: TextAlign.center,
    );
  }

  IconData _getIcon(NoVideoState state) {
    switch (state) {
      case NoVideoState.noVideo:
        return Icons.videocam_off_rounded;
      case NoVideoState.videoMuted:
        return Icons.volume_off_rounded;
      case NoVideoState.videoDisabled:
        return Icons.no_photography_rounded;
      case NoVideoState.loading:
        return Icons.hourglass_empty_rounded;
      case NoVideoState.error:
        return Icons.error_outline_rounded;
      case NoVideoState.screenShare:
        return Icons.monitor_rounded;
    }
  }

  Color _getIconColor(NoVideoState state) {
    switch (state) {
      case NoVideoState.noVideo:
      case NoVideoState.videoMuted:
      case NoVideoState.videoDisabled:
        return LKColors.textSecondary;
      case NoVideoState.loading:
        return LKColors.secondary;
      case NoVideoState.error:
        return LKColors.danger;
      case NoVideoState.screenShare:
        return LKColors.primary;
    }
  }

  String _getLabel(NoVideoState state) {
    switch (state) {
      case NoVideoState.noVideo:
        return 'Pas de vidéo';
      case NoVideoState.videoMuted:
        return 'Vidéo désactivée';
      case NoVideoState.videoDisabled:
        return 'Vidéo non disponible';
      case NoVideoState.loading:
        return 'Chargement...';
      case NoVideoState.error:
        return 'Erreur vidéo';
      case NoVideoState.screenShare:
        return 'Partage d\'écran';
    }
  }
}

/// États possibles pour le widget NoVideo
enum NoVideoState {
  noVideo,        // Caméra éteinte ou non disponible
  videoMuted,     // Vidéo désactivée (muted)
  videoDisabled,  // Vidéo explicitement désactivée
  loading,        // Chargement en cours
  error,          // Erreur de vidéo
  screenShare,    // Partage d'écran
}
