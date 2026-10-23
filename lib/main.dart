import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/intl.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:videolog_coach/core/call_foreground_service.dart';
import 'package:videolog_coach/theme.dart';
import 'package:logging/logging.dart';

import 'router.dart';

void main() async {
  final format = DateFormat('HH:mm:ss');
  Logger.root.level = Level.FINEST;
  Logger.root.onRecord.listen((record) {
    debugPrint('${format.format(record.time)} [${record.level.name}]: ${record.message}');
  });

  WidgetsFlutterBinding.ensureInitialized();

  FlutterForegroundTask.initCommunicationPort();
  CallForegroundService.initialize();

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
      title: 'VideoLog',
      routerConfig: goRouter,
    );
  }
}
