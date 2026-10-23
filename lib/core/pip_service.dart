import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PipService {
  PipService._();

  static const MethodChannel _channel = MethodChannel('videolog/pip');

  static final ValueNotifier<bool> isInPip = ValueNotifier<bool>(false);

  static bool _initialized = false;

  static bool get isAvailable => Platform.isAndroid;

  static void initialize() {
    if (_initialized || !isAvailable) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pipModeChanged') {
        isInPip.value = call.arguments == true;
      }
    });
    _initialized = true;
  }

  static Future<void> enableAutoEnter({
    int width = 9,
    int height = 16,
  }) async {
    if (!isAvailable) return;
    initialize();
    try {
      await _channel.invokeMethod<bool>('enableAutoEnter', {
        'width': width,
        'height': height,
      });
    } on PlatformException catch (error) {
      debugPrint('PiP enable failed: ${error.message}');
    } on MissingPluginException catch (error) {
      debugPrint('PiP plugin missing: ${error.message}');
    }
  }

  static Future<void> disableAutoEnter() async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod<bool>('disableAutoEnter');
    } on PlatformException catch (error) {
      debugPrint('PiP disable failed: ${error.message}');
    } on MissingPluginException catch (error) {
      debugPrint('PiP plugin missing: ${error.message}');
    }
  }

  static Future<bool> enter() async {
    if (!isAvailable) return false;
    initialize();
    try {
      return await _channel.invokeMethod<bool>('enter') ?? false;
    } on PlatformException catch (error) {
      debugPrint('PiP enter failed: ${error.message}');
      return false;
    } on MissingPluginException catch (error) {
      debugPrint('PiP plugin missing: ${error.message}');
      return false;
    }
  }
}
