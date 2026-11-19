import 'dart:async';
import 'package:flutter/foundation.dart'
    show TargetPlatform, VoidCallback, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/athletic_haptics.dart';
import '../../core/ble_sensor_service.dart';
import '../../core/ble_telemetry_service.dart';
import '../../data/athlete_profile.dart';
import '../../data/heart_rate_zones.dart';
import '../../data/remote_telemetry.dart';
import '../../data/telemetry_codec.dart';
import '../../data/user_role.dart';

/// Coordonne l'acquisition télémétrique locale :
/// - GPS haute précision, filtrage anti-dérive & calcul de distance accumulée.
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
    AthleteProfile athleteProfile = const AthleteProfile(),
    // ignore: prefer_initializing_formals
  }) : _athleteProfile = athleteProfile;

  /// Précision horizontale maximale acceptée (en mètres) pour valider un point GPS.
  static const double maxAcceptableAccuracyMeters = 25.0;

  /// Déplacement minimal (en mètres) pour incrémenter la distance cumulée (anti-bruit stationnaire).
  static const double minMovementDeltaMeters = 3.0;

  /// Vitesse implicite maximale (en km/h) au-delà de laquelle un saut GPS est rejeté.
  static const double maxPlausibleSpeedKmh = 75.0;

  /// Seuil en dessous duquel la vitesse GPS instantanée est considérée nulle (en km/h).
  static const double stationarySpeedThresholdKmh = 1.0;

  Timer? _telemetryTimer;
  double _simT = 0.0;
  DateTime? _lastGlassesDisplayTime;
  AthleteProfile _athleteProfile;

  // GPS
  StreamSubscription<Position>? _gpsSub;
  double _totalDistanceMiles = 0.0;
  Position? _lastPosition;
  Position? _lastDistanceAnchor;

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
  AthleteProfile get athleteProfile => _athleteProfile;

  void updateAthleteProfile(AthleteProfile profile) {
    _athleteProfile = profile;
  }

  /// Assainit la vitesse GPS en km/h :
  /// - Écarte les vitesses négatives (`speed < 0` quand non disponible) ou issues d'un fix imprécis.
  /// - Met à `0.0` les vitesses inférieures à [stationarySpeedThresholdKmh] (dérive à l'arrêt).
  /// - Plafonne aux vitesses plausibles ([maxPlausibleSpeedKmh]).
  static double? sanitizeSpeedKmh(Position? position) {
    if (position == null) return null;
    if (position.accuracy > maxAcceptableAccuracyMeters) return null;
    if (position.speed.isNaN || position.speed.isInfinite || position.speed < 0) {
      return 0.0;
    }
    final rawKmh = position.speed * 3.6;
    if (rawKmh < stationarySpeedThresholdKmh) return 0.0;
    if (rawKmh > maxPlausibleSpeedKmh) return null;
    return double.parse(rawKmh.toStringAsFixed(1));
  }

  /// Calcule le delta de distance (en miles) entre [previous] et [current] si et seulement si
  /// le point [current] est précis et cohérent (pas de saut GPS ni de bruit sur place).
  /// Retourne `null` si le point [current] doit être entièrement ignoré (précision > 25 m ou saut aberrant).
  static double? computeFilteredDistanceDeltaMiles(
    Position? previous,
    Position current,
  ) {
    if (current.accuracy.isNaN ||
        current.accuracy < 0 ||
        current.accuracy > maxAcceptableAccuracyMeters) {
      return null;
    }
    if (previous == null) return 0.0;

    final deltaMiles = SportMetrics.haversineDistanceMiles(
      previous.latitude,
      previous.longitude,
      current.latitude,
      current.longitude,
    );
    final deltaMeters = deltaMiles * 1609.344;

    final dtMs = current.timestamp.difference(previous.timestamp).inMilliseconds;
    if (dtMs > 0) {
      final impliedSpeedKmh = (deltaMeters / (dtMs / 1000.0)) * 3.6;
      if (impliedSpeedKmh > maxPlausibleSpeedKmh) {
        return null;
      }
    }

    if (deltaMeters < minMovementDeltaMeters) {
      return 0.0;
    }

    return deltaMiles;
  }

  /// Traite une nouvelle position GPS (utilisé par le flux Geolocator et testable unitairement).
  bool processPositionUpdate(Position position) {
    final deltaMiles = computeFilteredDistanceDeltaMiles(_lastDistanceAnchor, position);
    if (deltaMiles == null) return false;
    _lastPosition = position;
    if (_lastDistanceAnchor == null || deltaMiles > 0.0) {
      _totalDistanceMiles += deltaMiles;
      _lastDistanceAnchor = position;
    }
    onTelemetryUpdated();
    return true;
  }

  RemoteTelemetry buildLocalTelemetry(UserRole role) {
    final rawHeading = _lastPosition?.heading;
    final bearing = (rawHeading != null &&
            !rawHeading.isNaN &&
            !rawHeading.isInfinite &&
            rawHeading >= 0 &&
            rawHeading <= 360)
        ? (rawHeading.round() % 360).toDouble()
        : null;
    return RemoteTelemetry(
      heartRate: sensorService.isHrmConnected ? _sensorHeartRate : null,
      cadence: sensorService.isCadenceConnected ? _sensorCadence?.toDouble() : null,
      speed: sanitizeSpeedKmh(_lastPosition),
      lat: _lastPosition?.latitude,
      lng: _lastPosition?.longitude,
      altitude: _lastPosition?.altitude,
      bearing: bearing,
      role: role.wire,
      receivedAt: DateTime.now(),
    );
  }

  void start(Room room, UserRole role) {
    unawaited(_loadProfile());
    _startTelemetry(room, role);
    unawaited(_startGps());
    _startSensorListeners(room, role);
  }

  Future<void> _loadProfile() async {
    try {
      final loaded = await AthleteProfile.load();
      if (!_disposed) {
        _athleteProfile = loaded;
      }
    } catch (e) {
      debugPrint('⚠️ Impossible de charger AthleteProfile: $e');
    }
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
      speed = sanitizeSpeedKmh(position);
      lat = position.latitude;
      lng = position.longitude;
      altitude = position.altitude;
      bearing = position.heading >= 0 ? position.heading : null;
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
    final profile = _athleteProfile;
    final kcal = heartRate != null
        ? SportMetrics.estimateKcal(
            bpm: heartRate.round(),
            weightKg: profile.weightKg,
            ageYears: profile.ageYears,
            isMale: profile.isMale,
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
        locationSettings: buildLocationSettings(),
      ).listen(processPositionUpdate);
      debugPrint('📍 GPS tracking started');
    } catch (e) {
      debugPrint('⚠️ GPS error: $e');
    }
  }

  /// Construit la configuration GPS adaptée à la plateforme (avec maintien en
  /// arrière-plan et profil `fitness` sur iOS).
  static LocationSettings buildLocationSettings({TargetPlatform? platform}) {
    final target = platform ?? defaultTargetPlatform;
    if (!kIsWeb &&
        (target == TargetPlatform.iOS || target == TargetPlatform.macOS)) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
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
        final maxHr = _athleteProfile.maxHeartRate;
        final prevZone = prevBpm != null && prevBpm > 0
            ? HeartRateZone.fromBpm(prevBpm, maxHr: maxHr)
            : null;
        final newZone = HeartRateZone.fromBpm(bpm, maxHr: maxHr);
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

