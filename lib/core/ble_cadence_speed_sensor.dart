import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_heart_rate_sensor.dart';

/// Service dédié et testable unitairement pour un capteur de cadence/vitesse BLE
/// (Bluetooth SIG Cycling Speed & Cadence Service `0x1816` / Measurement `0x2A5B`).
class BleCadenceSpeedSensor {
  BleCadenceSpeedSensor({FlutterReactiveBle? ble}) : _ble = ble;

  static final Uuid serviceUuid = Uuid.parse(
    '00001816-0000-1000-8000-00805F9B34FB',
  );
  static final Uuid measurementCharUuid = Uuid.parse(
    '00002A5B-0000-1000-8000-00805F9B34FB',
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
  final _cadenceCtrl = StreamController<int>.broadcast();

  SensorStatus _status = const SensorStatus(
    type: SensorType.cadence,
    state: SensorConnectionState.disconnected,
  );
  int? _lastCadence;
  String? _deviceId;
  int? _lastCrankRev;
  int? _lastCrankTime; // en 1/1024 seconde

  Stream<int> get cadenceStream => _cadenceCtrl.stream;
  Stream<SensorStatus> get statusStream => _statusCtrl.stream;
  SensorStatus get status => _status;
  bool get isConnected => _status.isConnected;
  int? get lastCadence => _lastCadence;
  String? get deviceId => _deviceId;

  /// Reconnaît un capteur de cadence/vitesse BLE d'après ses services annoncés ou son nom.
  static bool matchesDevice(DiscoveredDevice device) {
    final serviceUuids = device.serviceUuids
        .map((u) => u.toString().toLowerCase())
        .toList();
    final name = device.name.toLowerCase();
    return serviceUuids.any((u) => u.contains('1816')) ||
        name.contains('cadence') ||
        name.contains('csc') ||
        name.contains('tilt');
  }

  /// Réinitialise l'état des révolutions de pédalier (ex. à la déconnexion).
  void resetCrankState() {
    _lastCrankRev = null;
    _lastCrankTime = null;
  }

  /// Décode une trame CSC Measurement (`0x2A5B`) selon la spécification Bluetooth SIG
  /// et calcule la cadence en tr/min (RPM) à partir du delta de révolutions et de temps.
  int? parseMeasurement(List<int> bytes) {
    if (bytes.isEmpty) return null;
    final flags = bytes[0];
    final hasCrank = (flags & 0x02) != 0;
    if (!hasCrank) return null;

    final hasWheel = (flags & 0x01) != 0;
    final offset = 1 + (hasWheel ? 6 : 0);
    if (bytes.length < offset + 4) return null;

    final crankRev = bytes[offset] | (bytes[offset + 1] << 8);
    final crankTime = bytes[offset + 2] | (bytes[offset + 3] << 8);

    return _calculateCadence(crankRev, crankTime);
  }

  int? _calculateCadence(int currentRev, int currentTime) {
    final prevRev = _lastCrankRev;
    final prevTime = _lastCrankTime;

    _lastCrankRev = currentRev;
    _lastCrankTime = currentTime;

    if (prevRev == null || prevTime == null) return null;

    // Gestion du débordement sur 16 bits (modulo 65536)
    var revDelta = currentRev - prevRev;
    if (revDelta < 0) revDelta += 65536;

    var timeDelta = currentTime - prevTime;
    if (timeDelta < 0) timeDelta += 65536;

    if (timeDelta == 0) return null;

    final timeSeconds = timeDelta / 1024.0;
    final rpm = (revDelta / timeSeconds) * 60.0;
    return rpm.round().clamp(0, 200);
  }

  /// Point d'entrée testable unitairement pour injecter une trame brute `0x2A5B`.
  int? handleMeasurementBytes(List<int> bytes) {
    final cadence = parseMeasurement(bytes);
    if (cadence != null) {
      _lastCadence = cadence;
      _cadenceCtrl.add(cadence);
    }
    return cadence;
  }

  /// Point d'entrée testable unitairement pour injecter un niveau de batterie `0x2A19`.
  void handleBatteryBytes(List<int> bytes) {
    if (bytes.isEmpty) return;
    final battery = bytes[0].clamp(0, 100);
    _status = SensorStatus(
      type: SensorType.cadence,
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
      type: SensorType.cadence,
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
                type: SensorType.cadence,
                state: SensorConnectionState.connected,
                deviceId: targetDeviceId,
              );
              _statusCtrl.add(_status);

              await _subscribeMeasurement(targetDeviceId);
              await _subscribeBattery(targetDeviceId);
            }

            if (update.connectionState == DeviceConnectionState.disconnected) {
              _deviceId = null;
              _lastCadence = null;
              resetCrankState();
              _status = const SensorStatus(
                type: SensorType.cadence,
                state: SensorConnectionState.disconnected,
              );
              _statusCtrl.add(_status);
              await _cancelCharSubs();
            }
          },
          onError: (e) {
            debugPrint('CSC connection error: $e');
            _deviceId = null;
            _status = SensorStatus(
              type: SensorType.cadence,
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
          onError: (e) => debugPrint('CSC char error: $e'),
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
            onError: (e) => debugPrint('CSC battery char error: $e'),
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
    _lastCadence = null;
    resetCrankState();
    _status = const SensorStatus(
      type: SensorType.cadence,
      state: SensorConnectionState.disconnected,
    );
    _statusCtrl.add(_status);
  }

  Future<void> dispose() async {
    await disconnect();
    await _cadenceCtrl.close();
    await _statusCtrl.close();
  }
}
