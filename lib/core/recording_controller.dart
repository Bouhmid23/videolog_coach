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
  }) {
    debugPrint(
      '[Recording] contrôleur créé room=$roomName canControl=$canControl '
      'poll=${pollInterval.inSeconds}s',
    );
  }

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
      canControl && !loading && (state == null ? false : state!.canStart);

  bool get canStop => canControl && !loading && (state?.canStop ?? false);

  bool get isPending => state?.isPending ?? false;

  bool get isRecording => state?.isActive ?? false;

  /// Raison lisible quand [canStart] est faux, utile pour l'UI et les logs.
  String? get startBlockReason {
    if (!canControl) {
      return 'Votre compte ne peut pas piloter l\'enregistrement de cette session.';
    }
    if (loading) return 'Une opération d\'enregistrement est déjà en cours.';
    if (state == null) {
      return 'L\'état de l\'enregistrement est indisponible. Réessayez.';
    }
    if (!state!.canStart) {
      return 'L\'enregistrement ne peut pas démarrer (${state!.label}).';
    }
    return null;
  }

  /// Raison lisible quand [canStop] est faux.
  String? get stopBlockReason {
    if (!canControl) {
      return 'Votre compte ne peut pas piloter l\'enregistrement de cette session.';
    }
    if (loading) return 'Une opération d\'enregistrement est déjà en cours.';
    if (state == null) {
      return 'L\'état de l\'enregistrement est indisponible. Réessayez.';
    }
    if (!state!.canStop) {
      return 'Aucun enregistrement actif à arrêter (${state!.label}).';
    }
    return null;
  }

  Future<void> load({bool silent = false}) async {
    if (_disposed || _requestInFlight) {
      debugPrint(
        '[Recording] load ignoré room=$roomName '
        'disposed=$_disposed inFlight=$_requestInFlight',
      );
      return;
    }
    _requestInFlight = true;
    if (!silent) {
      loading = true;
      error = null;
      _notify();
    }
    debugPrint(
      '[Recording] load room=$roomName canControl=$canControl silent=$silent',
    );

    try {
      final next = await ApiService.getRecording(roomName);
      state = next;
      error = null;
      debugPrint(
        '[Recording] load OK room=$roomName status=${next.rawStatus} '
        'normalized=${next.status} egress=${next.egressId}',
      );
    } on ApiException catch (exception, stack) {
      error = _errorMessage(exception);
      debugPrint(
        '[Recording] load FAILED room=$roomName HTTP=${exception.statusCode} '
        'message=${exception.message} detail=${exception.detail}',
      );
      debugPrintStack(stackTrace: stack);
      if (exception.isUnauthorized) {
        await AuthService.instance.signOut();
      }
    } catch (err, stack) {
      error = 'Impossible de récupérer l\'état de l\'enregistrement.';
      debugPrint('[Recording] load FAILED room=$roomName error=$err');
      debugPrintStack(stackTrace: stack);
    } finally {
      _requestInFlight = false;
      if (!silent) loading = false;
      _syncPolling();
      _notify();
    }
  }

  Future<bool> start() => startWithLayout(layout);

  Future<bool> startWithLayout(String selectedLayout) async {
    if (!canStart) {
      debugPrint(
        '[Recording] start BLOQUÉ room=$roomName layout=$selectedLayout '
        'canControl=$canControl loading=$loading '
        'status=${state?.rawStatus} reason=${startBlockReason ?? 'inconnue'}',
      );
      return false;
    }
    layout = selectedLayout;
    debugPrint('[Recording] start room=$roomName layout=$selectedLayout');
    return _run(
      'start',
      () => ApiService.startRecording(roomName, layout: selectedLayout),
    );
  }

  Future<bool> stop() async {
    if (!canStop) {
      debugPrint(
        '[Recording] stop BLOQUÉ room=$roomName '
        'canControl=$canControl loading=$loading '
        'status=${state?.rawStatus} reason=${stopBlockReason ?? 'inconnue'}',
      );
      return false;
    }
    debugPrint('[Recording] stop room=$roomName');
    return _run('stop', () => ApiService.stopRecording(roomName));
  }

  Future<bool> _run(
    String operation,
    Future<RecordingState> Function() action,
  ) async {
    loading = true;
    error = null;
    _notify();

    var success = false;
    var refreshAfterError = false;
    try {
      final result = await action();
      state = result;
      success = true;
      debugPrint(
        '[Recording] $operation OK room=$roomName '
        'status=${result.rawStatus} normalized=${result.status} '
        'egress=${result.egressId} error=${result.error}',
      );
    } on ApiException catch (exception, stack) {
      error = _errorMessage(exception);
      refreshAfterError = exception.isConflict;
      debugPrint(
        '[Recording] $operation FAILED room=$roomName '
        'HTTP=${exception.statusCode} message=${exception.message} '
        'detail=${exception.detail}',
      );
      debugPrintStack(stackTrace: stack);
      if (exception.isUnauthorized) {
        await AuthService.instance.signOut();
      }
    } catch (err, stack) {
      error = 'Opération d\'enregistrement impossible.';
      debugPrint('[Recording] $operation FAILED room=$roomName error=$err');
      debugPrintStack(stackTrace: stack);
    } finally {
      loading = false;
      _syncPolling();
      _notify();
    }

    if (refreshAfterError && !_disposed) {
      await load(silent: true);
    }
    return success;
  }

  String _errorMessage(ApiException exception) {
    if (exception.isForbidden) {
      return 'Votre compte ne peut pas piloter l\'enregistrement de cette session.';
    }
    return exception.message;
  }

  void _syncPolling() {
    final shouldPoll =
        (state?.isPending ?? false) || (state?.isActive ?? false);
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
