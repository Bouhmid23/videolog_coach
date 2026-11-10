import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service gérant la détection du déclencheur Bluetooth (stick K28 / télécommande selfie).
///
/// Intercepte les touches multimédia / volume via les canaux natifs Android
/// en évitant l'affichage de la jauge de volume système.
class RemoteShutterService {
  RemoteShutterService._();
  static final RemoteShutterService instance = RemoteShutterService._();

  static const MethodChannel _controlChannel =
      MethodChannel('videolog/remote_shutter_control');
  static const EventChannel _streamChannel =
      EventChannel('videolog/remote_shutter_stream');

  final StreamController<void> _shutterController =
      StreamController<void>.broadcast();
  StreamSubscription<dynamic>? _subscription;

  DateTime? _lastTriggerTime;
  static const Duration _debounceDuration = Duration(milliseconds: 700);

  bool _isEnabled = false;
  bool get isEnabled => _isEnabled;

  /// Flux émettant un événement à chaque appui valide sur le déclencheur.
  Stream<void> get onShutterPressed => _shutterController.stream;

  /// Active l'interception native des touches de déclenchement.
  Future<void> enable() async {
    if (_isEnabled) return;
    _isEnabled = true;

    _subscription?.cancel();
    _subscription = _streamChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        _handleRawTrigger();
      },
      onError: (dynamic error) {
        debugPrint('[RemoteShutter] Erreur flux: $error');
      },
    );

    try {
      await _controlChannel.invokeMethod<bool>('setIntercept', <String, dynamic>{
        'enabled': true,
      });
      debugPrint('[RemoteShutter] Interception activée');
    } catch (e) {
      debugPrint('[RemoteShutter] Impossible d\'activer l\'interception: $e');
    }
  }

  /// Désactive l'interception pour restaurer le comportement normal des touches du smartphone.
  Future<void> disable() async {
    if (!_isEnabled) return;
    _isEnabled = false;

    await _subscription?.cancel();
    _subscription = null;

    try {
      await _controlChannel.invokeMethod<bool>('setIntercept', <String, dynamic>{
        'enabled': false,
      });
      debugPrint('[RemoteShutter] Interception désactivée');
    } catch (e) {
      debugPrint('[RemoteShutter] Erreur désactivation interception: $e');
    }
  }

  void _handleRawTrigger() {
    final now = DateTime.now();
    if (_lastTriggerTime != null &&
        now.difference(_lastTriggerTime!) < _debounceDuration) {
      debugPrint('[RemoteShutter] Clic ignoré (anti-rebond)');
      return;
    }
    _lastTriggerTime = now;
    debugPrint('[RemoteShutter] Clic déclencheur détecté');
    _shutterController.add(null);
  }
}
