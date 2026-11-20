import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../theme.dart';
import '../../utils/ui_utils.dart';

/// Carte d'aperçu caméra (avec grille des tiers) et jauge de niveau microphone
/// affichée sur l'écran de pré-connexion ([ConnectPage]).
class ConnectMediaPreviewCard extends StatelessWidget {
  const ConnectMediaPreviewCard({
    super.key,
    required this.previewVideoTrack,
    required this.previewInitializing,
    required this.cameraEnabled,
    required this.micEnabled,
    required this.busy,
    required this.micLevelListenable,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onSwitchCamera,
  });

  final LocalVideoTrack? previewVideoTrack;
  final bool previewInitializing;
  final bool cameraEnabled;
  final bool micEnabled;
  final bool busy;
  final ValueListenable<double> micLevelListenable;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onSwitchCamera;

  @override
  Widget build(BuildContext context) {
    final previewTrack = previewVideoTrack;

    return Container(
      padding: UIUtils.paddingLG,
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllLG,
        border: Border.all(color: LKColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.center_focus_strong_rounded,
                size: 18,
                color: LKColors.primary,
              ),
              SizedBox(width: UIUtils.sm),
              Expanded(
                child: Text(
                  'Aperçu cadrage & audio',
                  style: UIUtils.labelLarge(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          SizedBox(height: UIUtils.md),
          ClipRRect(
            borderRadius: UIUtils.borderRadiusAllMD,
            child: SizedBox(
              height: 210,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: LKColors.background),
                  if (cameraEnabled && previewTrack != null)
                    RepaintBoundary(
                      child: VideoTrackRenderer(
                        previewTrack,
                        fit: VideoViewFit.cover,
                        renderMode: VideoRenderMode.auto,
                      ),
                    )
                  else if (previewInitializing)
                    const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          LKColors.primary,
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Icon(
                        cameraEnabled
                            ? Icons.videocam_rounded
                            : Icons.videocam_off_rounded,
                        size: 40,
                        color: LKColors.textHint,
                      ),
                    ),
                  if (cameraEnabled && previewTrack != null)
                    const IgnorePointer(child: FramingGridOverlay()),
                  Positioned(
                    left: UIUtils.sm,
                    right: UIUtils.sm,
                    bottom: UIUtils.sm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.62),
                        borderRadius: UIUtils.borderRadiusAllFull,
                      ),
                      child: Text(
                        'Vérifiez votre recul pour la détection de posture',
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: UIUtils.bodySmall(context).copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: UIUtils.sm,
                    top: UIUtils.sm,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildPreviewIconButton(
                          icon: micEnabled
                              ? Icons.mic_rounded
                              : Icons.mic_off_rounded,
                          color: micEnabled ? Colors.white : LKColors.danger,
                          tooltip: micEnabled
                              ? 'Couper le micro'
                              : 'Activer le micro',
                          onTap: busy ? null : onToggleMic,
                        ),
                        const SizedBox(height: 3),
                        _buildPreviewIconButton(
                          icon: cameraEnabled
                              ? Icons.videocam_rounded
                              : Icons.videocam_off_rounded,
                          color: cameraEnabled ? Colors.white : LKColors.danger,
                          tooltip: cameraEnabled
                              ? 'Couper la caméra'
                              : 'Activer la caméra',
                          onTap: busy ? null : onToggleCamera,
                        ),
                        const SizedBox(height: 3),
                        _buildPreviewIconButton(
                          icon: Icons.cameraswitch_rounded,
                          color: Colors.white,
                          tooltip: 'Basculer avant / arrière',
                          onTap: busy ? null : onSwitchCamera,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: UIUtils.md),
          ValueListenableBuilder<double>(
            valueListenable: micLevelListenable,
            builder: (context, level, _) => _buildMicMeterRow(context, level),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.68),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(icon, size: 18, color: color),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMicMeterRow(BuildContext context, double level) {
    const int segments = 14;
    final int activeSegments = micEnabled ? (level * segments).round() : 0;
    final pct = (level * 100).round();

    return Semantics(
      label: micEnabled
          ? 'Niveau du microphone : $pct pour cent'
          : 'Microphone coupé',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Icon(
              micEnabled ? Icons.graphic_eq_rounded : Icons.mic_off_rounded,
              size: 18,
              color: micEnabled ? LKColors.secondary : LKColors.danger,
            ),
            SizedBox(width: UIUtils.sm),
            Text(
              micEnabled ? 'Micro' : 'Micro coupé',
              style: UIUtils.bodySmall(context).copyWith(
                fontWeight: FontWeight.w600,
                color: micEnabled ? LKColors.textPrimary : LKColors.danger,
              ),
            ),
            SizedBox(width: UIUtils.md),
            Expanded(
              child: SizedBox(
                height: 12,
                child: Row(
                  children: List.generate(segments, (index) {
                    final isLit = index < activeSegments;
                    final Color barColor = index >= segments - 2
                        ? LKColors.danger
                        : index >= segments - 5
                        ? LKColors.warning
                        : LKColors.success;
                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          color: isLit
                              ? barColor
                              : LKColors.border.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            SizedBox(width: UIUtils.sm),
            SizedBox(
              width: 38,
              child: Text(
                micEnabled ? '$pct%' : 'OFF',
                textAlign: TextAlign.right,
                style: UIUtils.bodySmall(context).copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: micEnabled ? LKColors.textSecondary : LKColors.danger,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grille de cadrage discrète (règle des tiers) pour aider le sportif à se positionner.
class FramingGridOverlay extends StatelessWidget {
  const FramingGridOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _FramingGridPainter());
  }
}

class _FramingGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = 0.8;

    final thirdW = size.width / 3;
    final thirdH = size.height / 3;

    canvas.drawLine(Offset(thirdW, 0), Offset(thirdW, size.height), paint);
    canvas.drawLine(
      Offset(thirdW * 2, 0),
      Offset(thirdW * 2, size.height),
      paint,
    );
    canvas.drawLine(Offset(0, thirdH), Offset(size.width, thirdH), paint);
    canvas.drawLine(
      Offset(0, thirdH * 2),
      Offset(size.width, thirdH * 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
