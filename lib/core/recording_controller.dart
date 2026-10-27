import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/recording_state.dart';
import 'api_service.dart';
import 'auth_service.dart';

/// Pilote l'enregistrement Egress d'une room et rafraîchit son état.
///
/// Le serveur impose une durée maximale (180 s par défaut) : on continue donc
/// à interroger `GET /mobile/rooms/{room}/recording` pendant tout
/// l'enregistrement pour refléter l'arrêt automatique.
class RecordingController extends ChangeNotifier {
  RecordingController({
    required this.roomName,
    required this.canControl,
    this.pollInterval = const Duration(seconds: 4),
  });

  final String roomName;
  final bool canControl;
  final Duration pollInterval;

  RecordingState? state;
  bool loading = false;
  String? error;
  String layout = 'grid';

  Timer? _pollTimer;
  bool _requestInFlight = false;
  bool _disposed = false;

  bool get canStart =>
      canControl &&
      !loading &&
      (state == null ? false : state!.canStart);

  bool get canStop => canControl && !loading && (state?.canStop ?? false);

  bool get isPending => state?.isPending ?? false;

  bool get isRecording => state?.isActive ?? false;

  Future<void> load({bool silent = false}) async {
    if (_disposed || _requestInFlight) return;
    _requestInFlight = true;
    if (!silent) {
      loading = true;
      error = null;
      _notify();
    }

    try {
      final next = await ApiService.getRecording(roomName);
      state = next;
      error = null;
    } on ApiException catch (exception) {
      error = exception.message;
      if (exception.isUnauthorized) {
        await AuthService.instance.signOut();
      }
    } catch (_) {
      error = 'Impossible de récupérer l\'état de l\'enregistrement.';
    } finally {
      _requestInFlight = false;
      if (!silent) loading = false;
      _syncPolling();
      _notify();
    }
  }

  Future<void> start() => startWithLayout(layout);

  Future<void> startWithLayout(String selectedLayout) async {
    if (!canControl || loading) return;
    layout = selectedLayout;
    await _run(() => ApiService.startRecording(roomName, layout: selectedLayout));
  }

  Future<void> stop() async {
    if (!canControl || loading) return;
    await _run(() => ApiService.stopRecording(roomName));
  }

  Future<void> _run(Future<RecordingState> Function() action) async {
    loading = true;
    error = null;
    _notify();

    var refreshAfterError = false;
    try {
      state = await action();
    } on ApiException catch (exception) {
      error = exception.message;
      refreshAfterError = exception.isConflict;
      if (exception.isUnauthorized) {
        await AuthService.instance.signOut();
      }
    } catch (_) {
      error = 'Opération d\'enregistrement impossible.';
    } finally {
      loading = false;
      _syncPolling();
      _notify();
    }

    if (refreshAfterError && !_disposed) {
      await load(silent: true);
    }
  }

  void _syncPolling() {
    final shouldPoll = (state?.isPending ?? false) || (state?.isActive ?? false);
    if (shouldPoll) {
      _pollTimer ??= Timer.periodic(
        pollInterval,
        (_) => unawaited(load(silent: true)),
      );
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    super.dispose();
  }
}
