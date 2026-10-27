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

  static const Duration pendingConfirmationTimeout = Duration(seconds: 45);

  RecordingState? state;
  bool loading = false;
  String? error;
  String? operation;
  bool pendingTimedOut = false;
  String layout = 'grid';
  DateTime? _pendingSince;
  DateTime? lastStatusCheckAt;
  bool? lastStatusCheckSucceeded;
  String? lastStatusCheckMessage;
  String? lastStatusCheckStatus;
  int successfulStatusChecks = 0;
  int failedStatusChecks = 0;

  Timer? _pollTimer;
  Timer? _pendingTimeoutTimer;
  String? _trackedPendingStatus;
  bool _requestInFlight = false;
  bool _disposed = false;

  bool get canStart =>
      canControl &&
      !loading &&
      !_requestInFlight &&
      (state == null ? false : state!.canStart);

  bool get canStop =>
      canControl && !loading && !_requestInFlight && (state?.canStop ?? false);

  bool get isPending => state?.isPending ?? false;

  bool get isRecording => state?.isActive ?? false;

  String get operationLabel => switch (operation) {
    'start' => 'Envoi du démarrage...',
    'stop' => "Envoi de l'arrêt...",
    _ => 'Actualisation...',
  };

  String get pendingLabel {
    if (pendingTimedOut) return 'À vérifier';
    return state?.isStarting == true ? 'Préparation...' : 'Finalisation...';
  }

  String? get pendingDiagnosticMessage {
    if (!pendingTimedOut) return null;
    final elapsed = _pendingSince == null
        ? pendingConfirmationTimeout.inSeconds
        : DateTime.now().difference(_pendingSince!).inSeconds;
    final checkTime = lastStatusCheckAt?.toLocal().toIso8601String();
    final checkedAfterPending =
        lastStatusCheckAt != null &&
        (_pendingSince == null || !lastStatusCheckAt!.isBefore(_pendingSince!));
    if (checkedAfterPending && lastStatusCheckSucceeded == true) {
      return 'Attente: ${elapsed}s. Derniere verification reussie'
          '${checkTime == null ? '' : ' ($checkTime)'}: statut '
          '${lastStatusCheckStatus ?? state?.rawStatus ?? 'inconnu'}. '
          'Egress: ${state?.egressId ?? 'non fourni'}. '
          'Le mobile communique avec l\'API. Le statut reste en attente '
          'cote service d\'enregistrement (backend/LiveKit). '
          'Controles: $successfulStatusChecks reussis, '
          '$failedStatusChecks en echec.';
    }
    if (checkedAfterPending && lastStatusCheckSucceeded == false) {
      return 'Attente: ${elapsed}s. Derniere verification echouee'
          '${checkTime == null ? '' : ' ($checkTime)'}: '
          '${lastStatusCheckMessage ?? 'aucun statut recu'}. '
          'Le mobile n\'a pas obtenu de statut fiable; verifiez le reseau, '
          'la session et la reponse API. Controles: '
          '$successfulStatusChecks reussis, $failedStatusChecks en echec.';
    }
    return 'Attente: ${elapsed}s. Aucune verification de statut n\'a abouti.';
  }

  /// Raison lisible quand [canStart] est faux, utile pour l'UI et les logs.
  String? get startBlockReason {
    if (!canControl) {
      return 'Votre compte ne peut pas piloter l\'enregistrement de cette session.';
    }
    if (_requestInFlight && !loading) {
      return 'Vérification de l\'état en cours. Réessayez dans un instant.';
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
    if (_requestInFlight && !loading) {
      return 'Vérification de l\'état en cours. Réessayez dans un instant.';
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
      if (pendingTimedOut && state?.isPending == true) {
        pendingTimedOut = false;
        _pendingSince = DateTime.now();
        successfulStatusChecks = 0;
        failedStatusChecks = 0;
        _pendingTimeoutTimer?.cancel();
        _pendingTimeoutTimer = Timer(
          pendingConfirmationTimeout,
          _onPendingConfirmationTimeout,
        );
      }
      _notify();
    }
    debugPrint(
      '[Recording] load room=$roomName canControl=$canControl silent=$silent',
    );

    try {
      final next = await ApiService.getRecording(roomName);
      state = next;
      lastStatusCheckAt = DateTime.now();
      lastStatusCheckSucceeded = true;
      lastStatusCheckStatus = next.rawStatus;
      lastStatusCheckMessage = 'Reponse API recue';
      successfulStatusChecks++;
      if (!pendingTimedOut) error = null;
      debugPrint(
        '[Recording] load OK room=$roomName status=${next.rawStatus} '
        'normalized=${next.status} egress=${next.egressId}',
      );
    } on ApiException catch (exception, stack) {
      error = _errorMessage(exception);
      lastStatusCheckAt = DateTime.now();
      lastStatusCheckSucceeded = false;
      failedStatusChecks++;
      lastStatusCheckMessage = exception.statusCode == 0
          ? exception.message
          : 'HTTP ${exception.statusCode}: ${exception.message}';
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
      lastStatusCheckAt = DateTime.now();
      lastStatusCheckSucceeded = false;
      failedStatusChecks++;
      lastStatusCheckMessage = err.toString();
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
    _requestInFlight = true;
    loading = true;
    this.operation = operation;
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
      // A timeout can happen after the server received the command. Refresh
      // to reconcile the UI before reporting the final result.
      refreshAfterError = exception.isConflict || exception.statusCode == 0;
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
      _requestInFlight = false;
      loading = false;
      this.operation = null;
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
    final pendingStatus = state?.isPending == true ? state!.status : null;
    if (pendingStatus != _trackedPendingStatus) {
      _pendingTimeoutTimer?.cancel();
      _trackedPendingStatus = pendingStatus;
      pendingTimedOut = false;
      _pendingSince = pendingStatus == null ? null : DateTime.now();
      if (pendingStatus != null) {
        successfulStatusChecks = 0;
        failedStatusChecks = 0;
        _pendingTimeoutTimer = Timer(
          pendingConfirmationTimeout,
          _onPendingConfirmationTimeout,
        );
      }
    }

    final pending = pendingStatus != null;
    final shouldPoll = (pending && !pendingTimedOut) || isRecording;
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

  void _onPendingConfirmationTimeout() {
    if (_disposed || state?.isPending != true) return;
    pendingTimedOut = true;
    _pendingTimeoutTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    final action = state!.isStarting ? 'démarrage' : 'arrêt';
    error =
        "Le serveur n'a pas confirmé le $action après "
        '${pendingConfirmationTimeout.inSeconds} secondes. '
        "Vérifiez l'état avant de relancer l'opération.";
    debugPrint(
      '[Recording] confirmation timeout room=$roomName '
      'status=${state!.rawStatus} after=${pendingConfirmationTimeout.inSeconds}s',
    );
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    _pendingTimeoutTimer?.cancel();
    _pendingTimeoutTimer = null;
    super.dispose();
  }
}
