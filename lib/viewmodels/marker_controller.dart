import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/ball_marker.dart';

/// Stocke les ballons reçus du coach et gère leur expiration.
///
/// Les expirations reposent sur l'horloge du mobile : [BallMarker.ttl] est
/// compté à partir de la réception, jamais depuis le `ts` du coach.
class MarkerController {
  /// Nombre maximum de ballons affichés simultanément.
  static const int maxMarkers = 5;

  final ValueNotifier<List<BallMarker>> _notifier =
      ValueNotifier<List<BallMarker>>(const []);

  final Map<String, Timer> _timers = {};

  /// Listenable à transmettre aux overlays.
  ValueListenable<List<BallMarker>> get listenable => _notifier;

  List<BallMarker> get markers => _notifier.value;

  bool get isEmpty => _notifier.value.isEmpty;

  /// Ajoute un ballon et programme son retrait.
  ///
  /// Un message dont l'identifiant est déjà affiché remplace l'ancien
  /// (le coach peut suivre un mouvement en renvoyant le même `id`).
  void add(BallMarker marker) {
    _timers.remove(marker.id)?.cancel();

    final next = <BallMarker>[
      for (final existing in _notifier.value)
        if (existing.id != marker.id) existing,
      marker,
    ];

    // Cap : on supprime les plus anciens.
    while (next.length > maxMarkers) {
      final removed = next.removeAt(0);
      _timers.remove(removed.id)?.cancel();
    }

    _notifier.value = List<BallMarker>.unmodifiable(next);
    _timers[marker.id] = Timer(marker.ttl, () => remove(marker.id));
  }

  void remove(String id) {
    _timers.remove(id)?.cancel();
    if (!_notifier.value.any((marker) => marker.id == id)) return;
    _notifier.value = List<BallMarker>.unmodifiable(
      _notifier.value.where((marker) => marker.id != id),
    );
  }

  void clear() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    if (_notifier.value.isNotEmpty) {
      _notifier.value = const <BallMarker>[];
    }
  }

  void dispose() {
    clear();
    _notifier.dispose();
  }
}
