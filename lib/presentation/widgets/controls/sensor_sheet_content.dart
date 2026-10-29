import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../../../core/ble_sensor_service.dart';
import '../../../theme.dart';
import '../../utils/ui_utils.dart';

class SensorSheetContent extends StatefulWidget {
  final BleSensorService sensorService;

  const SensorSheetContent({required this.sensorService, super.key});

  @override
  State<SensorSheetContent> createState() => _SensorSheetContentState();
}

class _SensorSheetContentState extends State<SensorSheetContent> {
  StreamSubscription<List<DiscoveredDevice>>? _devicesSub;
  StreamSubscription<SensorStatus>? _hrmStatusSub;
  StreamSubscription<SensorStatus>? _cscStatusSub;
  List<DiscoveredDevice> _devices = [];
  SensorStatus _hrmStatus = const SensorStatus(
    type: SensorType.hrm,
    state: SensorConnectionState.disconnected,
  );
  SensorStatus _cscStatus = const SensorStatus(
    type: SensorType.cadence,
    state: SensorConnectionState.disconnected,
  );

  @override
  void initState() {
    super.initState();
    _hrmStatus = widget.sensorService.hrmStatus;
    _cscStatus = widget.sensorService.cscStatus;
    _devices = widget.sensorService.discoveredDevices;
    _devicesSub = widget.sensorService.devicesStream.listen((d) {
      if (!mounted) return;
      setState(() => _devices = d);
    });
    _hrmStatusSub = widget.sensorService.hrmStatusStream.listen((s) {
      if (!mounted) return;
      setState(() => _hrmStatus = s);
    });
    _cscStatusSub = widget.sensorService.cscStatusStream.listen((s) {
      if (!mounted) return;
      setState(() => _cscStatus = s);
    });
  }

  @override
  void dispose() {
    unawaited(_devicesSub?.cancel());
    unawaited(_hrmStatusSub?.cancel());
    unawaited(_cscStatusSub?.cancel());
    super.dispose();
  }

  List<DiscoveredDevice> _devicesForType(SensorType type) => _devices
      .where((d) => widget.sensorService.classifyDevice(d) == type)
      .toList();

  @override
  Widget build(BuildContext context) {
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.78;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Container(
          margin: UIUtils.paddingHorizontalLG.add(UIUtils.paddingVerticalLG),
          child: ClipRRect(
            borderRadius: UIUtils.borderRadiusAllLG,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AnimatedSize(
                duration: UIUtils.animationDuration,
                curve: UIUtils.animationCurve,
                alignment: Alignment.bottomCenter,
                child: Container(
                  padding: UIUtils.paddingLG,
                  decoration: BoxDecoration(
                    color: LKColors.surfaceElevated,
                    borderRadius: UIUtils.borderRadiusAllLG,
                    border: Border.all(color: LKColors.border, width: 0.5),
                    boxShadow: UIUtils.shadowXL,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.favorite_rounded,
                            color: LKColors.danger,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.speed_rounded,
                            color: LKColors.secondary,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Capteurs Sport',
                            style: UIUtils.titleMedium(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Connectez un capteur cardiaque et/ou de cadence.',
                        style: UIUtils.bodySmall(
                          context,
                        ).copyWith(color: LKColors.textHint),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHrmSection(),
                              const SizedBox(height: 10),
                              _buildCscSection(),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context),
                          style: FilledButton.styleFrom(
                            backgroundColor: LKColors.primary,
                            foregroundColor: Colors.white,
                            padding: UIUtils.paddingVerticalSM,
                            shape: RoundedRectangleBorder(
                              borderRadius: UIUtils.borderRadiusAllSM,
                            ),
                          ),
                          child: Text(
                            'Fermer',
                            style: UIUtils.labelMedium(
                              context,
                            ).copyWith(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHrmSection() {
    final devices = _devicesForType(SensorType.hrm);
    return SensorCard(
      title: 'Fréquence Cardiaque',
      icon: Icons.favorite_rounded,
      iconColor: LKColors.danger,
      status: _hrmStatus,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hrmStatus.isConnected)
            _buildConnectedBanner(
              deviceId: _hrmStatus.deviceId,
              battery: _hrmStatus.battery,
              onDisconnect: () => widget.sensorService.disconnectHrm(),
            )
          else if (_hrmStatus.isBusy)
            Padding(
              padding: UIUtils.paddingVerticalXS,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: LKColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Connexion...', style: UIUtils.bodySmall(context)),
                ],
              ),
            )
          else if (devices.isEmpty)
            Center(
              heightFactor: 1.0,
              child: Padding(
                padding: UIUtils.paddingVerticalXS,
                child: Text(
                  'Recherche capteur HRM...',
                  style: UIUtils.bodySmall(
                    context,
                  ).copyWith(color: LKColors.textHint),
                ),
              ),
            )
          else
            ...devices.map(
              (d) => _buildDeviceTile(
                device: d,
                sensorType: SensorType.hrm,
                onConnect: () => widget.sensorService.connectHrm(d.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCscSection() {
    final devices = _devicesForType(SensorType.cadence);
    return SensorCard(
      title: 'Cadence',
      icon: Icons.speed_rounded,
      iconColor: LKColors.secondary,
      status: _cscStatus,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_cscStatus.isConnected)
            _buildConnectedBanner(
              deviceId: _cscStatus.deviceId,
              battery: _cscStatus.battery,
              onDisconnect: () => widget.sensorService.disconnectCadence(),
            )
          else if (_cscStatus.isBusy)
            Padding(
              padding: UIUtils.paddingVerticalXS,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: LKColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Connexion...', style: UIUtils.bodySmall(context)),
                ],
              ),
            )
          else if (devices.isEmpty)
            Center(
              heightFactor: 1.0,
              child: Padding(
                padding: UIUtils.paddingVerticalXS,
                child: Text(
                  'Recherche capteur cadence...',
                  style: UIUtils.bodySmall(
                    context,
                  ).copyWith(color: LKColors.textHint),
                ),
              ),
            )
          else
            ...devices.map(
              (d) => _buildDeviceTile(
                device: d,
                sensorType: SensorType.cadence,
                onConnect: () => widget.sensorService.connectCadence(d.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConnectedBanner({
    String? deviceId,
    int? battery,
    required VoidCallback onDisconnect,
  }) {
    final displayId = deviceId != null && deviceId.length > 8
        ? deviceId.substring(0, 8)
        : deviceId ?? '\u2014';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: LKColors.success.withValues(alpha: 0.08),
        borderRadius: UIUtils.borderRadiusAllSM,
        border: Border.all(color: LKColors.success.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.bluetooth_connected_rounded,
            size: 16,
            color: LKColors.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayId,
                  style: UIUtils.labelMedium(context).copyWith(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (battery != null)
                  Text(
                    'Batterie: $battery%',
                    style: UIUtils.bodySmall(
                      context,
                    ).copyWith(fontSize: 10, color: LKColors.textHint),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: onDisconnect,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              'Déconnecter',
              style: TextStyle(fontSize: 11, color: LKColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTile({
    required DiscoveredDevice device,
    required SensorType sensorType,
    required VoidCallback onConnect,
  }) {
    final name = device.name.isEmpty
        ? 'Inconnu (${device.id.substring(0, math.min(8, device.id.length))})'
        : device.name;
    return AnimatedPadding(
      duration: UIUtils.animationDuration,
      padding: UIUtils.paddingVerticalSM,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          sensorType == SensorType.hrm
              ? Icons.favorite_rounded
              : Icons.speed_rounded,
          size: 18,
          color: sensorType == SensorType.hrm
              ? LKColors.danger
              : LKColors.secondary,
        ),
        title: Text(name, style: UIUtils.bodySmall(context)),
        subtitle: Text(
          'RSSI ${device.rssi}',
          style: UIUtils.bodySmall(
            context,
          ).copyWith(color: LKColors.textHint, fontSize: 10),
        ),
        trailing: OutlinedButton(
          onPressed: onConnect,
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            shape: RoundedRectangleBorder(
              borderRadius: UIUtils.borderRadiusAllSM,
            ),
            side: BorderSide(color: LKColors.border, width: 0.5),
          ),
          child: Text(
            'Connecter',
            style: TextStyle(fontSize: 11, color: LKColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class SensorCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final SensorStatus status;
  final Widget child;

  const SensorCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.status,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isConnected = status.isConnected;
    return Container(
      width: double.infinity,
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: isConnected
            ? LKColors.success.withValues(alpha: 0.04)
            : LKColors.surface.withValues(alpha: 0.3),
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(
          color: isConnected
              ? LKColors.success.withValues(alpha: 0.3)
              : LKColors.border.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: isConnected ? LKColors.success : iconColor,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isConnected ? LKColors.success : LKColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (isConnected)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: LKColors.success.withValues(alpha: 0.15),
                    borderRadius: UIUtils.borderRadiusAllSM,
                  ),
                  child: Text(
                    'CONNECTÉ',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: LKColors.success,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
