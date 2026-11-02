import 'dart:async';
import 'package:flutter/foundation.dart' show VoidCallback, debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/athletic_haptics.dart';
import '../../core/ble_sensor_service.dart';
import '../../core/ble_telemetry_service.dart';
import '../../data/heart_rate_zones.dart';
import '../../data/remote_telemetry.dart';
import '../../data/telemetry_codec.dart';
import '../../data/user_role.dart';

/// Coordonne l'acquisition télémétrique locale :
/// - GPS haute précision & calcul de distance accumulée.
/// - Capteurs BLE (ceinture cardio HRM, cadence vélo CSC) & alertes haptiques de zone.
/// - Émission périodique 2 Hz sur le topic LiveKit `telemetry`.
/// - Projection des métriques sur lunettes connectées (HUD ActiveLook / Engo).
class RoomTelemetryCoordinator {
  final BleTelemetryService bleService;
  final BleSensorService sensorService;
  final VoidCallback onTelemetryUpdated;
  final void Function(RemoteTelemetry telemetry)? onLocalTelemetryChanged;

  RoomTelemetryCoordinator({
    required this.bleService,
    required this.sensorService,
    required this.onTelemetryUpdated,
    this.onLocalTelemetryChanged,
  });

  Timer? _telemetryTimer;
  double _simT = 0.0;
  DateTime? _lastGlassesDisplayTime;

  // GPS
  StreamSubscription<Position>? _gpsSub;
  double _totalDistanceMiles = 0.0;
  Position? _lastPosition;

  // Capteurs
  StreamSubscription<int>? _hrmSub;
  StreamSubscription<int>? _cadenceSub;
  StreamSubscription<SensorStatus>? _hrmStatusSub;
  StreamSubscription<SensorStatus>? _cscStatusSub;
  int? _sensorHeartRate;
  int? _sensorCadence;

  // Lunettes BLE
  StreamSubscription<SportMetrics>? _bleMetricsSub;
  SportMetrics? _bleMetrics;

  bool _disposed = false;

  // ── Getters ──
  int? get sensorHeartRate => _sensorHeartRate;
  int? get sensorCadence => _sensorCadence;
  SportMetrics? get bleMetrics => _bleMetrics;
  double get totalDistanceMiles => _totalDistanceMiles;
  double get totalDistanceKm => _totalDistanceMiles * 1.60934;

  RemoteTelemetry buildLocalTelemetry(UserRole role) => RemoteTelemetry(
    heartRate: sensorService.isHrmConnected ? _sensorHeartRate : null,
    cadence: sensorService.isCadenceConnected ? _sensorCadence?.toDouble() : null,
    speed: _lastPosition != null
        ? double.parse((_lastPosition!.speed * 3.6).toStringAsFixed(1))
        : null,
    lat: _lastPosition?.latitude,
    lng: _lastPosition?.longitude,
    altitude: _lastPosition?.altitude,
    bearing: _lastPosition?.heading,
    role: role.wire,
    receivedAt: DateTime.now(),
  );

  void start(Room room, UserRole role) {
    _startTelemetry(room, role);
    unawaited(_startGps());
    _startSensorListeners(room, role);
  }

  void onBleConnected() {
    _bleMetricsSub?.cancel();
    _bleMetricsSub = bleService.metricsStream.listen((data) {
      _bleMetrics = data;
      onTelemetryUpdated();
    });
  }

  void onBleDisconnected() {
    _bleMetrics = null;
    onTelemetryUpdated();
  }

  void _startTelemetry(Room room, UserRole role) {
    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (timer) => _sendTelemetryTick(room, role),
    );
    debugPrint('📡 Telemetry started (2 Hz)');
  }

  void stop() {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    _gpsSub?.cancel();
    _gpsSub = null;
    _hrmSub?.cancel();
    _cadenceSub?.cancel();
    _hrmStatusSub?.cancel();
    _cscStatusSub?.cancel();
    _bleMetricsSub?.cancel();
  }

  void _sendTelemetryTick(Room room, UserRole role) {
    if (room.connectionState != ConnectionState.connected) return;

    _simT += 0.5;

    final heartRate = sensorService.isHrmConnected ? _sensorHeartRate?.toDouble() : null;
    final cadence = sensorService.isCadenceConnected ? _sensorCadence?.toDouble() : null;

    final position = _lastPosition;
    double? speed;
    double? lat;
    double? lng;
    double? altitude;
    double? bearing;

    if (position != null) {
      speed = double.parse((position.speed * 3.6).toStringAsFixed(1));
      lat = position.latitude;
      lng = position.longitude;
      altitude = position.altitude;
      bearing = position.heading;
    }

    final bytes = TelemetryCodec.encode(
      role: role.wire,
      speed: speed,
      heartRate: heartRate,
      cadence: cadence,
      lat: lat,
      lng: lng,
      altitude: altitude,
      bearing: bearing,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );

    try {
      room.localParticipant?.publishData(
        bytes,
        reliable: false,
        topic: 'telemetry',
      );
    } catch (e) {
      debugPrint('⚠️ Telemetry publish error: $e');
    }

    final localTel = buildLocalTelemetry(role);
    onLocalTelemetryChanged?.call(localTel);

    _pushGlassesDisplay(heartRate);
  }

  void _pushGlassesDisplay(double? heartRate) {
    final deviceId = bleService.connectedDeviceId;
    if (deviceId == null || !bleService.isDisplaySessionActive) return;

    final now = DateTime.now();
    if (_lastGlassesDisplayTime != null &&
        now.difference(_lastGlassesDisplayTime!) < const Duration(seconds: 2)) {
      return;
    }
    _lastGlassesDisplayTime = now;

    final dist = _totalDistanceMiles;
    final kcal = heartRate != null
        ? SportMetrics.estimateKcal(
            bpm: heartRate.round(),
            weightKg: 70,
            ageYears: 30,
            isMale: true,
            durationSeconds: _simT.round(),
          ).clamp(0, 9999)
        : 0;

    unawaited(
      bleService.displayMetrics(
        deviceId,
        distanceMiles: dist,
        bpm: heartRate?.round().clamp(30, 220),
        kcal: kcal,
        cadence: _sensorCadence,
      ),
    );
  }

  Future<void> _startGps() async {
    _gpsSub?.cancel();

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (_disposed) return;
    if (!serviceEnabled) {
      debugPrint('⚠️ GPS: Location services are disabled');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (_disposed) return;
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (_disposed) return;
      if (permission == LocationPermission.denied) {
        debugPrint('⚠️ GPS: Location permission denied');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('⚠️ GPS: Location permission denied forever');
      return;
    }

    try {
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((position) {
        if (_lastPosition != null) {
          final delta = SportMetrics.haversineDistanceMiles(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            position.latitude,
            position.longitude,
          );
          _totalDistanceMiles += delta;
        }
        _lastPosition = position;
        onTelemetryUpdated();
      });
      debugPrint('📍 GPS tracking started');
    } catch (e) {
      debugPrint('⚠️ GPS error: $e');
    }
  }

  void _startSensorListeners(Room room, UserRole role) {
    _hrmSub?.cancel();
    _cadenceSub?.cancel();
    _hrmStatusSub?.cancel();
    _cscStatusSub?.cancel();

    _hrmSub = sensorService.heartRateStream.listen((bpm) {
      if (_sensorHeartRate == bpm) return;
      final prevBpm = _sensorHeartRate;
      _sensorHeartRate = bpm;

      final localTel = buildLocalTelemetry(role);
      onLocalTelemetryChanged?.call(localTel);

      if (bpm > 0) {
        final prevZone = prevBpm != null && prevBpm > 0
            ? HeartRateZone.fromBpm(prevBpm)
            : null;
        final newZone = HeartRateZone.fromBpm(bpm);
        if (newZone.level == HeartRateZoneLevel.z5 &&
            prevZone?.level != HeartRateZoneLevel.z5) {
          unawaited(AthleticHaptics.thresholdZone5Alert());
        }
      }
      onTelemetryUpdated();
    });

    _cadenceSub = sensorService.cadenceStream.listen((rpm) {
      if (_sensorCadence == rpm) return;
      _sensorCadence = rpm;

      final localTel = buildLocalTelemetry(role);
      onLocalTelemetryChanged?.call(localTel);
      onTelemetryUpdated();
    });

    _hrmStatusSub = sensorService.hrmStatusStream.listen((status) {
      debugPrint('💓 HRM status: ${status.state}');
    });

    _cscStatusSub = sensorService.cscStatusStream.listen((status) {
      debugPrint('🚴 CSC status: ${status.state}');
    });
  }

  void resetGlassesTimer() {
    _lastGlassesDisplayTime = null;
  }

  void dispose() {
    _disposed = true;
    stop();
  }
}

