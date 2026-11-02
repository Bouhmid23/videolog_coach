import 'package:flutter/material.dart';

import '../../core/thermal_service.dart';
import '../../theme.dart';

/// Boîte de dialogue d'alerte informant l'utilisateur lorsque le téléphone chauffe.
class ThermalAlertDialog extends StatelessWidget {
  final ThermalInfo? info;

  const ThermalAlertDialog({
    super.key,
    this.info,
  });

  /// Affiche l'AlertDialog d'alerte thermique.
  static Future<void> show(
    BuildContext context, {
    ThermalInfo? info,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ThermalAlertDialog(info: info),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCritical = (info?.status ?? 0) >= 3;
    final accentColor = isCritical ? LKColors.danger : LKColors.warning;

    return AlertDialog(
      backgroundColor: LKColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: accentColor.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      iconPadding: const EdgeInsets.only(top: 24, bottom: 8),
      icon: Center(
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accentColor.withValues(alpha: 0.15),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.35),
              width: 2,
            ),
          ),
          child: Icon(
            Icons.local_fire_department_rounded,
            color: accentColor,
            size: 34,
          ),
        ),
      ),
      title: Text(
        isCritical ? 'Surchauffe Critique' : 'Alerte Surchauffe',
        textAlign: TextAlign.center,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: LKColors.textPrimary,
          fontSize: 21,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'La température de votre appareil est anormalement élevée. '
              'Pour protéger les composants et la batterie, les performances peuvent être réduites.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: LKColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: LKColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: LKColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recommandations immédiates :',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: LKColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildAdviceRow(
                    icon: Icons.wb_sunny_outlined,
                    text: 'Éloignez l\'appareil de la lumière directe du soleil.',
                  ),
                  const SizedBox(height: 8),
                  _buildAdviceRow(
                    icon: Icons.phone_android_rounded,
                    text: 'Retirez la coque de protection pour dissiper la chaleur.',
                  ),
                  const SizedBox(height: 8),
                  _buildAdviceRow(
                    icon: Icons.power_off_outlined,
                    text: 'Débranchez le chargeur si le téléphone est en charge.',
                  ),
                  const SizedBox(height: 8),
                  _buildAdviceRow(
                    icon: Icons.pause_circle_outline_rounded,
                    text: 'Fermez les applications en arrière-plan ou faites une pause.',
                  ),
                ],
              ),
            ),
            if (info != null && (info!.batteryTempC != null || info!.statusName != 'NONE')) ...[
              const SizedBox(height: 12),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.thermostat_rounded, size: 14, color: accentColor),
                      const SizedBox(width: 4),
                      Text(
                        _buildStatusLabel(info!),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      actions: [
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('J\'ai compris'),
          ),
        ),
      ],
    );
  }

  Widget _buildAdviceRow({required IconData icon, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: LKColors.textHint),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              color: LKColors.textSecondary,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  String _buildStatusLabel(ThermalInfo info) {
    final parts = <String>[];
    if (info.statusName != 'NONE' && info.statusName != 'UNKNOWN') {
      parts.add('Niveau : ${info.statusName}');
    }
    if (info.batteryTempC != null) {
      parts.add('${info.batteryTempC!.toStringAsFixed(1)}°C');
    }
    return parts.isNotEmpty ? parts.join(' · ') : 'Appareil chaud';
  }
}
