import 'dart:async';

/// Exécute au plus une opération à la fois, dans l'ordre d'arrivée.
///
/// Utilisé pour le cycle de vie des Room LiveKit : une nouvelle tentative de
/// connexion attend la fin (et le `disconnect()`) de la précédente, au lieu
/// de s'exécuter en parallèle.
class SingleFlight {
  Future<void> _tail = Future<void>.value();
  bool _busy = false;

  /// Vrai pendant l'exécution de l'opération courante.
  bool get isBusy => _busy;

  /// Exécute [action] après la fin de l'opération précédente.
  ///
  /// L'erreur éventuelle de [action] remonte à l'appelant sans bloquer la
  /// file : l'opération suivante s'exécute normalement.
  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;

    return () async {
      await previous;
      _busy = true;
      try {
        return await action();
      } finally {
        _busy = false;
        done.complete();
      }
    }();
  }
}
