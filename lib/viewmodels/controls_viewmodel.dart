import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier, VoidCallback, kIsWeb, debugPrint;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/ble_sensor_service.dart';
import '../core/gravity_service.dart';
import '../core/ble_telemetry_service.dart';

class ControlsViewModel extends ChangeNotifier {
  // ── References (set via init) ──
  BleTelemetryService? _bleService;
  BleSensorService? _sensorService;
  LocalParticipant? _participant;
  Room? _room;

  // ── Subscriptions ──
  StreamSubscription<BleConnectionStatus>? _bleConnectionStatusSub;
  StreamSubscription<SportMetrics>? _bleMetricsSub;
  StreamSubscription<SensorStatus>? _sensorHrmStatusSub;
  StreamSubscription<SensorStatus>? _sensorCscStatusSub;
  StreamSubscription? _deviceChangeSub;

  // ── State exposed to UI ──
  CameraPosition _cameraPosition = CameraPosition.front;
  bool _speakerphoneOn = false;
  bool _sensorHrConnected = false;
  bool _sensorCadenceConnected = false;
  bool _bleGlassesConnected = false;
  int? _bleBattery;
  List<MediaDevice>? _audioInputs;
  List<MediaDevice>? _audioOutputs;

  // ── Getters ──
  CameraPosition get cameraPosition => _cameraPosition;
  bool get speakerphoneOn => _speakerphoneOn;
  bool get sensorHrConnected => _sensorHrConnected;
  bool get sensorCadenceConnected => _sensorCadenceConnected;
  bool get bleGlassesConnected => _bleGlassesConnected;
  int? get bleBattery => _bleBattery;
  List<MediaDevice>? get audioInputs => _audioInputs;
  List<MediaDevice>? get audioOutputs => _audioOutputs;
  Room? get room => _room;
  bool get isMuted => _participant?.isMuted ?? true;
  bool get isCameraEnabled => _participant?.isCameraEnabled() ?? false;

  bool get hasBluetoothOutput {
    final list = _audioOutputs;
    if (list == null || list.isEmpty) return false;
    return list.any((d) => _isBluetoothDevice(d.label));
  }

  bool get hasBluetoothInput {
    final list = _audioInputs;
    if (list == null || list.isEmpty) return false;
    return list.any((d) => _isBluetoothDevice(d.label));
  }

  static bool _isBluetoothDevice(String label) {
    final lower = label.toLowerCase();
    return lower.contains('bluetooth') ||
        lower.contains('headset') ||
        lower.contains('casque') ||
        lower.contains('écouteur') ||
        lower.contains('ecouteur') ||
        lower.contains('airpod') ||
        lower.contains('buds') ||
        lower.contains('freebuds') ||
        lower.contains('wh-') ||
        lower.contains('wf-') ||
        lower.contains('bose') ||
        lower.contains('jabra') ||
        lower.contains('shokz');
  }

  bool _lastMuted = true;
  bool _lastCameraEnabled = false;
  bool _isSwitchingCamera = false;
  Future<void> Function()? _onBeforeCameraSwitch;
  VoidCallback? _onAfterCameraSwitch;

  // ── Lifecycle ──
  void init({
    required LocalParticipant participant,
    required Room room,
    required BleTelemetryService bleService,
    required BleSensorService sensorService,
    VoidCallback? onBleConnected,
    VoidCallback? onBleDisconnected,
    Future<void> Function()? onBeforeCameraSwitch,
    VoidCallback? onAfterCameraSwitch,
  }) {
    _participant = participant;
    _room = room;
    _bleService = bleService;
    _sensorService = sensorService;
    _onBeforeCameraSwitch = onBeforeCameraSwitch;
    _onAfterCameraSwitch = onAfterCameraSwitch;
    _speakerphoneOn = AudioManager.instance.isSpeakerOutputPreferred;
    _lastMuted = participant.isMuted;
    _lastCameraEnabled = participant.isCameraEnabled();

    participant.addListener(_onParticipantChanged);

    _deviceChangeSub = Hardware.instance.onDeviceChange.stream.listen((devices) {
      _loadDevices(devices);
    });
    unawaited(Hardware.instance.enumerateDevices().then(_loadDevices));

    _bleConnectionStatusSub = _bleService!.connectionStatusStream.listen((status) {
      final wasConnected = _bleGlassesConnected;
      final isReady = status.phase == BleConnectionPhase.ready;
      final isDisconnected =
          status.phase == BleConnectionPhase.disconnected ||
          status.phase == BleConnectionPhase.disconnecting ||
          status.phase == BleConnectionPhase.failed ||
          status.phase == BleConnectionPhase.idle;
      var changed = false;
      if (_bleGlassesConnected != isReady) {
        _bleGlassesConnected = isReady;
        changed = true;
      }
      if ((!isReady || isDisconnected) && _bleBattery != null) {
        _bleBattery = null;
        changed = true;
      }
      if (changed) {
        notifyListeners();
      }
      if (isReady && !wasConnected) {
        onBleConnected?.call();
      } else if (!isReady && wasConnected) {
        onBleDisconnected?.call();
      }
    });

    _bleMetricsSub = _bleService!.metricsStream.listen((metrics) {
      if (metrics.battery == null || _bleBattery == metrics.battery) return;
      _bleBattery = metrics.battery;
      notifyListeners();
    });

    _sensorHrmStatusSub = _sensorService!.hrmStatusStream.listen((s) {
      if (_sensorHrConnected == s.isConnected) return;
      final wasConnected = _sensorHrConnected;
      _sensorHrConnected = s.isConnected;
      if (_sensorHrConnected && !wasConnected) {
        unawaited(HapticFeedback.mediumImpact());
      }
      notifyListeners();
    });

    _sensorCscStatusSub = _sensorService!.cscStatusStream.listen((s) {
      if (_sensorCadenceConnected == s.isConnected) return;
      final wasConnected = _sensorCadenceConnected;
      _sensorCadenceConnected = s.isConnected;
      if (_sensorCadenceConnected && !wasConnected) {
        unawaited(HapticFeedback.mediumImpact());
      }
      notifyListeners();
    });
  }

  void _onParticipantChanged() {
    final p = _participant;
    if (p == null) return;
    final muted = p.isMuted;
    final cam = p.isCameraEnabled();
    if (muted != _lastMuted || cam != _lastCameraEnabled) {
      _lastMuted = muted;
      _lastCameraEnabled = cam;
      notifyListeners();
    }
  }

  void _loadDevices(List<MediaDevice> devices) {
    _audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
    _audioOutputs = devices.where((d) => d.kind == 'audiooutput').toList();
    notifyListeners();
  }

  // ── Audio/Video actions ──
  void toggleMicrophone() {
    final p = _participant;
    if (p == null) return;
    if (p.isMuted) {
      p.setMicrophoneEnabled(true);
    } else {
      p.setMicrophoneEnabled(false);
    }
  }

  void toggleCamera() {
    final p = _participant;
    if (p == null) return;
    if (p.isCameraEnabled()) {
      p.setCameraEnabled(false);
    } else {
      p.setCameraEnabled(true);
    }
  }

  void enableAudio() => _participant?.setMicrophoneEnabled(true);
  void disableAudio() => _participant?.setMicrophoneEnabled(false);
  void enableVideo() => _participant?.setCameraEnabled(true);
  void disableVideo() => _participant?.setCameraEnabled(false);

  Future<void> switchCamera() async {
    if (_isSwitchingCamera) return;
    final track = _participant?.videoTrackPublications.firstOrNull?.track;
    if (track == null) return;
    _isSwitchingCamera = true;
    try {
      await _onBeforeCameraSwitch?.call();
      final newPosition = _cameraPosition.switched();
      await track.setCameraPosition(newPosition);
      _cameraPosition = newPosition;
      GravityService.instance.frontCamera = newPosition == CameraPosition.front;
      notifyListeners();
    } catch (error) {
      debugPrint('Could not restart track: $error');
    } finally {
      _onAfterCameraSwitch?.call();
      _isSwitchingCamera = false;
    }
  }

  Future<void> toggleSpeakerphone() async {
    final room = _room;
    if (room == null) return;
    _speakerphoneOn = !_speakerphoneOn;
    await AudioManager.instance.setSpeakerOutputPreferred(_speakerphoneOn);
    notifyListeners();
  }

  Future<void> setSpeakerphone(bool enabled) async {
    _speakerphoneOn = enabled;
    await AudioManager.instance.setSpeakerOutputPreferred(enabled);
    notifyListeners();
  }

  Future<void> selectAudioInput(MediaDevice device) async {
    final room = _room;
    if (room == null) return;
    await room.setAudioInputDevice(device);
    notifyListeners();
  }

  Future<void> selectAudioOutput(MediaDevice device) async {
    final room = _room;
    if (room == null) return;
    final isSpeaker = device.label.toLowerCase().contains('speaker') ||
        device.label.toLowerCase().contains('haut-parleur');
    _speakerphoneOn = isSpeaker;
    await AudioManager.instance.setSpeakerOutputPreferred(isSpeaker);
    await room.setAudioOutputDevice(device);
    notifyListeners();
  }

  Future<void> refreshAudioDevices() async {
    final devices = await Hardware.instance.enumerateDevices();
    _loadDevices(devices);
  }

  // ── BLE actions ──
  Future<void> toggleDisplaySession() async {
    final service = _bleService;
    if (service == null) return;
    final deviceId = service.connectedDeviceId;
    if (deviceId == null) return;

    if (service.isDisplaySessionActive) {
      await service.stopDisplaySession();
    } else {
      await service.startDisplaySession(deviceId);
    }
    notifyListeners();
  }

  Future<void> openBleSheet() async {
    final service = _bleService;
    if (service == null) return;

    if (!kIsWeb) {
      for (final perm in [
        Permission.bluetooth,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.location,
      ]) {
        await perm.request();
      }
    }

    await service.startScan();
  }

  Future<void> closeBleSheet() async {
    await _bleService?.stopScan();
  }

  Future<void> connectBleDevice(String deviceId) async {
    await _bleService?.connectAndListen(deviceId);
  }

  Future<void> disconnectBleDevice() async {
    _bleBattery = null;
    _bleGlassesConnected = false;
    notifyListeners();
    await _bleService?.disconnect();
  }

  Future<void> openSensorSheet() async {
    final service = _sensorService;
    if (service == null) return;

    if (!kIsWeb) {
      for (final perm in [
        Permission.bluetooth,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.location,
      ]) {
        await perm.request();
      }
    }

    await service.startScan();
  }

  Future<void> closeSensorSheet() async {
    await _sensorService?.stopScan();
  }

  // ── Cleanup ──
  @override
  void dispose() {
    _participant?.removeListener(_onParticipantChanged);
    unawaited(_deviceChangeSub?.cancel());
    unawaited(_bleConnectionStatusSub?.cancel());
    unawaited(_bleMetricsSub?.cancel());
    unawaited(_sensorHrmStatusSub?.cancel());
    unawaited(_sensorCscStatusSub?.cancel());
    super.dispose();
  }
}
