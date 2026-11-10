import 'package:flutter/services.dart';

/// Petit bip court sur le téléphone, à l'arrivée d'un message du coach pour les lunettes.
///
/// Android : `ToneGenerator` (flux notification, 120 ms), via `MainActivity` : respecte le
/// volume des notifications du téléphone (silencieux si coupé).
/// Autres plateformes (iOS) : son de clic du système et léger retour haptique.
class BeepService {
  static const MethodChannel _channel = MethodChannel('videolog/beep');

  /// Bip simple (début d'enregistrement, message coach).
  static Future<void> beep() async {
    try {
      await _channel.invokeMethod<bool>('beep');
    } on MissingPluginException {
      try {
        await SystemSound.play(SystemSoundType.click);
        await HapticFeedback.lightImpact();
      } catch (_) {
        // Pas de son disponible : le message reste affiché sur les lunettes.
      }
    } catch (_) {
      // Un bip manqué ne doit jamais gêner l'affichage.
    }
  }

  /// Double bip (arrêt d'enregistrement).
  static Future<void> doubleBeep() async {
    try {
      await _channel.invokeMethod<bool>('doubleBeep');
    } on MissingPluginException {
      try {
        await SystemSound.play(SystemSoundType.click);
        await HapticFeedback.mediumImpact();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await SystemSound.play(SystemSoundType.click);
        await HapticFeedback.mediumImpact();
      } catch (_) {
        // Pas de son disponible.
      }
    } catch (_) {
      // Un bip manqué ne doit jamais bloquer l'action.
    }
  }
}
