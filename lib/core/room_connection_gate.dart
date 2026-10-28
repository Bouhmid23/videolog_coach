import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import 'single_flight.dart';

/// Sérialise le cycle de vie des Room LiveKit.
///
/// Règle : **une seule connexion à la fois**. Toute nouvelle tentative attend
/// la fin de la précédente, puis détruit (`disconnect()` + `dispose()`) la
/// Room encore vivante avant d'en créer une autre. Sans cette sérialisation,
/// deux Room peuvent se disputer le moteur natif (audio, caméra, peer
/// connection) et le SDK part en boucle « reconnecting ».
class RoomConnectionGate {
  RoomConnectionGate._();

  static final RoomConnectionGate instance = RoomConnectionGate._();

  final SingleFlight _flight = SingleFlight();

  /// File des destructions en cours : une nouvelle connexion attend aussi la
  /// fin d'un `dispose()` lancé en arrière-plan (fin de route, par exemple).
  Future<void> _teardownTail = Future<void>.value();

  Room? _tracked;

  /// Délai maximal accordé à `disconnect()` et `dispose()` lors d'un abandon.
  /// Au-delà, on détruit quand même : on ne reste pas bloqué sur une Room en
  /// reconnexion.
  static const Duration teardownTimeout = Duration(seconds: 5);

  /// Room actuellement possédée par l'app (appel en cours compris), ou null.
  Room? get trackedRoom => _tracked;

  /// Vrai pendant une tentative de connexion.
  bool get isConnecting => _flight.isBusy;

  /// Exécute une tentative de connexion de façon exclusive.
  ///
  /// Avant de lancer [attempt], détruit la Room précédente si elle existe
  /// encore (cas d'une déconnexion ou d'une reconnexion non terminée).
  Future<T> run<T>(Future<T> Function() attempt) {
    return _flight.run(() async {
      // Une destruction peut avoir été lancée en arrière-plan (déconnexion,
      // fin de route) : on attend qu'elle soit finie avant de reconnecter.
      await _teardownTail;

      final stale = _tracked;
      _tracked = null;
      if (stale != null) {
        debugPrint(
          '🧹 Room précédente encore vivante '
          '(état=${stale.connectionState.name}) → destruction avant reconnexion',
        );
        await destroy(stale);
      }
      return attempt();
    });
  }

  /// Déclare [room] comme Room courante. Elle sera détruite avant toute
  /// nouvelle connexion et par [forceStop].
  void track(Room room) => _tracked = room;

  /// La Room n'est plus possédée par l'app (elle vient d'être détruite).
  void untrack(Room room) {
    if (identical(_tracked, room)) _tracked = null;
  }

  /// `disconnect()` puis `dispose()`, avec délais maximaux.
  ///
  /// `Room.dispose()` est idempotent côté SDK : un double appel est sans
  /// effet, on peut donc l'utiliser aussi bien pour le bouton « Quitter » que
  /// pour le nettoyage de fin de route. Les destructions sont sérialisées :
  /// une nouvelle connexion attend la fin de celle qui est en cours.
  Future<void> destroy(Room room) {
    final next = _teardownTail.then((_) => _teardown(room));
    _teardownTail = next.catchError((Object _) {});
    return next;
  }

  Future<void> _teardown(Room room) async {
    if (room.isDisposed) return;

    debugPrint('🧹 Room.disconnect() (état=${room.connectionState.name})');
    try {
      await room.disconnect().timeout(teardownTimeout);
    } on TimeoutException {
      debugPrint(
        '⚠️ disconnect() bloqué > ${teardownTimeout.inSeconds} s — '
        'destruction forcée',
      );
    } catch (error) {
      debugPrint('⚠️ disconnect() erreur: $error');
    }

    try {
      await room.dispose().timeout(teardownTimeout);
      debugPrint('🧹 Room disposée');
    } on TimeoutException {
      debugPrint(
        '⚠️ dispose() bloqué > ${teardownTimeout.inSeconds} s — abandon',
      );
    } catch (error) {
      debugPrint('⚠️ dispose() erreur: $error');
    }
  }
}
