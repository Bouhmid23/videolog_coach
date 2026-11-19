import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/account_controller.dart';
import 'core/auth_service.dart';
import 'data/directory_models.dart';
import 'data/mobile_room.dart';
import 'presentation/screens/activity_detail_screen.dart';
import 'presentation/screens/connect.dart';
import 'presentation/screens/directory_organization_detail_screen.dart';
import 'presentation/screens/directory_screen.dart';
import 'presentation/screens/home_shell_screen.dart';
import 'presentation/screens/invitation_screen.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/screens/room.dart';
import 'presentation/screens/session_replay_screen.dart';
import 'presentation/screens/verify_email_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final _rootNavigatorKey = rootNavigatorKey;

final goRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/login',
  refreshListenable: Listenable.merge([
    AuthService.instance,
    AccountController.instance,
  ]),
  redirect: (context, state) {
    final location = state.matchedLocation;
    final atLogin = location == '/login';
    final atInvite = location.startsWith('/invite/');
    final atOnboarding = location == '/onboarding';
    final atVerifyEmail = location == '/verify-email';
    final atDirectory =
        location == '/directory' || location.startsWith('/directory/');

    // Normalisation des deep links natifs (ex: videolog://invite/<token>, /invite?token=...)
    if (!atInvite) {
      final inviteTokenFromUri = AccountController.extractInviteToken(
        state.uri.toString(),
      );
      if (inviteTokenFromUri != null &&
          inviteTokenFromUri.isNotEmpty &&
          inviteTokenFromUri != 'manual') {
        AccountController.instance.setPendingInviteToken(inviteTokenFromUri);
        return '/invite/${Uri.encodeComponent(inviteTokenFromUri)}';
      }
    }

    final signedIn = AuthService.instance.isSignedIn;

    if (!signedIn) {
      return (atLogin || atInvite) ? null : '/login';
    }

    final pendingInvite = AccountController.instance.pendingInviteToken;
    if (pendingInvite != null && pendingInvite.isNotEmpty && !atInvite) {
      return '/invite/${Uri.encodeComponent(pendingInvite)}';
    }

    final accountLoaded = AccountController.instance.hasLoaded;
    final needsOnboarding = AccountController.instance.needsOnboarding;

    if (atLogin) {
      if (accountLoaded && needsOnboarding) return '/onboarding';
      return '/rooms';
    }

    if (accountLoaded &&
        needsOnboarding &&
        !atOnboarding &&
        !atVerifyEmail &&
        !atInvite &&
        !atDirectory) {
      return '/onboarding';
    }

    if (accountLoaded && !needsOnboarding && atOnboarding) {
      return '/rooms';
    }

    if (location == '/room' && state.extra is! RoomRouteArgs) {
      return '/rooms';
    }
    return null;
  },
  onException: (context, state, router) {
    final token = AccountController.extractInviteToken(state.uri.toString());
    if (token != null && token.isNotEmpty) {
      AccountController.instance.setPendingInviteToken(token);
      router.go('/invite/${Uri.encodeComponent(token)}');
      return;
    }
    router.go(AuthService.instance.isSignedIn ? '/rooms' : '/login');
  },
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/verify-email',
      builder: (context, state) => const VerifyEmailScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/directory',
      builder: (context, state) {
        final tab = state.uri.queryParameters['tab'];
        return DirectoryScreen(
          initialTabIndex: tab == 'requests' ? 1 : 0,
        );
      },
    ),
    GoRoute(
      path: '/directory/:orgId',
      builder: (context, state) {
        final extra = state.extra;
        return DirectoryOrganizationDetailScreen(
          orgId: state.pathParameters['orgId']!,
          initialOrganization:
              extra is DirectoryOrganization ? extra : null,
        );
      },
    ),
    GoRoute(
      path: '/invite/:token',
      builder: (context, state) => InvitationScreen(
        initialToken: state.pathParameters['token'] ?? 'manual',
      ),
    ),
    GoRoute(
      path: '/rooms',
      builder: (context, state) => const HomeShellScreen(),
    ),
    GoRoute(
      path: '/sessions/:orgId/:roomName',
      builder: (context, state) => SessionReplayScreen(
        orgId: state.pathParameters['orgId']!,
        roomName: state.pathParameters['roomName']!,
      ),
    ),
    GoRoute(
      path: '/activities/:orgId/:activityId',
      builder: (context, state) => ActivityDetailScreen(
        orgId: state.pathParameters['orgId']!,
        activityId: state.pathParameters['activityId']!,
      ),
    ),
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
        final extra = state.extra;
        if (extra is! RoomRouteArgs) {
          return const HomeShellScreen(initialIndex: 3);
        }
        return RoomPage(
          extra.room,
          extra.listener,
          role: extra.role,
          roomName: extra.roomName,
          canControlRecording: extra.canControlRecording,
          knownParticipantNames: extra.knownParticipantNames,
          fastConnection: true,
        );
      },
    ),
  ],
);
