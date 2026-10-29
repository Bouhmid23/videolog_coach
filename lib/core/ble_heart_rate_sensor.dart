import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

// ─── Types & Statuts partagés des capteurs sport BLE ─────────────────────────

enum SensorType { hrm, cadence, unknown }

enum SensorConnectionState { disconnected, connecting, connected, failed }

class SensorStatus {
  final SensorType type;
  final SensorConnectionState state;
  final String? deviceId;
  final String? deviceName;
  final String? error;
  final int? battery;

  const SensorStatus({
    required this.type,
    required this.state,
    this.deviceId,
    this.deviceName,
    this.error,
    this.battery,
  });

  bool get isConnected => state == SensorConnectionState.connected;
  bool get isBusy => state == SensorConnectionState.connecting;
}

/// Service dédié et testable unitairement pour un capteur cardio BLE
/// (Bluetooth SIG Heart Rate Service `0x180D` / Measurement `0x2A37`).
class BleHeartRateSensor {
  BleHeartRateSensor({FlutterReactiveBle? ble}) : _ble = ble;

  static final Uuid serviceUuid = Uuid.parse(
    '0000180D-0000-1000-8000-00805F9B34FB',
  );
  static final Uuid measurementCharUuid = Uuid.parse(
    '00002A37-0000-1000-8000-00805F9B34FB',
  );
  static final Uuid batteryServiceUuid = Uuid.parse(
    '0000180F-0000-1000-8000-00805F9B34FB',
  );
  static final Uuid batteryCharUuid = Uuid.parse(
    '00002A19-0000-1000-8000-00805F9B34FB',
  );

  FlutterReactiveBle? _ble;
  FlutterReactiveBle get _reactiveBle => _ble ??= FlutterReactiveBle();

  StreamSubscription<ConnectionStateUpdate>? _connectionSub;
  StreamSubscription<List<int>>? _charSub;
  StreamSubscription<List<int>>? _batterySub;

  final _statusCtrl = StreamController<SensorStatus>.broadcast();
  final _heartRateCtrl = StreamController<int>.broadcast();

  SensorStatus _status = const SensorStatus(
    type: SensorType.hrm,
    state: SensorConnectionState.disconnected,
  );
  int? _lastHeartRate;
  String? _deviceId;

  Stream<int> get heartRateStream => _heartRateCtrl.stream;
  Stream<SensorStatus> get statusStream => _statusCtrl.stream;
  SensorStatus get status => _status;
  bool get isConnected => _status.isConnected;
  int? get lastHeartRate => _lastHeartRate;
  String? get deviceId => _deviceId;

  /// Reconnaît un capteur cardio BLE d'après ses services annoncés ou son nom.
  static bool matchesDevice(DiscoveredDevice device) {
    final serviceUuids = device.serviceUuids
        .map((u) => u.toString().toLowerCase())
        .toList();
    final name = device.name.toLowerCase();
    return serviceUuids.any((u) => u.contains('180d')) ||
        name.contains('hrm') ||
        name.contains('heart');
  }

  /// Décode une trame Heart Rate Measurement (`0x2A37`) selon la spécification Bluetooth SIG.
  /// - Bit 0 des flags : `0` = fréquence cardiaque sur UINT8 (1 octet), `1` = UINT16 (2 octets LE).
  static int? parseMeasurement(List<int> bytes) {
    if (bytes.isEmpty) return null;
    final flags = bytes[0];
    final isUint16 = (flags & 0x01) == 1;
    final minLength = isUint16 ? 3 : 2;
    if (bytes.length < minLength) return null;

    if (isUint16) {
      return bytes[1] | (bytes[2] << 8);
    }
    return bytes[1];
  }

  /// Point d'entrée testable unitairement pour injecter une trame brute `0x2A37`.
  int? handleMeasurementBytes(List<int> bytes) {
    final hr = parseMeasurement(bytes);
    if (hr != null) {
      _lastHeartRate = hr;
      _heartRateCtrl.add(hr);
    }
    return hr;
  }

  /// Point d'entrée testable unitairement pour injecter un niveau de batterie `0x2A19`.
  void handleBatteryBytes(List<int> bytes) {
    if (bytes.isEmpty) return;
    final battery = bytes[0].clamp(0, 100);
    _status = SensorStatus(
      type: SensorType.hrm,
      state: _status.state,
      deviceId: _deviceId,
      battery: battery,
    );
    _statusCtrl.add(_status);
  }

  Future<void> connect(String targetDeviceId) async {
    if (_deviceId == targetDeviceId && _status.isConnected) return;
    await disconnect();

    _deviceId = targetDeviceId;
    _status = SensorStatus(
      type: SensorType.hrm,
      state: SensorConnectionState.connecting,
      deviceId: targetDeviceId,
    );
    _statusCtrl.add(_status);

    _connectionSub = _reactiveBle
        .connectToDevice(
          id: targetDeviceId,
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen(
          (update) async {
            if (update.connectionState == DeviceConnectionState.connected) {
              _status = SensorStatus(
                type: SensorType.hrm,
                state: SensorConnectionState.connected,
                deviceId: targetDeviceId,
              );
              _statusCtrl.add(_status);

              await _subscribeMeasurement(targetDeviceId);
              await _subscribeBattery(targetDeviceId);
            }

            if (update.connectionState == DeviceConnectionState.disconnected) {
              _deviceId = null;
              _lastHeartRate = null;
              _status = const SensorStatus(
                type: SensorType.hrm,
                state: SensorConnectionState.disconnected,
              );
              _statusCtrl.add(_status);
              await _cancelCharSubs();
            }
          },
          onError: (e) {
            debugPrint('HRM connection error: $e');
            _deviceId = null;
            _status = SensorStatus(
              type: SensorType.hrm,
              state: SensorConnectionState.failed,
              error: e.toString(),
            );
            _statusCtrl.add(_status);
          },
        );
  }

  Future<void> _subscribeMeasurement(String targetDeviceId) async {
    await _charSub?.cancel();
    final char = QualifiedCharacteristic(
      deviceId: targetDeviceId,
      serviceId: serviceUuid,
      characteristicId: measurementCharUuid,
    );
    _charSub = _reactiveBle
        .subscribeToCharacteristic(char)
        .listen(
          handleMeasurementBytes,
          onError: (e) => debugPrint('HRM char error: $e'),
        );
  }

  Future<void> _subscribeBattery(String targetDeviceId) async {
    await _batterySub?.cancel();
    try {
      final char = QualifiedCharacteristic(
        deviceId: targetDeviceId,
        serviceId: batteryServiceUuid,
        characteristicId: batteryCharUuid,
      );
      _batterySub = _reactiveBle
          .subscribeToCharacteristic(char)
          .listen(
            handleBatteryBytes,
            onError: (e) => debugPrint('HRM battery char error: $e'),
          );
    } catch (_) {
      // Caractéristique batterie optionnelle selon le capteur.
    }
  }

  Future<void> _cancelCharSubs() async {
    await _charSub?.cancel();
    await _batterySub?.cancel();
    _charSub = null;
    _batterySub = null;
  }

  Future<void> disconnect() async {
    await _cancelCharSubs();
    await _connectionSub?.cancel();
    _connectionSub = null;
    _deviceId = null;
    _lastHeartRate = null;
    _status = const SensorStatus(
      type: SensorType.hrm,
      state: SensorConnectionState.disconnected,
    );
    _statusCtrl.add(_status);
  }

  Future<void> dispose() async {
    await disconnect();
    await _heartRateCtrl.close();
    await _statusCtrl.close();
  }
}
