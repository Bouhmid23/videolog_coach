import 'dart:async';
import 'package:flutter/services.dart';

/// Service centralisé de feedbacks haptiques sportifs et micro-interactions immersives.
class AthleticHaptics {
  const AthleticHaptics._();

  /// Haptique de seuil : Vibration marquée (rythmique) lors du passage
  /// en Zone Cardiaque 5 (Zone Rouge / Anaérobie).
  static Future<void> thresholdZone5Alert() async {
    try {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 130));
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 130));
      await HapticFeedback.heavyImpact();
    } catch (_) {
      // Les plateformes sans moteur haptique continuent sans planter.
    }
  }

  /// Haptique de coaching : Double impulsion discrète lors de la réception
  /// d'un marqueur coach ("ballon") ou d'une correction posturale.
  static Future<void> coachingDoublePulse() async {
    try {
      await HapticFeedback.lightImpact();
      await Future<void>.delayed(const Duration(milliseconds: 110));
      await HapticFeedback.lightImpact();
    } catch (_) {
      // Continuer sans crash
    }
  }

  /// Feedback lors du verrouillage / déverrouillage de l'écran (Sweat Lock).
  static Future<void> sweatLockToggled({required bool locked}) async {
    try {
      if (locked) {
        await HapticFeedback.mediumImpact();
      } else {
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await HapticFeedback.lightImpact();
      }
    } catch (_) {}
  }

  /// Feedback lors du basculement du mode plein soleil (Outdoor Sun Mode).
  static Future<void> outdoorModeToggled({required bool active}) async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Feedback tactile direct lors du balayage horizontal pour changer de participant.
  static Future<void> participantSwitched() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// Feedback lors du double-tap pour couper / activer le micro.
  static Future<void> micToggled({required bool muted}) async {
    try {
      if (muted) {
        await HapticFeedback.mediumImpact();
      } else {
        await HapticFeedback.lightImpact();
        await Future<void>.delayed(const Duration(milliseconds: 90));
        await HapticFeedback.lightImpact();
      }
    } catch (_) {}
  }
}
