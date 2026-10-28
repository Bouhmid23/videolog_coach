import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/intl.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videolog_coach/core/call_foreground_service.dart';
import 'package:videolog_coach/theme.dart';
import 'package:logging/logging.dart';

import 'firebase_options.dart';
import 'router.dart';

void main() async {
  final format = DateFormat('HH:mm:ss');
  Logger.root.level = Level.FINEST;
  Logger.root.onRecord.listen((record) {
    // Le nom du logger permet de filtrer dans logcat :
    //   adb logcat -d | grep -i -E "livekit|webrtc|flutter"
    debugPrint(
      '${format.format(record.time)} [${record.level.name}] '
      '${record.loggerName}: ${record.message}',
    );
  });

  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // La session Firebase est persistée par défaut. Si l'utilisateur a décoché
  // « Se souvenir de moi », on efface la session au prochain démarrage.
  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool('remember_me') ?? true)) {
    await FirebaseAuth.instance.signOut();
  }

  FlutterForegroundTask.initCommunicationPort();
  CallForegroundService.initialize();

  await LiveKitClient.initialize(
    bypassVoiceProcessing: lkPlatformIsMobile(),
  );

  // Logs verbeux du SDK LiveKit (signal, ICE, reconnexion) dans logcat.
  if (kDebugMode) {
    setLoggingLevel(LoggerLevel.kFINEST);
  }

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
