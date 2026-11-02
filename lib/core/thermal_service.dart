import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../presentation/widgets/thermal_alert_dialog.dart';

/// Représente l'état thermique courant de l'appareil.
class ThermalInfo {
  final bool isOverheating;
  final int status;
  final String statusName;
  final double? batteryTempC;
  final String source;
  final DateTime timestamp;

  const ThermalInfo({
    required this.isOverheating,
    this.status = 0,
    this.statusName = 'NORMAL',
    this.batteryTempC,
    this.source = 'native',
    required this.timestamp,
  });

  factory ThermalInfo.normal() => ThermalInfo(
        isOverheating: false,
        status: 0,
        statusName: 'NONE',
        source: 'initial',
        timestamp: DateTime.now(),
      );

  factory ThermalInfo.fromMap(Map<dynamic, dynamic> map, {String source = 'native'}) {
    return ThermalInfo(
      isOverheating: map['isOverheating'] == true,
      status: (map['status'] as num?)?.toInt() ?? 0,
      statusName: map['statusName'] as String? ?? 'UNKNOWN',
      batteryTempC: (map['batteryTempC'] as num?)?.toDouble(),
      source: source,
      timestamp: DateTime.now(),
    );
  }

  @override
  String toString() =>
      'ThermalInfo(isOverheating: $isOverheating, status: $status, statusName: $statusName, temp: ${batteryTempC != null ? '${batteryTempC!.toStringAsFixed(1)}°C' : 'N/A'}, source: $source)';
}

/// Service de surveillance thermique de l'appareil.
///
/// Détecte la surchauffe matérielle (PowerManager / Battery sur Android,
/// ProcessInfo.thermalState sur iOS) ainsi que les alertes de throttling
/// issues du pipeline d'analyse vidéo NPU/GPU.
///
/// Lorsqu'une surchauffe est détectée, un AlertDialog préventif est affiché
/// à l'utilisateur pour lui recommander les bons gestes.
class ThermalService {
  ThermalService._();
  static final ThermalService instance = ThermalService._();

  static const MethodChannel _methodChannel = MethodChannel('videolog/thermal');
  static const EventChannel _eventChannel = EventChannel('videolog/thermal_stream');

  GlobalKey<NavigatorState>? _navigatorKey;
  StreamSubscription<dynamic>? _streamSubscription;
  bool _initialized = false;
  bool _isDialogShowing = false;
  DateTime? _lastDialogShownAt;

  /// Cooldown entre deux affichages automatiques de la boîte de dialogue (3 minutes),
  /// sauf si l'état thermique s'aggrave (critique).
  static const Duration dialogCooldown = Duration(minutes: 3);

  /// Indique si la boîte de dialogue doit s'afficher automatiquement.
  bool autoShowDialog = true;

  /// État thermique actuel notifiable.
  final ValueNotifier<ThermalInfo> thermalInfo = ValueNotifier<ThermalInfo>(ThermalInfo.normal());

  bool get isOverheating => thermalInfo.value.isOverheating;
  bool get isDialogShowing => _isDialogShowing;

  /// Initialise le service thermique avec le navigatorKey global de l'application.
  Future<void> initialize({GlobalKey<NavigatorState>? navigatorKey}) async {
    if (navigatorKey != null) {
      _navigatorKey = navigatorKey;
    }
    if (_initialized) return;
    _initialized = true;

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      _subscribeThermalStream();
      unawaited(checkThermalStatus());
    }
  }

  void _subscribeThermalStream() {
    _streamSubscription?.cancel();
    _streamSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          final info = ThermalInfo.fromMap(event, source: 'stream');
          _onThermalInfoReceived(info);
        }
      },
      onError: (dynamic error) {
        debugPrint('[ThermalService] Erreur stream thermique : $error');
      },
    );
  }

  /// Interroge ponctuellement l'état thermique natif.
  Future<ThermalInfo> checkThermalStatus() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return thermalInfo.value;
    }

    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('getThermalStatus');
      if (result != null) {
        final info = ThermalInfo.fromMap(result, source: 'polling');
        _onThermalInfoReceived(info);
        return info;
      }
    } on MissingPluginException {
      // Ignoré sur simulateur ou plateforme non supportée
    } catch (e) {
      debugPrint('[ThermalService] Échec lecture statut thermique : $e');
    }
    return thermalInfo.value;
  }

  /// Appelé par le pipeline de détection posturale (NPU/GPU) lorsqu'un throttling thermique survient.
  void notifyThermalThrottled({required bool isThrottled, String reason = 'pose_pipeline'}) {
    if (isThrottled) {
      final current = thermalInfo.value;
      final updated = ThermalInfo(
        isOverheating: true,
        status: current.status > 0 ? current.status : 2, // au moins MODERATE
        statusName: current.statusName != 'NONE' ? current.statusName : 'THROTTLED',
        batteryTempC: current.batteryTempC,
        source: reason,
        timestamp: DateTime.now(),
      );
      _onThermalInfoReceived(updated);
    } else if (thermalInfo.value.source == reason) {
      // Retour à la normale si la source était le pipeline de pose
      thermalInfo.value = ThermalInfo(
        isOverheating: false,
        status: 0,
        statusName: 'NORMAL',
        batteryTempC: thermalInfo.value.batteryTempC,
        source: reason,
        timestamp: DateTime.now(),
      );
    }
  }

  void _onThermalInfoReceived(ThermalInfo newInfo) {
    final previous = thermalInfo.value;
    thermalInfo.value = newInfo;

    debugPrint(
      '[ThermalService] État thermique : overheating=${newInfo.isOverheating} '
      'status=${newInfo.statusName} temp=${newInfo.batteryTempC ?? 'N/A'}',
    );

    if (newInfo.isOverheating && autoShowDialog) {
      final now = DateTime.now();
      final isFirstTime = !previous.isOverheating;
      final cooldownPassed = _lastDialogShownAt == null ||
          now.difference(_lastDialogShownAt!) >= dialogCooldown;
      final isCriticalEscalation = newInfo.status >= 4 && previous.status < 4;

      if ((isFirstTime || cooldownPassed || isCriticalEscalation) && !_isDialogShowing) {
        showThermalDialog();
      }
    }
  }

  /// Affiche l'AlertDialog informant l'utilisateur de la surchauffe.
  Future<void> showThermalDialog({BuildContext? context, ThermalInfo? info}) async {
    final targetContext = context ?? _navigatorKey?.currentContext;
    if (targetContext == null) {
      debugPrint('[ThermalService] Impossible d\'afficher le dialogue : aucun BuildContext disponible.');
      return;
    }

    if (_isDialogShowing) return;

    _isDialogShowing = true;
    _lastDialogShownAt = DateTime.now();

    try {
      await ThermalAlertDialog.show(
        targetContext,
        info: info ?? thermalInfo.value,
      );
    } finally {
      _isDialogShowing = false;
    }
  }

  /// Réinitialise pour les tests ou le nettoyage.
  @visibleForTesting
  void resetForTesting() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _initialized = false;
    _isDialogShowing = false;
    _lastDialogShownAt = null;
    thermalInfo.value = ThermalInfo.normal();
  }
}
