import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../data/glasses_message.dart';

// ─── UUIDs ActiveLook / Engo ──────────────────────────────────────────────────
const String _kServiceUuid = "0783B03E-8535-B5A0-7140-A304D2495CB7";
const String _kTxUuid = "0783B03E-8535-B5A0-7140-A304D2495CB8";
const String _kRxUuid = "0783B03E-8535-B5A0-7140-A304D2495CBA";
const String _kControlUuid = "0783B03E-8535-B5A0-7140-A304D2495CB9";
const String _kGestureUuid = "0783B03E-8535-B5A0-7140-A304D2495CBB";
const String _kTouchUuid = "0783B03E-8535-B5A0-7140-A304D2495CBC";
const String _kBatteryUuid = "00002A19-0000-1000-8000-00805F9B34FB";

const int _kTargetMtu = 512;
const int _kMaxChunkSize = 128;

// ─── Commandes ActiveLook §4 ──────────────────────────────────────────────────
const int _cmdDisplayPower = 0x00;
const int _cmdClear = 0x01;
const int _cmdBattery = 0x05;
const int _cmdLuminance = 0x10;
const int _cmdAlsOnly = 0x22;
const int _cmdTxtDisplay = 0x37;
const int _cmdHoldFlush = 0x39;

const int _actionHold = 0x00;
const int _actionFlush = 0x01;
const int _actionResetFlush = 0xFF;

// ─── Résolution & Rendu (§5.7) ────────────────────────────────────────────────
const int _kDisplayH = 256;
const int _kTextRotation = 0x04; // miroir horizontal Engo
const int _kColorWhite = 0x0F; // blanc maximum
const int _kColorGray = 0x09; // gris moyen pour les labels

const int _kFontSmall = 1; // ~16 px
const int _kFontValue = 3; // ~32 px
const int _kFontBig = 2; // ~24 px
const Map<int, int> _kFontCharH = {1: 16, 2: 24, 3: 32};

// ─── §3.5 Contrôle de flux ────────────────────────────────────────────────────
const int _flowCanSend = 0x01;
const int _flowStop = 0x02;

// ─── Positions verticales HUD (translation +25 px vers le haut pour éviter la coupure du km en bas d'écran) ──
const int _yDistValue = 60;
const int _yBpmValue = 120;
const int _yKcalValue = 180;
const int _yRpmValue = 240;

// ─── Modèle ───────────────────────────────────────────────────────────────────
enum BleConnectionPhase {
  idle,
  connecting,
  connected,
  initializing,
  ready,
  disconnecting,
  disconnected,
  failed,
}

class BleConnectionStatus {
  final String? deviceId;
  final BleConnectionPhase phase;
  final String message;
  final String? error;
  final DateTime updatedAt;

  const BleConnectionStatus({
    required this.phase,
    this.deviceId,
    required this.message,
    this.error,
    required this.updatedAt,
  });

  BleConnectionStatus.idle()
    : this(
        phase: BleConnectionPhase.idle,
        message: 'Prêt pour une connexion BLE',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  bool get isBusy =>
      phase == BleConnectionPhase.connecting ||
      phase == BleConnectionPhase.connected ||
      phase == BleConnectionPhase.initializing ||
      phase == BleConnectionPhase.disconnecting;
}

class SportMetrics {
  final double distanceMiles;
  final int bpm;
  final int kcal;
  final int? battery;
  final bool? gestureDetected;
  final bool? touchDetected;

  const SportMetrics({
    this.distanceMiles = 0,
    this.bpm = 0,
    this.kcal = 0,
    this.battery,
    this.gestureDetected,
    this.touchDetected,
  });

  static int estimateKcal({
    required int bpm,
    required double weightKg,
    required int ageYears,
    required bool isMale,
    required int durationSeconds,
  }) {
    final min = durationSeconds / 60.0;
    if (isMale) {
      return ((-55.0969 +
                  0.6309 * bpm +
                  0.1988 * weightKg +
                  0.2017 * ageYears) /
              4.184 *
              min)
          .round();
    } else {
      return ((-20.4022 + 0.4472 * bpm - 0.1263 * weightKg + 0.074 * ageYears) /
              4.184 *
              min)
          .round();
    }
  }

  static double haversineDistanceMiles(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 3958.8;
    final dLat = _rad(lat2 - lat1), dLon = _rad(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double d) => d * pi / 180;
}

/// Catégorie d'une transaction BLE pour la gestion de priorité et de coalescence.
enum BleCommandTag {
  /// Commandes système / session (power, luminance, clear initial, batterie).
  control,

  /// Rafraîchissement périodique du HUD télémétrique (coalescable si la file est occupée).
  telemetry,

  /// Message prioritaire du coach (évince les trames télémétriques en attente).
  coachMessage,
}

class _QueuedBleTransaction {
  _QueuedBleTransaction({
    required this.deviceId,
    required this.commands,
    required this.tag,
  });

  final String deviceId;
  final List<List<int>> commands;
  final BleCommandTag tag;
  final Completer<bool> completer = Completer<bool>();
}

typedef GattChunkWriter =
    Future<void> Function(String deviceId, List<int> chunkBytes);

/// Service dédié et testable unitairement pour le pilotage BLE des lunettes
/// ActiveLook / Engo (file d'attente GATT sérialisée, contrôle de flux, HUD et messages coach).
class EngoGlassesDisplayService {
  EngoGlassesDisplayService({
    FlutterReactiveBle? ble,
    GattChunkWriter? gattWriter,
    Duration flowControlTimeout = const Duration(seconds: 2),
  }) : _ble = ble,
       _gattWriter = gattWriter,
       _flowControlTimeout = flowControlTimeout;

  FlutterReactiveBle? _ble;
  FlutterReactiveBle get _reactiveBle => _ble ??= FlutterReactiveBle();

  final GattChunkWriter? _gattWriter;
  final Duration _flowControlTimeout;

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connectionSub;
  StreamSubscription<List<int>>? _txSub,
      _controlSub,
      _gestureSub,
      _touchSub,
      _batterySub;

  final _devicesCtrl = StreamController<List<DiscoveredDevice>>.broadcast();
  final _metricsCtrl = StreamController<SportMetrics>.broadcast();
  final _connectionCtrl = StreamController<DeviceConnectionState>.broadcast();
  final _connectionStatusCtrl =
      StreamController<BleConnectionStatus>.broadcast();

  Stream<List<DiscoveredDevice>> get devicesStream => _devicesCtrl.stream;
  Stream<SportMetrics> get metricsStream => _metricsCtrl.stream;
  Stream<DeviceConnectionState> get connectionStream => _connectionCtrl.stream;
  Stream<BleConnectionStatus> get connectionStatusStream =>
      _connectionStatusCtrl.stream;

  final List<DiscoveredDevice> _devices = [];
  String? connectedDeviceId;
  bool _canSendData = true;
  Completer<void>? _flowResumeCompleter;
  bool _displaySessionActive = false;
  BleConnectionStatus _connectionStatus = BleConnectionStatus.idle();

  bool get isDisplaySessionActive => _displaySessionActive;
  bool get canSendData => _canSendData;
  int get pendingTransactionCount => _cmdQueue.length;
  BleConnectionStatus get connectionStatus => _connectionStatus;

  /// Permet de configurer une session active en test unitaire sans matériel BLE.
  void debugConfigureSession({
    required String? deviceId,
    required bool displaySessionActive,
    int negotiatedMtu = 128,
  }) {
    connectedDeviceId = deviceId;
    _displaySessionActive = displaySessionActive;
    _negotiatedMtu = negotiatedMtu;
  }

  /// Reconnaît une paire de lunettes ActiveLook/Engo via son nom annoncé ou
  /// le service propriétaire présent dans la réponse de scan.
  bool isEngoDevice(DiscoveredDevice device) {
    final name = device.name.toLowerCase().trim();
    if (name.contains('engo') ||
        name.contains('activelook') ||
        name.contains('active look')) {
      return true;
    }
    return device.serviceUuids.any(
      (uuid) => uuid.toString().toLowerCase().contains('0783b03e'),
    );
  }

  static final _serviceUuid = Uuid.parse(_kServiceUuid);
  static final _txUuid = Uuid.parse(_kTxUuid);
  static final _rxUuid = Uuid.parse(_kRxUuid);
  static final _controlUuid = Uuid.parse(_kControlUuid);
  static final _gestureUuid = Uuid.parse(_kGestureUuid);
  static final _touchUuid = Uuid.parse(_kTouchUuid);
  static final _batteryUuid = Uuid.parse(_kBatteryUuid);

  int _negotiatedMtu = 20;
  final List<_QueuedBleTransaction> _cmdQueue = [];
  bool _cmdQueueRunning = false;

  // ─── Scan ─────────────────────────────────────────────────────────────────
  Future<void> startScan() async {
    await _scanSub?.cancel();
    _devices.clear();
    _devicesCtrl.add(const []);
    _scanSub = _reactiveBle
        .scanForDevices(withServices: [], scanMode: ScanMode.lowLatency)
        .listen((d) {
          final i = _devices.indexWhere((e) => e.id == d.id);
          i >= 0 ? _devices[i] = d : _devices.add(d);
          _devicesCtrl.add(List.unmodifiable(_devices));
        }, onError: _devicesCtrl.addError);
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
  }

  // ─── Contrôle de flux BLE (§3.5) ──────────────────────────────────────────
  /// Traite un octet reçu sur la caractéristique de contrôle ActiveLook (`0x01` = prêt, `0x02` = pause).
  void handleFlowControlByte(int v) {
    if (v == _flowCanSend) {
      _canSendData = true;
      final completer = _flowResumeCompleter;
      _flowResumeCompleter = null;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    } else if (v == _flowStop) {
      _canSendData = false;
      _flowResumeCompleter ??= Completer<void>();
      debugPrint('⚠️ ActiveLook buffer 75%: pause du flux GATT');
    } else if (v >= 0x03) {
      debugPrint('⚠️ ActiveLook erreur: 0x${v.toRadixString(16)}');
    }
  }

  Future<void> _waitForFlowControl() async {
    if (_canSendData) return;
    final completer = _flowResumeCompleter ??= Completer<void>();
    try {
      await completer.future.timeout(_flowControlTimeout);
    } on TimeoutException {
      debugPrint('⚠️ Timeout contrôle de flux ActiveLook : reprise forcée');
      _canSendData = true;
      if (identical(_flowResumeCompleter, completer)) {
        _flowResumeCompleter = null;
      }
    }
  }

  // ─── File d'attente GATT sérialisée (Command Queue) ───────────────────────
  /// Enfile une commande unitaire et attend l'accusé d'écriture GATT (`writeCharacteristicWithResponse`).
  Future<bool> enqueueCommand(
    String deviceId,
    List<int> cmd, {
    BleCommandTag tag = BleCommandTag.control,
  }) {
    return enqueueTransaction(deviceId, [cmd], tag: tag);
  }

  /// Enfile un lot atomique de trames (ex: `[Hold, Clear, ...Text..., Flush]`) qui ne peut pas
  /// être entrelacé avec une autre transaction.
  Future<bool> enqueueTransaction(
    String deviceId,
    List<List<int>> commands, {
    BleCommandTag tag = BleCommandTag.control,
  }) {
    if (commands.isEmpty) return Future.value(true);

    final tx = _QueuedBleTransaction(
      deviceId: deviceId,
      commands: List<List<int>>.unmodifiable(
        commands.map((c) => List<int>.unmodifiable(c)),
      ),
      tag: tag,
    );

    if (tag == BleCommandTag.telemetry) {
      _evictPendingByTag(BleCommandTag.telemetry);
      _cmdQueue.add(tx);
    } else if (tag == BleCommandTag.coachMessage) {
      _evictPendingByTag(BleCommandTag.telemetry);
      final insertIndex = _cmdQueue.indexWhere(
        (item) => item.tag != BleCommandTag.control,
      );
      if (insertIndex >= 0) {
        _cmdQueue.insert(insertIndex, tx);
      } else {
        _cmdQueue.add(tx);
      }
    } else {
      _cmdQueue.add(tx);
    }

    if (!_cmdQueueRunning) {
      unawaited(_drainCommandQueue());
    }
    return tx.completer.future;
  }

  void _evictPendingByTag(BleCommandTag tag) {
    for (var i = _cmdQueue.length - 1; i >= 0; i--) {
      if (_cmdQueue[i].tag == tag) {
        final evicted = _cmdQueue.removeAt(i);
        if (!evicted.completer.isCompleted) {
          evicted.completer.complete(false);
        }
      }
    }
  }

  void _clearCommandQueue() {
    while (_cmdQueue.isNotEmpty) {
      final tx = _cmdQueue.removeAt(0);
      if (!tx.completer.isCompleted) {
        tx.completer.complete(false);
      }
    }
    _canSendData = true;
    final flowCompleter = _flowResumeCompleter;
    _flowResumeCompleter = null;
    if (flowCompleter != null && !flowCompleter.isCompleted) {
      flowCompleter.complete();
    }
  }

  Future<void> _drainCommandQueue() async {
    if (_cmdQueueRunning) return;
    _cmdQueueRunning = true;
    try {
      while (_cmdQueue.isNotEmpty) {
        final tx = _cmdQueue.removeAt(0);
        var ok = true;
        for (final cmd in tx.commands) {
          if (connectedDeviceId != null && tx.deviceId != connectedDeviceId) {
            ok = false;
            break;
          }
          try {
            await sendCommand(tx.deviceId, cmd);
          } catch (e) {
            ok = false;
            debugPrint('⚠️ BLE cmd failed: $e');
            break;
          }
        }
        if (!tx.completer.isCompleted) {
          tx.completer.complete(ok);
        }
      }
    } finally {
      _cmdQueueRunning = false;
    }
  }

  // ─── Écrans de session ────────────────────────────────────────────────────
  Future<void> _showReadyScreen(String deviceId) async {
    const text = 'READY';
    final yText = (_kDisplayH - (_kFontCharH[_kFontValue] ?? 32)) ~/ 2;
    const sub = 'Session en cours...';

    await enqueueTransaction(deviceId, [
      _buildFrame(_cmdHoldFlush, [_actionHold]),
      _buildFrame(_cmdClear, []),
      _buildTextCommand(
        x: 250,
        y: yText,
        fontId: _kFontValue,
        color: _kColorWhite,
        text: text,
      ),
      _buildTextCommand(
        x: 250,
        y: yText + (_kFontCharH[_kFontValue] ?? 32) + 8,
        fontId: _kFontSmall,
        color: _kColorGray,
        text: sub,
      ),
      _buildFrame(_cmdHoldFlush, [_actionFlush]),
    ]);
    await Future.delayed(const Duration(milliseconds: 1500));
  }

  Future<void> _showCountdown(String deviceId) async {
    final h = _kFontCharH[_kFontBig] ?? 24;
    for (final step in ['3', '2', '1', 'GO!']) {
      await enqueueTransaction(deviceId, [
        _buildFrame(_cmdHoldFlush, [_actionHold]),
        _buildFrame(_cmdClear, []),
        _buildTextCommand(
          x: 250,
          y: (_kDisplayH - h) ~/ 2,
          fontId: _kFontBig,
          color: _kColorWhite,
          text: step,
        ),
        _buildFrame(_cmdHoldFlush, [_actionFlush]),
      ]);
      await Future.delayed(
        step == 'GO!'
            ? const Duration(milliseconds: 800)
            : const Duration(seconds: 1),
      );
    }
  }

  // ─── Connexion ────────────────────────────────────────────────────────────
  Future<void> connectAndListen(String deviceId) async {
    await disconnect();
    _emitStatus(
      BleConnectionPhase.connecting,
      deviceId: deviceId,
      message: 'Connexion BLE...',
    );

    _connectionSub = _reactiveBle
        .connectToDevice(
          id: deviceId,
          connectionTimeout: const Duration(seconds: 12),
        )
        .listen(
          (update) async {
            _connectionCtrl.add(update.connectionState);

            if (update.connectionState == DeviceConnectionState.connected) {
              connectedDeviceId = deviceId;
              _canSendData = true;
              _emitStatus(
                BleConnectionPhase.connected,
                deviceId: deviceId,
                message: 'Connexion établie',
              );
              _emitStatus(
                BleConnectionPhase.initializing,
                deviceId: deviceId,
                message: 'Initialisation...',
              );
              try {
                _negotiatedMtu =
                    (await _reactiveBle.requestMtu(
                      deviceId: deviceId,
                      mtu: _kTargetMtu,
                    )) -
                    3;
                debugPrint('✅ MTU: $_negotiatedMtu B');
              } catch (e) {
                _negotiatedMtu = 20;
                debugPrint('⚠️ MTU fallback 20B: $e');
              }

              await _subscribeAll(deviceId);
              _displaySessionActive = false;
              await enqueueCommand(deviceId, _buildFrame(_cmdBattery, []));
              _emitStatus(
                BleConnectionPhase.ready,
                deviceId: deviceId,
                message: 'Lunettes prêtes',
              );
            }

            if (update.connectionState == DeviceConnectionState.disconnected) {
              connectedDeviceId = null;
              _displaySessionActive = false;
              _clearCommandQueue();
              _emitStatus(
                BleConnectionPhase.disconnected,
                deviceId: deviceId,
                message: 'Déconnecté',
              );
              await _cancelCharSubs();
            }
          },
          onError: (e) {
            _clearCommandQueue();
            _emitStatus(
              BleConnectionPhase.failed,
              deviceId: deviceId,
              message: 'Connexion échouée',
              error: e.toString(),
            );
            _connectionCtrl.addError(e);
          },
        );
  }

  // ─── Session ──────────────────────────────────────────────────────────────
  Future<void> startDisplaySession([String? deviceId]) async {
    final target = deviceId ?? connectedDeviceId;
    if (target == null || _displaySessionActive) return;
    _emitStatus(
      BleConnectionPhase.initializing,
      deviceId: target,
      message: 'Démarrage session...',
    );

    await enqueueTransaction(target, [
      _buildFrame(_cmdDisplayPower, [0x01]),
      _buildFrame(_cmdAlsOnly, [0x00]),
      _buildFrame(_cmdLuminance, [0x0F]),
      _buildFrame(_cmdHoldFlush, [_actionResetFlush]),
      _buildFrame(_cmdClear, []),
    ]);

    await _showReadyScreen(target);
    await _showCountdown(target);

    await enqueueTransaction(target, [
      _buildFrame(_cmdHoldFlush, [_actionResetFlush]),
      _buildFrame(_cmdClear, []),
    ]);

    _displaySessionActive = true;
    _emitStatus(
      BleConnectionPhase.ready,
      deviceId: target,
      message: 'Session ActiveLook active',
    );
  }

  Future<void> stopDisplaySession() async {
    final target = connectedDeviceId;
    if (!_displaySessionActive) return;
    _emitStatus(
      BleConnectionPhase.disconnecting,
      deviceId: target,
      message: 'Arrêt session...',
    );

    if (target != null) {
      const msg = 'Session terminee';
      await enqueueTransaction(target, [
        _buildFrame(_cmdHoldFlush, [_actionHold]),
        _buildFrame(_cmdClear, []),
        _buildTextCommand(
          x: 250,
          y: (_kDisplayH - 16) ~/ 2,
          fontId: _kFontSmall,
          color: _kColorWhite,
          text: msg,
        ),
        _buildFrame(_cmdHoldFlush, [_actionFlush]),
      ]);
      await Future.delayed(const Duration(seconds: 1));
      await enqueueCommand(target, _buildFrame(_cmdDisplayPower, [0x00]));
    }

    _displaySessionActive = false;
    _emitStatus(
      BleConnectionPhase.ready,
      deviceId: target,
      message: 'Session arrêtée',
    );
  }

  // ─── Abonnements ──────────────────────────────────────────────────────────
  Future<void> _subscribeAll(String deviceId) async {
    QualifiedCharacteristic char(Uuid uuid) => QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: _serviceUuid,
      characteristicId: uuid,
    );

    _txSub = _reactiveBle
        .subscribeToCharacteristic(char(_txUuid))
        .listen(handleTxFrameBytes, onError: _metricsCtrl.addError);
    _controlSub = _reactiveBle
        .subscribeToCharacteristic(char(_controlUuid))
        .listen((b) {
          if (b.isEmpty) return;
          handleFlowControlByte(b[0]);
        });
    _gestureSub = _reactiveBle
        .subscribeToCharacteristic(char(_gestureUuid))
        .listen((b) {
          if (b.isNotEmpty && b[0] == 0x01) {
            _metricsCtrl.add(const SportMetrics(gestureDetected: true));
          }
        });
    _touchSub = _reactiveBle.subscribeToCharacteristic(char(_touchUuid)).listen(
      (b) {
        if (b.isNotEmpty && b[0] == 0x01) {
          _metricsCtrl.add(const SportMetrics(touchDetected: true));
        }
      },
    );
    _batterySub = _reactiveBle
        .subscribeToCharacteristic(
          QualifiedCharacteristic(
            deviceId: deviceId,
            serviceId: Uuid.parse("0000180F-0000-1000-8000-00805F9B34FB"),
            characteristicId: _batteryUuid,
          ),
        )
        .listen((b) {
          if (b.isNotEmpty) {
            _metricsCtrl.add(SportMetrics(battery: b[0].clamp(0, 100)));
          }
        });
  }

  /// Point d'entrée testable unitairement pour décoder une trame TX ActiveLook (ex: batterie `0x05`).
  void handleTxFrameBytes(List<int> bytes) {
    if (bytes.length < 5 || bytes[0] != 0xFF || bytes.last != 0xAA) return;
    final cmdId = bytes[1];
    final data = bytes.sublist(4, bytes.length - 1);
    if (cmdId == _cmdBattery && data.isNotEmpty) {
      _metricsCtrl.add(SportMetrics(battery: data[0].clamp(0, 100)));
    }
  }

  // ─── Affichage HUD ────────────────────────────────────────────────────────
  Future<void> displayMetrics(
    String deviceId, {
    required double distanceMiles,
    int? bpm,
    required int kcal,
    int? cadence,
  }) async {
    if (!_displaySessionActive || _messageActive) return;

    final distKm = distanceMiles * 1.60934;
    final distStr = '${distKm.toStringAsFixed(2)} km';
    final bpmStr = bpm != null ? '$bpm bpm' : '-- bpm';
    final kcalStr = '$kcal kcal';
    final rpmStr = '${cadence ?? 0} rpm';

    debugPrint("distance $distStr");
    debugPrint("bpm $bpmStr");
    debugPrint("kcal $kcalStr");
    if (cadence != null) debugPrint("cadence $rpmStr");

    await enqueueTransaction(
      deviceId,
      [
        _buildFrame(_cmdHoldFlush, [_actionHold]),
        _buildFrame(_cmdClear, []),
        _buildTextCommand(
          x: 250,
          y: _yDistValue,
          fontId: _kFontValue,
          color: _kColorWhite,
          text: distStr,
        ),
        _buildTextCommand(
          x: 250,
          y: _yBpmValue,
          fontId: _kFontValue,
          color: _kColorWhite,
          text: bpmStr,
        ),
        _buildTextCommand(
          x: 250,
          y: _yKcalValue,
          fontId: _kFontValue,
          color: _kColorWhite,
          text: kcalStr,
        ),
        _buildTextCommand(
          x: 250,
          y: _yRpmValue,
          fontId: _kFontValue,
          color: _kColorWhite,
          text: rpmStr,
        ),
        _buildFrame(_cmdHoldFlush, [_actionFlush]),
      ],
      tag: BleCommandTag.telemetry,
    );
  }

  // ─── Message du coach ─────────────────────────────────────────────────────
  bool _messageActive = false;
  DateTime? _messageShownAt;
  Timer? _messageTimer;

  bool get isMessageActive => _messageActive;

  static const Duration _minMessageGap = Duration(milliseconds: 500);

  Future<bool> showMessage(List<String> lines, Duration duration) async {
    final deviceId = connectedDeviceId;
    if (deviceId == null || !_displaySessionActive) {
      debugPrint('🕶️ Message ignoré : lunettes non prêtes');
      return false;
    }
    if (lines.isEmpty) return false;
    final now = DateTime.now();
    if (_messageShownAt != null &&
        now.difference(_messageShownAt!) < _minMessageGap) {
      return false;
    }
    _messageShownAt = now;
    _messageActive = true;
    _messageTimer?.cancel();
    _messageTimer = Timer(duration, () => _messageActive = false);

    final frames = <List<int>>[
      _buildFrame(_cmdHoldFlush, [_actionHold]),
      _buildFrame(_cmdClear, []),
      for (final line in GlassesLayout.place(lines))
        _buildTextCommand(
          x: line.x,
          y: line.y,
          fontId: GlassesLayout.fontId,
          color: _kColorWhite,
          text: line.text,
        ),
      _buildFrame(_cmdHoldFlush, [_actionFlush]),
    ];

    return enqueueTransaction(
      deviceId,
      frames,
      tag: BleCommandTag.coachMessage,
    );
  }

  // ─── §3.1 Construction trames binaires ───────────────────────────────────
  List<int> _buildFrame(int cmdId, List<int> data) {
    final length = 5 + data.length;
    return [0xFF, cmdId, 0x00, length, ...data, 0xAA];
  }

  List<int> _buildTextCommand({
    required int x,
    required int y,
    required int fontId,
    required int color,
    required String text,
  }) {
    return _buildFrame(_cmdTxtDisplay, [
      (x >> 8) & 0xFF, x & 0xFF, // s16 x big-endian
      (y >> 8) & 0xFF, y & 0xFF, // s16 y big-endian
      _kTextRotation, // u8  r = 0x04 (miroir Engo)
      fontId, // u8  f
      color, // u8  c
      ...text.codeUnits, // str ASCII
    ]);
  }

  // ─── Envoi BLE → caractéristique RX (avec acquittement GATT et contrôle de débit) ──
  Future<void> _writeGattChunk(String deviceId, List<int> bytes) async {
    final writer = _gattWriter;
    if (writer != null) {
      await writer(deviceId, bytes);
      return;
    }
    final rxChar = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: _serviceUuid,
      characteristicId: _rxUuid,
    );
    await _reactiveBle.writeCharacteristicWithResponse(rxChar, value: bytes);
  }

  Future<void> sendCommand(String deviceId, List<int> commandBytes) async {
    final chunk = _negotiatedMtu.clamp(20, _kMaxChunkSize);

    if (commandBytes.length <= chunk) {
      await _waitForFlowControl();
      debugPrint(
        '📡 BLE ${commandBytes.length}B cmd=0x${commandBytes[1].toRadixString(16)}',
      );
      await _writeGattChunk(deviceId, commandBytes);
    } else {
      debugPrint('📡 BLE fragmenté ${commandBytes.length}B → ${chunk}B/chunk');
      for (var i = 0; i < commandBytes.length; i += chunk) {
        await _waitForFlowControl();
        final slice = commandBytes.sublist(
          i,
          (i + chunk).clamp(0, commandBytes.length),
        );
        await _writeGattChunk(deviceId, slice);
      }
    }
  }

  // ─── Cleanup ──────────────────────────────────────────────────────────────
  Future<void> _cancelCharSubs() async {
    for (final s in [
      _txSub,
      _controlSub,
      _gestureSub,
      _touchSub,
      _batterySub,
    ]) {
      await s?.cancel();
    }
    _txSub = _controlSub = _gestureSub = _touchSub = _batterySub = null;
  }

  Future<void> disconnect() async {
    _emitStatus(
      BleConnectionPhase.disconnecting,
      deviceId: connectedDeviceId,
      message: 'Déconnexion...',
    );
    _clearCommandQueue();
    await _cancelCharSubs();
    await _connectionSub?.cancel();
    _connectionSub = null;
    connectedDeviceId = null;
    _displaySessionActive = false;
    _emitStatus(BleConnectionPhase.disconnected, message: 'Déconnecté');
  }

  Future<void> dispose() async {
    _messageTimer?.cancel();
    _clearCommandQueue();
    await stopScan();
    await disconnect();
    for (final c in [
      _devicesCtrl,
      _metricsCtrl,
      _connectionCtrl,
      _connectionStatusCtrl,
    ]) {
      await c.close();
    }
  }

  void _emitStatus(
    BleConnectionPhase phase, {
    String? deviceId,
    required String message,
    String? error,
  }) {
    final s = BleConnectionStatus(
      phase: phase,
      deviceId: deviceId ?? _connectionStatus.deviceId,
      message: message,
      error: error,
      updatedAt: DateTime.now(),
    );
    _connectionStatus = s;
    _connectionStatusCtrl.add(s);
  }
}
