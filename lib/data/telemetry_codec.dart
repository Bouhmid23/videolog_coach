import 'dart:typed_data';

import 'remote_telemetry.dart';

/// Encodage binaire compact du flux de télémétrie (topic LiveKit `telemetry`).
///
/// Format v2, big-endian :
/// - 1 octet : version (0x02)
/// - 1 octet : code du rôle (0=coach, 1=trainee, 2=other)
/// - 2 octets : vitesse (uint16, km/h × 100, 65535=null)
/// - 1 octet : fréquence cardiaque (uint8, 0-255 bpm, 255=null)
/// - 1 octet : cadence (uint8, 0-255 rpm, 255=null)
/// - 4 octets : latitude (int32, degrés × 10^7, 0x7FFFFFFF=null)
/// - 4 octets : longitude (int32, degrés × 10^7, 0x7FFFFFFF=null)
/// - 2 octets : altitude (int16, cm, 0x7FFF=null)
/// - 1 octet : bearing/cap (uint8, degrés 0-254, 255=null)
/// - 4 octets : timestamp (uint32, epoch ms)
///
/// Taille totale : 21 octets (fixe)
class TelemetryCodec {
  TelemetryCodec._();

  static const int version = 2;
  static const int packetSize = 21;

  /// Valeurs null pour les champs optionnels
  static const int nullUint16 = 65535;
  static const int nullUint8 = 255;
  static const int nullInt32 = 0x7FFFFFFF;
  static const int nullInt16 = 0x7FFF; // 32767

  /// Encodage binaire d'un paquet de télémétrie.
  static Uint8List encode({
    required String role,
    required double? speed,
    required double? heartRate,
    required double? cadence,
    required double? lat,
    required double? lng,
    required double? altitude,
    required double? bearing,
    required int timestampMs,
  }) {
    final data = Uint8List(packetSize);
    final bd = ByteData.sublistView(data);
    var o = 0;

    // Version
    data[o++] = version;

    // Role
    data[o++] = _roleToCode(role);

    // Speed: km/h × 100 ; 65535 est réservé à null.
    final speedKmhTimes100 = speed != null ? (speed * 100).round() : nullUint16;
    bd.setUint16(o, speedKmhTimes100.clamp(0, nullUint16), Endian.big);
    o += 2;

    // Heart rate: uint8 (0-255 bpm)
    final hr = heartRate != null ? heartRate.round() : nullUint8;
    data[o++] = hr.clamp(0, nullUint8);

    // Cadence: uint8 (0-255 rpm)
    final cad = cadence != null ? cadence.round() : nullUint8;
    data[o++] = cad.clamp(0, nullUint8);

    // Latitude: degrés × 10^7 (sept décimales).
    final latScaled = lat != null ? (lat * 10000000).round() : nullInt32;
    bd.setInt32(o, latScaled.clamp(-nullInt32, nullInt32), Endian.big);
    o += 4;

    // Longitude: degrés × 10^7 (sept décimales).
    final lngScaled = lng != null ? (lng * 10000000).round() : nullInt32;
    bd.setInt32(o, lngScaled.clamp(-nullInt32, nullInt32), Endian.big);
    o += 4;

    // Altitude: int16 en cm (2 décimales en mètres)
    final altitudeCm = altitude != null ? (altitude * 100).round() : nullInt16;
    bd.setInt16(o, altitudeCm.clamp(-nullInt16, nullInt16), Endian.big);
    o += 2;

    // Bearing: 255 est réservé à null ; seuls 0..254 sont représentables.
    final bearingVal = bearing != null && bearing >= 0 && bearing <= 254
        ? bearing.round()
        : nullUint8;
    data[o++] = bearingVal.clamp(0, nullUint8);

    // Timestamp: uint32
    bd.setUint32(o, timestampMs & 0xFFFFFFFF, Endian.big);

    return data;
  }

  /// Décodage binaire d'un paquet de télémétrie.
  /// Renvoie `null` si le paquet est invalide.
  static RemoteTelemetry? decode(
    List<int> raw, {
    DateTime? receivedAt,
  }) {
    if (raw.length != packetSize) return null;

    final data = raw is Uint8List ? raw : Uint8List.fromList(raw);
    final bd = ByteData.sublistView(data);

    // Version
    final packetVersion = data[0];
    if (packetVersion != version) return null;

    // Role
    final roleCode = data[1];
    final role = _codeToRole(roleCode);
    if (role == null) return null;

    // Speed
    final speedRaw = bd.getUint16(2, Endian.big);
    final speed = speedRaw == nullUint16 ? null : speedRaw / 100.0;

    // Heart rate
    final heartRateRaw = data[4];
    final heartRate = heartRateRaw == nullUint8 ? null : heartRateRaw.toDouble();

    // Cadence
    final cadenceRaw = data[5];
    final cadence = cadenceRaw == nullUint8 ? null : cadenceRaw.toDouble();

    // Latitude
    final latRaw = bd.getInt32(6, Endian.big);
    final lat = latRaw == nullInt32 ? null : latRaw / 10000000.0;

    // Longitude
    final lngRaw = bd.getInt32(10, Endian.big);
    final lng = lngRaw == nullInt32 ? null : lngRaw / 10000000.0;

    // Altitude (cm)
    final altitudeRaw = bd.getInt16(14, Endian.big);
    final altitude = altitudeRaw == nullInt16 ? null : altitudeRaw / 100.0;

    // Bearing (degrees)
    final bearingRaw = data[16];
    final bearing = bearingRaw == nullUint8 ? null : bearingRaw.toDouble();

    // Timestamp
    final timestampMs = bd.getUint32(17, Endian.big);

    return RemoteTelemetry(
      heartRate: heartRate?.round(),
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
