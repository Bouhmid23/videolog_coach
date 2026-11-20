import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' show BleStatus;

import '../../../theme.dart';
import '../../utils/ui_utils.dart';

enum GpsCheckState { checking, ready, searching, disabled, denied }

/// Carte d'état des capteurs Bluetooth Low Energy (BLE) et GPS sur l'écran de pré-connexion.
class ConnectSensorsStatusCard extends StatelessWidget {
  const ConnectSensorsStatusCard({
    super.key,
    required this.bleStatus,
    required this.gpsState,
    required this.gpsAccuracyMeters,
    required this.onRefresh,
  });

  final BleStatus bleStatus;
  final GpsCheckState gpsState;
  final double? gpsAccuracyMeters;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final (bleLabel, bleSubtitle, bleColor, bleIcon) = _bleStatusPresentation();
    final (gpsLabel, gpsSubtitle, gpsColor, gpsIcon) = _gpsStatusPresentation();

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
                Icons.sensors_rounded,
                size: 18,
                color: LKColors.secondary,
              ),
              SizedBox(width: UIUtils.sm),
              Expanded(
                child: Text(
                  'État des capteurs (BLE & GPS)',
                  style: UIUtils.labelLarge(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                color: LKColors.textSecondary,
                tooltip: 'Actualiser l\'état des capteurs',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
            ],
          ),
          SizedBox(height: UIUtils.sm),
          _buildSensorRow(
            context,
            icon: bleIcon,
            title: 'Bluetooth Low Energy (BLE)',
            subtitle: bleSubtitle,
            badgeLabel: bleLabel,
            color: bleColor,
          ),
          Container(
            height: 0.5,
            margin: EdgeInsets.symmetric(vertical: UIUtils.sm),
            color: LKColors.border.withValues(alpha: 0.7),
          ),
          _buildSensorRow(
            context,
            icon: gpsIcon,
            title: 'Géolocalisation GPS',
            subtitle: gpsSubtitle,
            badgeLabel: gpsLabel,
            color: gpsColor,
          ),
        ],
      ),
    );
  }

  (String, String, Color, IconData) _bleStatusPresentation() {
    switch (bleStatus) {
      case BleStatus.ready:
        return (
          'Prêt',
          'Prêt pour lunettes Engo, cardio HRM et cadence',
          LKColors.success,
          Icons.bluetooth_connected_rounded,
        );
      case BleStatus.poweredOff:
        return (
          'Désactivé',
          'Activez le Bluetooth pour connecter vos capteurs',
          LKColors.danger,
          Icons.bluetooth_disabled_rounded,
        );
      case BleStatus.unauthorized:
        return (
          'Permission',
          'Autorisation Bluetooth requise dans les réglages',
          LKColors.warning,
          Icons.bluetooth_searching_rounded,
        );
      case BleStatus.locationServicesDisabled:
        return (
          'Localisation off',
          'La localisation est requise pour le scan BLE Android',
          LKColors.warning,
          Icons.location_disabled_rounded,
        );
      case BleStatus.unsupported:
        return (
          'Non supporté',
          'Bluetooth Low Energy non disponible sur cet appareil',
          LKColors.textHint,
          Icons.bluetooth_disabled_rounded,
        );
      case BleStatus.unknown:
        return (
          'Vérification…',
          'Initialisation de l\'adaptateur Bluetooth…',
          LKColors.secondary,
          Icons.bluetooth_rounded,
        );
    }
  }

  (String, String, Color, IconData) _gpsStatusPresentation() {
    switch (gpsState) {
      case GpsCheckState.ready:
        final acc = gpsAccuracyMeters != null
            ? ' (±${gpsAccuracyMeters!.round()} m)'
            : '';
        return (
          'Signal OK$acc',
          'Vitesse et télémétrie extérieure disponibles',
          LKColors.success,
          Icons.gps_fixed_rounded,
        );
      case GpsCheckState.searching:
        return (
          'Recherche…',
          'GPS actif · Acquisition des satellites en cours',
          LKColors.secondary,
          Icons.gps_not_fixed_rounded,
        );
      case GpsCheckState.disabled:
        return (
          'Désactivé',
          'Activez la localisation pour la vitesse GPS',
          LKColors.danger,
          Icons.location_disabled_rounded,
        );
      case GpsCheckState.denied:
        return (
          'Permission',
          'Autorisation de localisation refusée',
          LKColors.warning,
          Icons.location_off_rounded,
        );
      case GpsCheckState.checking:
        return (
          'Vérification…',
          'Test du capteur GPS…',
          LKColors.secondary,
          Icons.my_location_rounded,
        );
    }
  }

  Widget _buildSensorRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String badgeLabel,
    required Color color,
  }) {
    return Semantics(
      label: '$title : $badgeLabel. $subtitle',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: UIUtils.borderRadiusAllSM,
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            SizedBox(width: UIUtils.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: UIUtils.bodyMedium(
                      context,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    subtitle,
                    style: UIUtils.bodySmall(
                      context,
                    ).copyWith(color: LKColors.textHint, fontSize: 11),
                  ),
                ],
              ),
            ),
            SizedBox(width: UIUtils.sm),
            Container(
              padding: EdgeInsets.symmetric(horizontal: UIUtils.sm, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: UIUtils.borderRadiusAllFull,
                border: Border.all(
                  color: color.withValues(alpha: 0.22),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 13, color: color),
                  const SizedBox(width: 5),
                  Text(
                    badgeLabel,
                    style: UIUtils.bodySmall(context).copyWith(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
