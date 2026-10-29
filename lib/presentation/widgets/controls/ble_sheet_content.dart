import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../../../core/ble_telemetry_service.dart';
import '../../../theme.dart';
import '../../utils/ui_utils.dart';
import 'glasses_icon.dart';

class BleSheetContent extends StatefulWidget {
  final BleTelemetryService bleService;
  final Future<void> Function(String deviceId) onConnect;
  final Future<void> Function() onDisconnect;
  final Future<void> Function() onToggleDisplay;

  const BleSheetContent({
    required this.bleService,
    required this.onConnect,
    required this.onDisconnect,
    required this.onToggleDisplay,
    super.key,
  });

  @override
  State<BleSheetContent> createState() => _BleSheetContentState();
}

class _BleSheetContentState extends State<BleSheetContent> {
  StreamSubscription<BleConnectionStatus>? _statusSub;
  StreamSubscription<List<DiscoveredDevice>>? _devicesSub;
  BleConnectionStatus _status = BleConnectionStatus.idle();
  List<DiscoveredDevice> _devices = const [];

  @override
  void initState() {
    super.initState();
    _status = widget.bleService.connectionStatus;
    _statusSub = widget.bleService.connectionStatusStream.listen((s) {
      if (!mounted) return;
      setState(() => _status = s);
    });
    _devicesSub = widget.bleService.devicesStream.listen((d) {
      if (!mounted) return;
      setState(() => _devices = d);
    });
  }

  @override
  void dispose() {
    unawaited(_statusSub?.cancel());
    unawaited(_devicesSub?.cancel());
    super.dispose();
  }

  String? get _connectedDeviceId => widget.bleService.connectedDeviceId;
  bool get _isDisplaySessionActive => widget.bleService.isDisplaySessionActive;
  bool get _isBusy =>
      _status.isBusy || _status.phase == BleConnectionPhase.ready;
  List<DiscoveredDevice> get _engoDevices =>
      _devices.where(widget.bleService.isEngoDevice).toList();

  IconData _phaseIcon(BleConnectionPhase phase) {
    switch (phase) {
      case BleConnectionPhase.ready:
        return Icons.check_circle_rounded;
      case BleConnectionPhase.failed:
        return Icons.error_outline_rounded;
      case BleConnectionPhase.disconnected:
        return Icons.link_off_rounded;
      default:
        return Icons.visibility_rounded;
    }
  }

  Color _phaseColor(BleConnectionPhase phase) {
    switch (phase) {
      case BleConnectionPhase.ready:
        return LKColors.success;
      case BleConnectionPhase.failed:
        return LKColors.danger;
      case BleConnectionPhase.disconnected:
        return LKColors.textHint;
      default:
        return LKColors.warning;
    }
  }

  String _statusLabel(BleConnectionPhase phase) {
    switch (phase) {
      case BleConnectionPhase.idle:
        return 'Prêt';
      case BleConnectionPhase.connecting:
        return 'Connexion en cours...';
      case BleConnectionPhase.connected:
        return 'Connexion établie';
      case BleConnectionPhase.initializing:
        return 'Initialisation...';
      case BleConnectionPhase.ready:
        return 'Connecté ✓';
      case BleConnectionPhase.disconnecting:
        return 'Déconnexion...';
      case BleConnectionPhase.disconnected:
        return 'Déconnecté';
      case BleConnectionPhase.failed:
        return 'Échec de connexion';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final hasActiveStatus =
        status.phase != BleConnectionPhase.idle &&
        status.phase != BleConnectionPhase.disconnected;
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
                    color: LKColors.lkDarkBlue,
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
                          GlassesIcon(size: 24, color: LKColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Lunettes Engo',
                            style: UIUtils.titleMedium(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Connectez vos lunettes Engo ActiveLook pour afficher la télémétrie.',
                        style: UIUtils.bodySmall(
                          context,
                        ).copyWith(color: LKColors.textHint),
                      ),
                      const SizedBox(height: 12),
                      if (hasActiveStatus) _buildStatusCard(status),
                      if (hasActiveStatus) const SizedBox(height: 12),
                      Flexible(child: _buildDeviceList(status)),
                      if (_connectedDeviceId != null) ...[
                        const SizedBox(height: 8),
                        _buildSessionSection(),
                      ],
                      const SizedBox(height: 12),
                      _buildActionRow(),
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

  Widget _buildStatusCard(BleConnectionStatus status) {
    final phase = status.phase;
    final isProgress =
        phase == BleConnectionPhase.connecting ||
        phase == BleConnectionPhase.initializing ||
        phase == BleConnectionPhase.disconnecting;
    final sessionMsg =
        phase == BleConnectionPhase.ready && status.message.isNotEmpty
        ? status.message
        : null;

    return AnimatedContainer(
      duration: UIUtils.animationDuration,
      width: double.infinity,
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: _phaseColor(phase).withValues(alpha: 0.08),
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(color: _phaseColor(phase).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: isProgress
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _phaseColor(phase),
                      ),
                    ),
                  )
                : Icon(_phaseIcon(phase), size: 18, color: _phaseColor(phase)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusLabel(phase),
                  style: TextStyle(
                    color: _phaseColor(phase),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (sessionMsg != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sessionMsg,
                    style: TextStyle(
                      color: _phaseColor(phase).withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
                if (status.message.isNotEmpty &&
                    phase != BleConnectionPhase.ready &&
                    !isProgress) ...[
                  const SizedBox(height: 2),
                  Text(
                    status.message,
                    style: TextStyle(color: LKColors.textHint, fontSize: 12),
                  ),
                ],
                if (status.error != null && status.error!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    status.error!,
                    style: TextStyle(color: LKColors.danger, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(BleConnectionStatus status) {
    final engoDevices = _engoDevices;
    if (engoDevices.isEmpty) {
      return Center(
        heightFactor: 1.0,
        child: Padding(
          padding: UIUtils.paddingVerticalSM,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassesIcon(size: 20, color: LKColors.textHint),
              const SizedBox(width: 8),
              Text(
                'Recherche de lunettes Engo...',
                style: UIUtils.bodySmall(context),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: engoDevices.length,
      itemBuilder: (context, i) {
        final device = engoDevices[i];
        final name = device.name.isEmpty
            ? 'Inconnu (${device.id})'
            : device.name;
        final isConnected = _connectedDeviceId == device.id;
        final isConnectingThis =
            status.deviceId == device.id &&
            (status.phase == BleConnectionPhase.connecting ||
                status.phase == BleConnectionPhase.connected ||
                status.phase == BleConnectionPhase.initializing);

        return AnimatedPadding(
          duration: UIUtils.animationDuration,
          padding: UIUtils.paddingVerticalSM,
          child: Card(
            color: LKColors.lkDarkBlue,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: UIUtils.borderRadiusAllMD,
              side: BorderSide(color: LKColors.border, width: 0.5),
            ),
            child: ListTile(
              title: Text(name, style: UIUtils.labelMedium(context)),
              subtitle: Text(
                'RSSI ${device.rssi}',
                style: UIUtils.bodySmall(context),
              ),
              trailing: isConnected
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: LKColors.success.withValues(alpha: 0.1),
                        borderRadius: UIUtils.borderRadiusAllSM,
                      ),
                      child: Text(
                        'Connecté',
                        style: TextStyle(
                          fontSize: 11,
                          color: LKColors.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : isConnectingThis
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          LKColors.primary,
                        ),
                      ),
                    )
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: UIUtils.borderRadiusAllSM,
                        ),
                        side: BorderSide(color: LKColors.border, width: 0.5),
                      ),
                      onPressed: _isBusy
                          ? null
                          : () => widget.onConnect(device.id),
                      child: Text(
                        'Connecter',
                        style: TextStyle(
                          fontSize: 11,
                          color: _isBusy
                              ? LKColors.textHint
                              : LKColors.textPrimary,
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSessionSection() {
    return AnimatedContainer(
      duration: UIUtils.animationDuration,
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: LKColors.lkDarkBlue.withValues(alpha: 0.5),
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(color: LKColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(
            _isDisplaySessionActive
                ? Icons.stop_circle_rounded
                : Icons.play_circle_fill_rounded,
            color: _isDisplaySessionActive ? LKColors.danger : LKColors.success,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _isDisplaySessionActive ? 'Session en cours' : 'Session arrêtée',
              style: UIUtils.labelMedium(context),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            icon: Icon(
              _isDisplaySessionActive
                  ? Icons.stop_rounded
                  : Icons.play_arrow_rounded,
              size: 16,
            ),
            onPressed: widget.onToggleDisplay,
            label: Text(
              _isDisplaySessionActive ? 'Arrêter' : 'Démarrer',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              padding: UIUtils.paddingHorizontalMD.add(
                UIUtils.paddingVerticalSM,
              ),
              backgroundColor: _isDisplaySessionActive
                  ? LKColors.danger
                  : LKColors.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: UIUtils.borderRadiusAllSM,
              ),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => widget.onDisconnect(),
            style: OutlinedButton.styleFrom(
              foregroundColor: LKColors.textPrimary,
              padding: UIUtils.paddingVerticalSM,
              shape: RoundedRectangleBorder(
                borderRadius: UIUtils.borderRadiusAllSM,
              ),
              side: BorderSide(color: LKColors.border, width: 0.5),
            ),
            child: Text('Déconnecter', style: UIUtils.labelMedium(context)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
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
              style: UIUtils.labelMedium(context).copyWith(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
