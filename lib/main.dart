import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/intl.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:videolog_coach/core/account_controller.dart';
import 'package:videolog_coach/core/auth_service.dart';
import 'package:videolog_coach/core/call_foreground_service.dart';
import 'package:videolog_coach/core/thermal_service.dart';
import 'package:videolog_coach/theme.dart';
import 'package:logging/logging.dart';

import 'app_config.dart';
import 'firebase_options.dart';
import 'router.dart';

void main() async {
  if (kReleaseMode) {
    Logger.root.level = Level.WARNING;
  } else {
    final format = DateFormat('HH:mm:ss');
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint('${format.format(record.time)} [${record.level.name}]: ${record.message}');
    });
    debugPrint(
      '[AppConfig] env=${AppConfig.environmentLabel} | api=${AppConfig.apiBaseUrl}',
    );
  }

  WidgetsFlutterBinding.ensureInitialized();

  // Active l'affichage bord-à-bord (Android 15–17 / iOS) avec icônes claires sur fond sombre
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Migre les anciens tokens / préférences vers FlutterSecureStorage et applique « Se souvenir de moi ».
  await AuthService.instance.enforceRememberMePolicyOnStartup();
  if (AuthService.instance.isSignedIn) {
    unawaited(AccountController.instance.refresh());
  }

  FlutterForegroundTask.initCommunicationPort();
  CallForegroundService.initialize();
  await ThermalService.instance.initialize(navigatorKey: rootNavigatorKey);

  await LiveKitClient.initialize(
    bypassVoiceProcessing: lkPlatformIsMobile(),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: LiveKitTheme().buildThemeData(context),
      title: 'VideoLog OnAir',
      routerConfig: goRouter,
    );
  }
}
