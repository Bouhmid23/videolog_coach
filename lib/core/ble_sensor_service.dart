import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_cadence_speed_sensor.dart';
import 'ble_heart_rate_sensor.dart';

export 'ble_cadence_speed_sensor.dart';
export 'ble_heart_rate_sensor.dart';

/// Orchestrateur léger des capteurs sport BLE qui délègue aux services dédiés :
/// - [BleHeartRateSensor] (cardio `0x180D` / `0x2A37`)
/// - [BleCadenceSpeedSensor] (cadence/vitesse `0x1816` / `0x2A5B`)
class BleSensorService {
  BleSensorService({
    FlutterReactiveBle? ble,
    BleHeartRateSensor? hrmSensor,
    BleCadenceSpeedSensor? cadenceSensor,
  }) : _ble = ble,
       hrm = hrmSensor ?? BleHeartRateSensor(ble: ble),
       cadence = cadenceSensor ?? BleCadenceSpeedSensor(ble: ble);

  FlutterReactiveBle? _ble;
  FlutterReactiveBle get _reactiveBle => _ble ??= FlutterReactiveBle();

  final BleHeartRateSensor hrm;
  final BleCadenceSpeedSensor cadence;

  // ── Scan ──
  StreamSubscription<DiscoveredDevice>? _scanSub;
  final _devicesCtrl = StreamController<List<DiscoveredDevice>>.broadcast();
  final List<DiscoveredDevice> _devices = [];

  // ── Public streams ──
  List<DiscoveredDevice> get discoveredDevices => List.unmodifiable(_devices);
  Stream<List<DiscoveredDevice>> get devicesStream => _devicesCtrl.stream;
  Stream<int> get heartRateStream => hrm.heartRateStream;
  Stream<int> get cadenceStream => cadence.cadenceStream;
  Stream<SensorStatus> get hrmStatusStream => hrm.statusStream;
  Stream<SensorStatus> get cscStatusStream => cadence.statusStream;

  // ── Public getters ──
  bool get isHrmConnected => hrm.isConnected;
  bool get isCadenceConnected => cadence.isConnected;
  int? get lastHeartRate => hrm.lastHeartRate;
  int? get lastCadence => cadence.lastCadence;
  SensorStatus get hrmStatus => hrm.status;
  SensorStatus get cscStatus => cadence.status;
  String? get hrmDeviceId => hrm.deviceId;
  String? get cscDeviceId => cadence.deviceId;

  // ─── Scan ───────────────────────────────────────────────────────────────────

  Future<void> startScan() async {
    await _scanSub?.cancel();
    _devicesCtrl.add(List.unmodifiable(_devices));

    _scanSub = _reactiveBle
        .scanForDevices(withServices: [], scanMode: ScanMode.lowLatency)
        .listen(
          (d) {
            final i = _devices.indexWhere((e) => e.id == d.id);
            if (i >= 0) {
              _devices[i] = d;
            } else {
              _devices.add(d);
            }
            _devicesCtrl.add(List.unmodifiable(_devices));
          },
          onError: (e) {
            debugPrint('BLE Sensor scan error: $e');
            _devicesCtrl.addError(e);
          },
        );
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
  }

  // ─── Connexions / Déconnexions déléguées aux services dédiés ────────────────

  Future<void> connectHrm(String deviceId) => hrm.connect(deviceId);
  Future<void> disconnectHrm() => hrm.disconnect();

  Future<void> connectCadence(String deviceId) => cadence.connect(deviceId);
  Future<void> disconnectCadence() => cadence.disconnect();

  // ─── Classification d'un appareil découvert ─────────────────────────────────

  SensorType classifyDevice(DiscoveredDevice device) {
    final hasHrm = BleHeartRateSensor.matchesDevice(device);
    final hasCsc = BleCadenceSpeedSensor.matchesDevice(device);
    if (hasHrm) return SensorType.hrm;
    if (hasCsc) return SensorType.cadence;
    return SensorType.unknown;
  }

  // ─── Cleanup ───────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await stopScan();
    await hrm.dispose();
    await cadence.dispose();
    await _devicesCtrl.close();
  }
}
