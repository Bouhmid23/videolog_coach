import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

const int _serviceId = 256;
const String _channelId = 'videolog_call';
const String _endCallButtonId = 'end_call';
const String _endCallEvent = 'end_call';
const String _roomKey = 'call_room';
const String _usernameKey = 'call_username';
const String _startedAtKey = 'call_started_at';

@pragma('vm:entry-point')
void callForegroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(CallTaskHandler());
}

class CallTaskHandler extends TaskHandler {
  DateTime? _startedAt;
  String _roomName = '';
  String _username = '';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final startedAtMs = await FlutterForegroundTask.getData<int>(
      key: _startedAtKey,
    );
    _startedAt = startedAtMs != null
        ? DateTime.fromMillisecondsSinceEpoch(startedAtMs)
        : timestamp;
    _roomName =
        await FlutterForegroundTask.getData<String>(key: _roomKey) ?? '';
    _username =
        await FlutterForegroundTask.getData<String>(key: _usernameKey) ?? '';
    _updateNotification();
  }

  @override
  void onRepeatEvent(DateTime timestamp) => _updateNotification();

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await FlutterForegroundTask.removeData(key: _startedAtKey);
    await FlutterForegroundTask.removeData(key: _roomKey);
    await FlutterForegroundTask.removeData(key: _usernameKey);
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == _endCallButtonId) {
      FlutterForegroundTask.sendDataToMain({'event': _endCallEvent});
    }
  }

  void _updateNotification() {
    final elapsed = _startedAt == null
        ? Duration.zero
        : DateTime.now().difference(_startedAt!);
    final details = <String>[
      if (_username.isNotEmpty) _username,
      if (_roomName.isNotEmpty) _roomName,
      _formatDuration(elapsed),
    ];
    unawaited(
      FlutterForegroundTask.updateService(
        notificationTitle: 'Appel en cours',
        notificationText: details.join(' • '),
      ),
    );
  }

  static String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }
}

class CallForegroundService {
  CallForegroundService._();

  static bool _initialized = false;
  static VoidCallback? _onEndCall;

  static void initialize() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: 'Appel en cours',
        channelDescription:
            'Notification affichée pendant une session d\'appel VideoLog.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
        allowAutoRestart: false,
        stopWithTask: true,
      ),
    );
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    _initialized = true;
  }

  static void setOnEndCall(VoidCallback? callback) {
    _onEndCall = callback;
  }

  static Future<void> start({
    required String roomName,
    required String username,
  }) async {
    if (!Platform.isAndroid) return;
    initialize();

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Appel en cours',
        notificationText: '$username • $roomName',
      );
      return;
    }

    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
      if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
        debugPrint('Foreground service: Notification permission denied by user');
        return;
      }
    }

    await FlutterForegroundTask.saveData(key: _roomKey, value: roomName);
    await FlutterForegroundTask.saveData(key: _usernameKey, value: username);
    await FlutterForegroundTask.saveData(
      key: _startedAtKey,
      value: DateTime.now().millisecondsSinceEpoch,
    );

    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: const [
        ForegroundServiceTypes.camera,
        ForegroundServiceTypes.microphone,
      ],
      notificationTitle: 'Appel en cours',
      notificationText: '$username • $roomName',
      notificationButtons: const [
        NotificationButton(id: _endCallButtonId, text: 'Raccrocher'),
      ],
      notificationInitialRoute: '/',
      callback: callForegroundTaskCallback,
    );

    if (result is ServiceRequestFailure) {
      debugPrint('Foreground service start failed: ${result.error}');
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    if (!await FlutterForegroundTask.isRunningService) return;
    final result = await FlutterForegroundTask.stopService();
    if (result is ServiceRequestFailure) {
      debugPrint('Foreground service stop failed: ${result.error}');
    }
  }

  static void _onTaskData(Object data) {
    if (data is Map && data['event'] == _endCallEvent) {
      _onEndCall?.call();
    }
  }
}
