import 'package:flutter/material.dart';

/// Representation of the 5 standard athletic cardiovascular training zones (Z1-Z5).
enum HeartRateZoneLevel {
  z1, // Active Recovery / Warmup (<60%)
  z2, // Aerobic / Endurance (60-70%)
  z3, // Tempo / Steady state (70-80%)
  z4, // Threshold (80-90%)
  z5, // VO2 Max / Anaerobic (>=90%)
}

class HeartRateZone {
  final HeartRateZoneLevel level;
  final String code;
  final String name;
  final Color color;
  final double minPercent;
  final double maxPercent;

  const HeartRateZone._({
    required this.level,
    required this.code,
    required this.name,
    required this.color,
    required this.minPercent,
    required this.maxPercent,
  });

  /// Zone 1 - Récupération / Échauffement (< 60% FCmax)
  static const z1 = HeartRateZone._(
    level: HeartRateZoneLevel.z1,
    code: 'Z1',
    name: 'Récupération',
    color: Color(0xFF38BDF8), // Cyan / Sky Blue
    minPercent: 0.0,
    maxPercent: 0.60,
  );

  /// Zone 2 - Endurance fondamentale (60% - 70% FCmax)
  static const z2 = HeartRateZone._(
    level: HeartRateZoneLevel.z2,
    code: 'Z2',
    name: 'Endurance',
    color: Color(0xFF10B981), // Emerald Green
    minPercent: 0.60,
    maxPercent: 0.70,
  );

  /// Zone 3 - Tempo / Aérobie soutenu (70% - 80% FCmax)
  static const z3 = HeartRateZone._(
    level: HeartRateZoneLevel.z3,
    code: 'Z3',
    name: 'Tempo',
    color: Color(0xFFF59E0B), // Amber / Gold
    minPercent: 0.70,
    maxPercent: 0.80,
  );

  /// Zone 4 - Seuil anaérobie (80% - 90% FCmax)
  static const z4 = HeartRateZone._(
    level: HeartRateZoneLevel.z4,
    code: 'Z4',
    name: 'Seuil',
    color: Color(0xFFF97316), // Vivid Orange
    minPercent: 0.80,
    maxPercent: 0.90,
  );

  /// Zone 5 - VO2 Max / Vitesse maximale (>= 90% FCmax)
  static const z5 = HeartRateZone._(
    level: HeartRateZoneLevel.z5,
    code: 'Z5',
    name: 'VO2 Max',
    color: Color(0xFFEF4444), // Crimson Red
    minPercent: 0.90,
    maxPercent: 1.0,
  );

  static const List<HeartRateZone> allZones = [z1, z2, z3, z4, z5];

  /// Computes the active cardiovascular zone based on instantaneous bpm.
  /// Standard default [maxHr] is 190 bpm if not personalized.
  static HeartRateZone fromBpm(int bpm, {int maxHr = 190}) {
    if (bpm <= 0) return z1;
    final ratio = bpm / (maxHr > 0 ? maxHr : 190);

    if (ratio < 0.60) return z1;
    if (ratio < 0.70) return z2;
    if (ratio < 0.80) return z3;
    if (ratio < 0.90) return z4;
    return z5;
  }
}
