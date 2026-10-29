export 'ble_cadence_speed_sensor.dart';
export 'ble_heart_rate_sensor.dart';
export 'engo_glasses_display_service.dart';

import 'engo_glasses_display_service.dart';

/// Alias de compatibilité vers [EngoGlassesDisplayService] suite au découpage
/// en 3 services BLE dédiés et testables unitairement :
/// - [EngoGlassesDisplayService] (`engo_glasses_display_service.dart`)
/// - [BleHeartRateSensor] (`ble_heart_rate_sensor.dart`)
/// - [BleCadenceSpeedSensor] (`ble_cadence_speed_sensor.dart`)
typedef BleTelemetryService = EngoGlassesDisplayService;
