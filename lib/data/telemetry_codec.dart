import 'dart:typed_data';

import 'remote_telemetry.dart';

/// Encodage binaire compact du flux de télémétrie (topic LiveKit `telemetry`).
///
/// Format v3 (25 octets, big-endian) :
/// - 0..0   (1) : version (`3`)
/// - 1..1   (1) : code du rôle (`0=coach`, `1=trainee`, `2=observer`)
/// - 2..3   (2) : vitesse (`uint16`, km/h × 100, `65535`=null)
/// - 4..4   (1) : fréquence cardiaque (`uint8`, 0–254 bpm, `255`=null)
/// - 5..5   (1) : cadence (`uint8`, 0–254 rpm, `255`=null)
/// - 6..9   (4) : latitude (`int32`, degrés × 10^7, `0x7FFFFFFF`=null)
/// - 10..13 (4) : longitude (`int32`, degrés × 10^7, `0x7FFFFFFF`=null)
/// - 14..15 (2) : altitude (`int16`, m × 100, `0x7FFF`=null)
/// - 16..17 (2) : bearing (`uint16`, 0..359°, `65535`=null)
/// - 18..19 (2) : puissance (`uint16`, W, `65535`=null)
/// - 20..23 (4) : timestamp (`uint32`, Unix ms mod 2^32)
/// - 24..24 (1) : flags (`uint8`, `0`)
///
/// Le décodeur reste rétrocompatible avec la v2 (21 octets).
class TelemetryCodec {
  TelemetryCodec._();

  static const int version = 3;
  static const int packetSize = 25;

  static const int v2Version = 2;
  static const int v2PacketSize = 21;

  /// Valeurs null pour les champs optionnels
  static const int nullUint16 = 65535;
  static const int nullUint8 = 255;
  static const int nullInt32 = 0x7FFFFFFF;
  static const int nullInt16 = 0x7FFF; // 32767

  /// Encodage binaire v3 (25 octets) d'un paquet de télémétrie.
  static Uint8List encode({
    required String role,
    required double? speed,
    required double? heartRate,
    required double? cadence,
    required double? lat,
    required double? lng,
    required double? altitude,
    required double? bearing,
    int? powerWatts,
    required int timestampMs,
    int flags = 0,
  }) {
    final data = Uint8List(packetSize);
    final bd = ByteData.sublistView(data);

    // 0: version (3)
    bd.setUint8(0, version);

    // 1: role
    bd.setUint8(1, _roleToCode(role));

    // 2..3: speed (km/h × 100 ; 65535 = null)
    final speedScaled =
        (speed != null && !speed.isNaN && !speed.isInfinite && speed >= 0)
        ? (speed * 100).round().clamp(0, nullUint16 - 1)
        : nullUint16;
    bd.setUint16(2, speedScaled, Endian.big);

    // 4: heart rate (0..254 bpm ; 255 = null)
    final hrVal =
        (heartRate != null &&
            !heartRate.isNaN &&
            !heartRate.isInfinite &&
            heartRate >= 0)
        ? heartRate.round().clamp(0, nullUint8 - 1)
        : nullUint8;
    bd.setUint8(4, hrVal);

    // 5: cadence (0..254 rpm ; 255 = null)
    final cadVal =
        (cadence != null &&
            !cadence.isNaN &&
            !cadence.isInfinite &&
            cadence >= 0)
        ? cadence.round().clamp(0, nullUint8 - 1)
        : nullUint8;
    bd.setUint8(5, cadVal);

    // 6..9: latitude (deg × 10^7)
    final latScaled = (lat != null && !lat.isNaN && !lat.isInfinite)
        ? (lat * 10000000).round().clamp(-nullInt32, nullInt32 - 1)
        : nullInt32;
    bd.setInt32(6, latScaled, Endian.big);

    // 10..13: longitude (deg × 10^7)
    final lngScaled = (lng != null && !lng.isNaN && !lng.isInfinite)
        ? (lng * 10000000).round().clamp(-nullInt32, nullInt32 - 1)
        : nullInt32;
    bd.setInt32(10, lngScaled, Endian.big);

    // 14..15: altitude (m × 100)
    final altitudeScaled =
        (altitude != null && !altitude.isNaN && !altitude.isInfinite)
        ? (altitude * 100).round().clamp(-32768, nullInt16 - 1)
        : nullInt16;
    bd.setInt16(14, altitudeScaled, Endian.big);

    // 16..17: bearing (0..359° ; 65535 = null)
    final bearingVal =
        (bearing != null &&
            !bearing.isNaN &&
            !bearing.isInfinite &&
            bearing >= 0 &&
            bearing <= 360)
        ? (bearing.round() % 360)
        : nullUint16;
    bd.setUint16(16, bearingVal, Endian.big);

    // 18..19: power (W ; 65535 = null)
    final powerVal = (powerWatts != null && powerWatts >= 0)
        ? powerWatts.clamp(0, nullUint16 - 1)
        : nullUint16;
    bd.setUint16(18, powerVal, Endian.big);

    // 20..23: timestamp (Unix ms mod 2^32)
    bd.setUint32(20, timestampMs & 0xFFFFFFFF, Endian.big);

    // 24: flags
    bd.setUint8(24, flags & 0xFF);

    return data;
  }

  /// Décodage binaire d'un paquet de télémétrie (v3 25 octets ou v2 21 octets).
  /// Renvoie `null` si le paquet est invalide.
  static RemoteTelemetry? decode(
    List<int> raw, {
    DateTime? receivedAt,
  }) {
    if (raw.isEmpty) return null;

    final data = raw is Uint8List ? raw : Uint8List.fromList(raw);
    final packetVersion = data[0];

    if (packetVersion == version && data.length == packetSize) {
      return _decodeV3(data, receivedAt: receivedAt);
    }
    if (packetVersion == v2Version && data.length == v2PacketSize) {
      return _decodeV2(data, receivedAt: receivedAt);
    }
    return null;
  }

  static RemoteTelemetry? _decodeV3(
    Uint8List data, {
    DateTime? receivedAt,
  }) {
    final bd = ByteData.sublistView(data);
    final role = _codeToRole(bd.getUint8(1));
    if (role == null) return null;

    final speedRaw = bd.getUint16(2, Endian.big);
    final speed = speedRaw == nullUint16 ? null : speedRaw / 100.0;

    final hrRaw = bd.getUint8(4);
    final heartRate = hrRaw == nullUint8 ? null : hrRaw;

    final cadRaw = bd.getUint8(5);
    final cadence = cadRaw == nullUint8 ? null : cadRaw.toDouble();

    final latRaw = bd.getInt32(6, Endian.big);
    final lat = latRaw == nullInt32 ? null : latRaw / 10000000.0;

    final lngRaw = bd.getInt32(10, Endian.big);
    final lng = lngRaw == nullInt32 ? null : lngRaw / 10000000.0;

    final altRaw = bd.getInt16(14, Endian.big);
    final altitude = altRaw == nullInt16 ? null : altRaw / 100.0;

    final bearingRaw = bd.getUint16(16, Endian.big);
    final bearing =
        (bearingRaw == nullUint16 || bearingRaw > 359) ? null : bearingRaw.toDouble();

    final powerRaw = bd.getUint16(18, Endian.big);
    final powerWatts = powerRaw == nullUint16 ? null : powerRaw;

    final timestampMs = bd.getUint32(20, Endian.big);

    return RemoteTelemetry(
      heartRate: heartRate,
      cadence: cadence,
      speed: speed,
      lat: lat,
      lng: lng,
      altitude: altitude,
      bearing: bearing,
      powerWatts: powerWatts,
      role: role,
      receivedAt: receivedAt ?? DateTime.fromMillisecondsSinceEpoch(timestampMs),
    );
  }

  static RemoteTelemetry? _decodeV2(
    Uint8List data, {
    DateTime? receivedAt,
  }) {
    final bd = ByteData.sublistView(data);
    final role = _codeToRole(data[1]);
    if (role == null) return null;

    final speedRaw = bd.getUint16(2, Endian.big);
    final speed = speedRaw == nullUint16 ? null : speedRaw / 100.0;

    final heartRateRaw = data[4];
    final heartRate = heartRateRaw == nullUint8 ? null : heartRateRaw;

    final cadenceRaw = data[5];
    final cadence = cadenceRaw == nullUint8 ? null : cadenceRaw.toDouble();

    final latRaw = bd.getInt32(6, Endian.big);
    final lat = latRaw == nullInt32 ? null : latRaw / 10000000.0;

    final lngRaw = bd.getInt32(10, Endian.big);
    final lng = lngRaw == nullInt32 ? null : lngRaw / 10000000.0;

    final altitudeRaw = bd.getInt16(14, Endian.big);
    final altitude = altitudeRaw == nullInt16 ? null : altitudeRaw / 100.0;

    final bearingRaw = data[16];
    final bearing = bearingRaw == nullUint8 ? null : bearingRaw.toDouble();

    final timestampMs = bd.getUint32(17, Endian.big);

    return RemoteTelemetry(
      heartRate: heartRate,
      cadence: cadence,
      speed: speed,
      lat: lat,
      lng: lng,
      altitude: altitude,
      bearing: bearing,
      role: role,
      receivedAt: receivedAt ?? DateTime.fromMillisecondsSinceEpoch(timestampMs),
    );
  }

  /// Convertit un rôle en code (1 octet).
  static int _roleToCode(String role) {
    switch (role.toLowerCase()) {
      case 'coach':
        return 0;
      case 'trainee':
        return 1;
      default:
        return 2;
    }
  }

  /// Convertit un code en rôle.
  static String? _codeToRole(int code) {
    switch (code) {
      case 0:
        return 'coach';
      case 1:
        return 'trainee';
      case 2:
        return 'observer';
      default:
        return null;
    }
  }
}
