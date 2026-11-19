import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videolog_coach/core/account_controller.dart';
import 'package:videolog_coach/core/api_service.dart';
import 'package:videolog_coach/core/auth_service.dart';
import 'package:videolog_coach/data/remote_telemetry.dart';
import 'package:videolog_coach/presentation/screens/home_shell_screen.dart';
import 'package:videolog_coach/presentation/screens/login_screen.dart';
import 'package:videolog_coach/presentation/screens/onboarding_screen.dart';
import 'package:videolog_coach/presentation/screens/verify_email_screen.dart';
import 'package:videolog_coach/presentation/widgets/data_hud.dart';
import 'package:videolog_coach/presentation/widgets/sweat_lock_overlay.dart';
import 'package:videolog_coach/presentation/widgets/wellness_checkin_sheet.dart';
import 'package:videolog_coach/theme.dart';

class _InMemoryStore implements SecureTokenStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}

class _FakeAuthService extends AuthService {
  _FakeAuthService()
    : super.forTesting(
        secureStore: _InMemoryStore(),
        tokenProvider: ({required bool forceRefresh}) async => 'jwt-test',
      );

  @override
  bool get isSignedIn => true;

  @override
  bool get isEmailVerified => true;

  @override
  String get uid => 'u-test-1';

  @override
  String? get email => 'athlete@videolog.app';

  @override
  String get displayName => 'Alice Martin';
}

Future<({AuthService auth, ApiService api, AccountController account})>
_buildShellHarness() async {
  SharedPreferences.setMockInitialValues({});
  final auth = _FakeAuthService();
  final api = ApiService(
    authService: auth,
    baseUrl: 'https://api.videolog.app',
    httpClient: MockClient((req) async {
      if (req.url.path == '/v1/me') {
        return http.Response(
          jsonEncode({
            'uid': 'u-test-1',
            'email': 'athlete@videolog.app',
            'email_verified': true,
            'needs_onboarding': false,
            'user': {
              'uid': 'u-test-1',
              'email': 'athlete@videolog.app',
              'first_name': 'Alice',
              'last_name': 'Martin',
              'health_consent': {'granted': true},
            },
            'memberships': [
              {
                'org_id': 'org-1',
                'role': 'athlete',
                'organization': {'id': 'org-1', 'type': 'club', 'name': 'VC Lyon'},
              },
            ],
          }),
          200,
        );
      }
      if (req.url.path == '/v1/me/notifications') {
        return http.Response(
          jsonEncode({'unread_count': 3, 'items': []}),
          200,
        );
      }
      if (req.url.path == '/v1/me/invitations') {
        return http.Response(jsonEncode({'items': []}), 200);
      }
      return http.Response('{}', 200);
    }),
  );

  final account = AccountController.forTesting(
    authService: auth,
    apiService: api,
  );
  await account.refresh(syncAthleteProfile: false);
  return (auth: auth, api: api, account: account);
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Phase 2.1 — Navigation adaptative, Header unifié & AccountSheet', () {
    testWidgets('HomeShellScreen utilise NavigationBar < 600dp et NavigationRail >= 600dp', (tester) async {
      final harness = (await tester.runAsync(_buildShellHarness))!;
      final builtTabs = <int>{};

      Widget buildShell() => Builder(
        builder: (context) => Theme(
          data: const LiveKitTheme().buildThemeData(context),
          child: HomeShellScreen(
            apiService: harness.api,
            accountController: harness.account,
            authService: harness.auth,
            tabsOverride: List.generate(4, (i) {
              return Builder(
                builder: (_) {
                  builtTabs.add(i);
                  return Center(child: Text('Tab Content $i'));
                },
              );
            }),
          ),
        ),
      );

      // Mobile viewport (< 600dp)
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(home: buildShell()));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('VC Lyon'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // badge notifications
      expect(builtTabs, {0}); // montage paresseux

      // Navigation vers Activités (onglet 2)
      await tester.tap(find.text('Activités'));
      await tester.pumpAndSettle();
      expect(builtTabs, {0, 2});

      // Tablet viewport (>= 600dp)
      await tester.binding.setSurfaceSize(const Size(768, 900));
      await tester.pumpWidget(MaterialApp(home: buildShell()));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('Header unifié ouvre AccountSettingsSheet avec Seuils FTP/LTHR et Profil RGPD', (tester) async {
      final harness = (await tester.runAsync(_buildShellHarness))!;
      await tester.binding.setSurfaceSize(const Size(420, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Theme(
              data: const LiveKitTheme().buildThemeData(context),
              child: HomeShellScreen(
                apiService: harness.api,
                accountController: harness.account,
                authService: harness.auth,
                tabsOverride: const [
                  SizedBox(),
                  SizedBox(),
                  SizedBox(),
                  SizedBox(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Compte & Réglages'));
      await tester.pumpAndSettle();

      expect(find.text('Alice Martin'), findsOneWidget);
      expect(find.text('Profil sportif & RGPD'), findsOneWidget);
      expect(find.text('Seuils d\'entraînement (FTP / LTHR)'), findsOneWidget);
      expect(find.text('Mes clubs, coachs & invitations'), findsOneWidget);
      expect(find.text('Se déconnecter'), findsOneWidget);
    });

    testWidgets('HomeShellScreen ne lève pas setState during build lors du montage paresseux avec AccountController non chargé', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final auth = _FakeAuthService();
      final api = ApiService(
        authService: auth,
        baseUrl: 'https://api.videolog.app',
        httpClient: MockClient((req) async {
          if (req.url.path == '/v1/me') {
            return http.Response(
              jsonEncode({
                'uid': 'u-test-1',
                'email': 'athlete@videolog.app',
                'email_verified': true,
                'needs_onboarding': false,
                'user': {
                  'uid': 'u-test-1',
                  'email': 'athlete@videolog.app',
                  'first_name': 'Alice',
                  'last_name': 'Martin',
                  'health_consent': {'granted': true},
                },
                'memberships': [
                  {
                    'org_id': 'org-1',
                    'role': 'athlete',
                    'organization': {'id': 'org-1', 'type': 'club', 'name': 'VC Lyon'},
                  },
                ],
              }),
              200,
            );
          }
          if (req.url.path == '/v1/me/notifications') {
            return http.Response(jsonEncode({'unread_count': 1, 'items': []}), 200);
          }
          if (req.url.path == '/v1/me/invitations') {
            return http.Response(jsonEncode({'items': []}), 200);
          }
          if (req.url.path.endsWith('/calendar')) {
            return http.Response(
              jsonEncode({'planned_workouts': [], 'wellness': [], 'goals': []}),
              200,
            );
          }
          if (req.url.path.endsWith('/activities')) {
            return http.Response(jsonEncode({'items': []}), 200);
          }
          return http.Response('{}', 200);
        }),
      );
      final unloadedAccount = AccountController.forTesting(
        authService: auth,
        apiService: api,
      );

      await tester.binding.setSurfaceSize(const Size(420, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: ListenableBuilder(
            listenable: unloadedAccount,
            builder: (context, _) => Theme(
              data: const LiveKitTheme().buildThemeData(context),
              child: HomeShellScreen(
                apiService: api,
                accountController: unloadedAccount,
                authService: auth,
                now: DateTime(2026, 11, 18),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('VC Lyon'), findsOneWidget);

      // Force le montage paresseux de CalendarScreen alors que l'état compte vient d'être réinitialisé
      unloadedAccount.clear();
      await tester.tap(find.text('Aujourd\'hui'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Activités'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 2.2 — Auth, Mot de passe oublié, VerifyEmail & Onboarding', () {
    testWidgets('LoginScreen valide le formulaire, affiche SVG Google, Apple Sign-In et Mot de passe oublié', (tester) async {
      final harness = (await tester.runAsync(_buildShellHarness))!;
      String? resetEmailSent;
      var appleTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Theme(
              data: const LiveKitTheme().buildThemeData(context),
              child: LoginScreen(
                authService: harness.auth,
                accountController: harness.account,
                showAppleSignIn: true,
                onSendPasswordReset: (email) async {
                  resetEmailSent = email;
                },
                onSignInWithApple: () async {
                  appleTapped = true;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.text('Continuer avec Apple'), findsOneWidget);

      // Validation inline sur champs vides
      await tester.ensureVisible(find.text('Se connecter'));
      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();
      expect(find.text('Adresse e-mail requise.'), findsOneWidget);
      expect(find.text('Mot de passe requis.'), findsOneWidget);

      // Pré-remplissage email + mot de passe oublié
      await tester.ensureVisible(find.widgetWithText(TextFormField, 'Email'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'coach@videolog.app',
      );
      await tester.ensureVisible(find.text('Mot de passe oublié ?'));
      await tester.tap(find.text('Mot de passe oublié ?'));
      await tester.pumpAndSettle();

      expect(find.text('Réinitialiser le mot de passe'), findsOneWidget);
      await tester.tap(find.text('Envoyer le lien'));
      await tester.pumpAndSettle();

      expect(resetEmailSent, 'coach@videolog.app');

      // Mode création : indicateur robustesse mot de passe
      await tester.ensureVisible(find.text('Créer un compte'));
      await tester.tap(find.text('Créer un compte'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(TextFormField, 'Mot de passe'),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mot de passe'),
        'Abc123456!',
      );
      await tester.pump();
      expect(find.text('Robuste'), findsOneWidget);

      // Apple Sign-In callback exécuté
      await tester.ensureVisible(find.text('Continuer avec Apple'));
      await tester.tap(find.text('Continuer avec Apple'));
      await tester.pump();
      expect(appleTapped, isTrue);
    });

    testWidgets('VerifyEmailScreen applique le cooldown de 60s et vérifie au retour en premier plan', (tester) async {
      var reloadCalls = 0;
      var resendCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Theme(
              data: const LiveKitTheme().buildThemeData(context),
              child: VerifyEmailScreen(
                email: 'athlete@videolog.app',
                onReloadAndRefresh: () async {
                  reloadCalls++;
                  return false;
                },
                onSendEmailVerification: () async {
                  resendCalls++;
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Renvoyer l\'e-mail de vérification'));
      await tester.pumpAndSettle();
      expect(resendCalls, 1);
      expect(find.textContaining('60s'), findsOneWidget);

      // Simule reprise d'application depuis la boîte mail
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(reloadCalls, 1);
    });

    testWidgets('OnboardingScreen en 2 étapes valide l étape 1 avant de passer à l étape 2', (tester) async {
      final harness = (await tester.runAsync(_buildShellHarness))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Theme(
              data: const LiveKitTheme().buildThemeData(context),
              child: OnboardingScreen(
                apiService: harness.api,
                accountController: harness.account,
                emailVerifiedOverride: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Étape 1 / 2'), findsOneWidget);
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      expect(find.text('Au moins 2 caractères requis.'), findsOneWidget);
      expect(find.text('Étape 1 / 2'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom du club / organisation *'),
        'VC Lyon',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Prénom *'),
        'Alice',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom *'),
        'Martin',
      );
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();

      expect(find.text('Étape 2 / 2'), findsOneWidget);
      expect(find.text('Créer mon espace'), findsOneWidget);
    });
  });

  group('Phase 2.3 — Accessibilité Semantics & cibles >= 48dp', () {
    testWidgets('HeartRateHudGauge, DataHud et SweatLockOverlay exposent leurs Semantics', (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Column(
                    children: [
                      const HeartRateHudGauge(bpm: 162, maxHr: 190),
                      DataHud(
                        telemetry: RemoteTelemetry(
                          heartRate: 162,
                          speed: 34.5,
                          powerWatts: 280,
                          receivedAt: DateTime(2026, 11, 18),
                        ),
                      ),
                    ],
                  ),
                  const SweatLockOverlay(onUnlock: _noop),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.bySemanticsLabel(RegExp(r'Fréquence cardiaque 162.*zone Z4')),
          findsWidgets,
        );
        expect(find.bySemanticsLabel('Vitesse 34.5 km/h'), findsOneWidget);
        expect(find.bySemanticsLabel('Puissance 280 W'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Écran verrouillé contre la sueur'),
          findsOneWidget,
        );
      } finally {
        semanticsHandle.dispose();
      }
    });

    testWidgets('WellnessCheckinSheet expose des cibles >= 48dp et des labels sémantiques', (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: WellnessCheckinSheet(
                orgId: 'org-1',
                uid: 'u-1',
                hasHealthConsent: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final target = find.bySemanticsLabel('Qualité du sommeil : 4 sur 5');
        expect(target, findsOneWidget);
        final size = tester.getSize(target);
        expect(size.height, greaterThanOrEqualTo(48));
      } finally {
        semanticsHandle.dispose();
      }
    });
  });
}

void _noop() {}
