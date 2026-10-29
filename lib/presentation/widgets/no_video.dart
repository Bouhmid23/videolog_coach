import 'package:flutter/material.dart';

import '../../theme.dart';

/// Widget affichant un état "pas de vidéo" moderne avec avatar du participant,
/// badge d'information et fond sombre adapté aux sessions de coaching.
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact =
            constraints.maxHeight < 140 || constraints.maxWidth < 140;

        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: LKColors.lkDarkBlue,
          ),
          child: Center(
            child:
            _buildAvatar(isCompact),
          ),
        );
      },
    );
  }

  Widget _buildAvatar(bool isCompact) {
    final size = isCompact ? 38.0 : 76.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            LKColors.border.withValues(alpha: 0.35),
            LKColors.lkDarkBlue.withValues(alpha: 0.8),
          ],
        ),
        border: Border.all(
          color: LKColors.textHint.withValues(alpha: 0.5),
          width: isCompact ? 1.2 : 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: isCompact ? 4 : 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          _getIcon(state),
          color: _getIconColor(state),
          size: isCompact ? 18 : 36,
        ),
      ),
    );
  }

  IconData _getIcon(NoVideoState state) {
    switch (state) {
      case NoVideoState.noVideo:
      case NoVideoState.videoMuted:
      case NoVideoState.videoDisabled:
        return Icons.videocam_off_rounded;
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
        return LKColors.textHint;
      case NoVideoState.loading:
        return LKColors.secondary;
      case NoVideoState.error:
        return LKColors.danger;
      case NoVideoState.screenShare:
        return LKColors.primary;
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
