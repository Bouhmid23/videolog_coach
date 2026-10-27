import 'package:flutter/material.dart';

import '../../core/recording_controller.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

/// Contrôle compact d'enregistrement Egress, intégré à la barre d'infos du
/// participant local. Il remplace les indicateurs Wi‑Fi/E2EE de cette tuile.
class RecordingControls extends StatelessWidget {
  const RecordingControls({required this.controller, super.key});

  final RecordingController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isActive = controller.isRecording;
        final isPending = controller.isPending;
        final visible =
            controller.canControl ||
            isActive ||
            isPending ||
            controller.loading;
        if (!visible) return const SizedBox.shrink();

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.error != null) ...[
              _errorButton(context),
              SizedBox(width: UIUtils.xs),
            ],
            if (controller.loading || isPending) ...[
              _ActivityIndicator(
                color: isPending ? LKColors.warning : LKColors.textSecondary,
                tooltip: controller.state?.label ?? 'Enregistrement...',
              ),
              const SizedBox(width: 4),
              _RecordingPill(
                label: controller.state?.label ?? 'Enregistrement…',
                color: LKColors.warning,
              ),
            ] else if (isActive) ...[
              _RecordingPill(
                label: 'REC',
                color: LKColors.danger,
                icon: Icons.fiber_manual_record_rounded,
              ),
              if (controller.canControl)
                IconButton(
                  onPressed: () => _stop(context),
                  icon: const Icon(Icons.stop_circle_rounded, size: 21),
                  color: LKColors.danger,
                  tooltip: 'Arrêter l\'enregistrement',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
            ] else if (controller.canControl)
              PopupMenuButton<String>(
                tooltip: 'Démarrer l\'enregistrement',
                onSelected: (layout) => _start(context, layout),
                color: LKColors.surfaceElevated,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'grid', child: Text('Grille')),
                  PopupMenuItem(
                    value: 'speaker',
                    child: Text('Intervenant actif'),
                  ),
                  PopupMenuItem(
                    value: 'single-speaker',
                    child: Text('Intervenant unique'),
                  ),
                ],
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(
                    Icons.fiber_manual_record_rounded,
                    size: 20,
                    color: LKColors.danger,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _start(BuildContext context, String layout) async {
    debugPrint(
      '[Recording UI] start requested layout=$layout '
      'canStart=${controller.canStart} canControl=${controller.canControl} '
      'loading=${controller.loading} status=${controller.state?.rawStatus}',
    );
    final messenger = ScaffoldMessenger.of(context);
    _showTransient(messenger, 'Démarrage de l\'enregistrement…');

    final started = await controller.startWithLayout(layout);
    if (!context.mounted) return;

    final message = started
        ? (controller.state?.isStarting == true
              ? 'Démarrage en cours…'
              : 'Enregistrement démarré.')
        : (controller.error ??
              controller.startBlockReason ??
              'Impossible de démarrer l\'enregistrement.');
    debugPrint(
      '[Recording UI] start layout=$layout success=$started '
      'status=${controller.state?.rawStatus} error=${controller.error} '
      'block=${controller.startBlockReason}',
    );
    _showResult(context, message, isError: !started);
  }

  Future<void> _stop(BuildContext context) async {
    debugPrint(
      '[Recording UI] stop requested canStop=${controller.canStop} '
      'canControl=${controller.canControl} loading=${controller.loading} '
      'status=${controller.state?.rawStatus}',
    );
    final messenger = ScaffoldMessenger.of(context);
    _showTransient(messenger, 'Arrêt de l\'enregistrement…');

    final stopped = await controller.stop();
    if (!context.mounted) return;

    final message = stopped
        ? (controller.state?.isStopping == true
              ? 'Arrêt en cours…'
              : 'Enregistrement arrêté.')
        : (controller.error ??
              controller.stopBlockReason ??
              'Impossible d\'arrêter l\'enregistrement.');
    debugPrint(
      '[Recording UI] stop success=$stopped '
      'status=${controller.state?.rawStatus} error=${controller.error} '
      'block=${controller.stopBlockReason}',
    );
    _showResult(context, message, isError: !stopped);
  }

  void _showTransient(ScaffoldMessengerState messenger, String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _showResult(
    BuildContext context,
    String message, {
    required bool isError,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          duration: Duration(seconds: isError ? 6 : 3),
          action: isError && controller.error != null
              ? SnackBarAction(
                  label: 'Détails',
                  onPressed: () {
                    if (context.mounted) _showError(context);
                  },
                )
              : null,
        ),
      );
  }

  Widget _errorButton(BuildContext context) {
    return Tooltip(
      message: controller.error!,
      preferBelow: false,
      child: IconButton(
        onPressed: () => _showError(context),
        icon: const Icon(Icons.error_outline_rounded, size: 17),
        color: LKColors.danger,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      ),
    );
  }

  void _showError(BuildContext context) {
    final error = controller.error;
    if (error == null) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enregistrement'),
        content: Text(error),
        actions: [
          if (controller.canControl)
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await controller.load();
              },
              child: const Text('Réessayer'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}

class _RecordingPill extends StatelessWidget {
  const _RecordingPill({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 76),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: UIUtils.borderRadiusAllSM,
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityIndicator extends StatelessWidget {
  const _ActivityIndicator({required this.color, required this.tooltip});

  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: SizedBox(
        width: 20,
        height: 20,
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
      ),
    );
  }
}
