import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/auth_service.dart';
import 'data/mobile_room.dart';
import 'presentation/screens/connect.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/room.dart';
import 'presentation/screens/rooms_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final goRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/login',
  refreshListenable: AuthService.instance,
  redirect: (context, state) {
    final signedIn = AuthService.instance.isSignedIn;
    final atLogin = state.matchedLocation == '/login';
    if (!signedIn) return atLogin ? null : '/login';
    if (atLogin) return '/rooms';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/rooms', builder: (context, state) => const RoomsScreen()),
    GoRoute(
      path: '/connect/:roomName',
      builder: (context, state) {
        final extra = state.extra;
        final room = extra is MobileRoom ? extra : null;
        return ConnectPage(
          roomName: state.pathParameters['roomName']!,
          canControlRecording: room?.canControlRecording ?? extra == true,
          room: room,
        );
      },
    ),
    // La session est empilée au-dessus de l'écran de connexion, puis ce
    // dernier est remplacé par la room (retour direct vers /rooms).
    GoRoute(
      path: '/room',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final args = state.extra as RoomRouteArgs;
        return RoomPage(
          args.room,
          args.listener,
          role: args.role,
          roomName: args.roomName,
          canControlRecording: args.canControlRecording,
          fastConnection: true,
        );
      },
    ),
  ],
);
