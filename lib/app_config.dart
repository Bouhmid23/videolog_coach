import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kReleaseMode, visibleForTesting;

/// Environnements disponibles pour l'application Videolog.
enum AppEnvironment {
  /// Backend exécuté en local sur votre poste / réseau local.
  local,

  /// Backend déployé en production (`https://api.videolog.app`).
  prod,
}

/// Configuration centrale des endpoints de l'application.
///
/// En mode **debug / profile**, l'environnement par défaut est [AppEnvironment.local].
/// En mode **release** (`kReleaseMode`), l'environnement bascule automatiquement sur
/// [AppEnvironment.prod] sauf surcharge explicite via `--dart-define=APP_ENV=local`.
///
/// Vous pouvez aussi surcharger sans modifier ce fichier via `--dart-define` :
/// - `flutter run --dart-define=APP_ENV=local`
/// - `flutter run --dart-define=APP_ENV=prod`
/// - `flutter run --dart-define=APP_ENV=local --dart-define=API_BASE_URL=http://192.168.1.25:8000`
class AppConfig {
  const AppConfig._();

  // ===========================================================================
  // BASCULE RAPIDE LOCAL <-> PROD
  // ===========================================================================

  /// Environnement actif par défaut lorsque `--dart-define=APP_ENV` n'est pas fourni.
  /// En build release (`kReleaseMode`), pointe toujours sur [AppEnvironment.prod] par sécurité.
  static AppEnvironment get defaultEnvironment =>
      kReleaseMode ? AppEnvironment.prod : AppEnvironment.local;

  // ===========================================================================
  // ADRESSES DES SERVEURS
  // ===========================================================================

  /// Adresse du backend déployé en production.
  static const String prodApiBaseUrl = 'https://api.videolog.app';

  /// Adresse du backend local pour l'émulateur Android (`10.0.2.2` -> localhost du PC).
  /// Sur téléphone Android physique en Wi-Fi, remplacez par l'IP locale du PC
  /// (ex: `http://192.168.1.42:8000`) ou utilisez `adb reverse tcp:8000 tcp:8000`
  /// avec `http://127.0.0.1:8000`.
  static const String localAndroidApiBaseUrl = 'http://127.0.0.1:8001';

  /// Adresse du backend local pour le simulateur iOS.
  /// Sur iPhone physique en Wi-Fi, remplacez par l'IP locale du PC
  /// (ex: `http://192.168.1.42:8000`).
  static const String localIosApiBaseUrl = 'http://192.168.1.5:8001';

  /// Adresse du backend local pour les autres plateformes (macOS, Linux, Windows, Web).
  static const String localOtherApiBaseUrl = 'http://192.168.1.5:8001';

  /// Surcharge optionnelle de l'URL LiveKit en mode local (ex: `ws://10.0.2.2:7880`).
  /// Laisser vide (`''`) pour utiliser directement l'URL renvoyée par `POST /token`.
  static const String localLiveKitUrlOverride = 'ws://127.0.0.1:7880';

  // ===========================================================================
  // SURCHARGES COMPILE-TIME (--dart-define)
  // ===========================================================================

  static const String _envDefine = String.fromEnvironment(
    'APP_ENV',
    defaultValue: '',
  );
  static const String _apiBaseUrlDefine = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );
  static const String _liveKitUrlDefine = String.fromEnvironment(
    'LIVEKIT_URL',
    defaultValue: '',
  );

  // ===========================================================================
  // ACCESSEURS ACTIFS
  // ===========================================================================

  /// Environnement effectif après application éventuelle de `--dart-define=APP_ENV`.
  static AppEnvironment get environment => resolveEnvironment(_envDefine);

  static bool get isLocal => environment == AppEnvironment.local;

  static bool get isProd => environment == AppEnvironment.prod;

  /// URL de base de l'API HTTP (toujours sans `/` final).
  static String get apiBaseUrl => resolveApiBaseUrl(
    environment: environment,
    platform: defaultTargetPlatform,
    overrideUrl: _apiBaseUrlDefine,
  );

  /// Surcharge optionnelle de l'URL WebSocket LiveKit (vide si non définie).
  static String get liveKitUrlOverride => resolveLiveKitUrlOverride(
    environment: environment,
    overrideUrl: _liveKitUrlDefine,
  );

  /// Indique si les protocoles non chiffrés (`http://`, `ws://`) sont autorisés.
  static bool get allowInsecureProtocols =>
      isLocal || apiBaseUrl.toLowerCase().startsWith('http://');

  /// Libellé court de l'environnement actif (`LOCAL` ou `PROD`).
  static String get environmentLabel => isLocal ? 'LOCAL' : 'PROD';

  @visibleForTesting
  static AppEnvironment resolveEnvironment(
    String envName, {
    bool isReleaseMode = kReleaseMode,
  }) {
    switch (envName.trim().toLowerCase()) {
      case 'local':
      case 'dev':
      case 'development':
        return AppEnvironment.local;
      case 'prod':
      case 'production':
        return AppEnvironment.prod;
      default:
        return isReleaseMode ? AppEnvironment.prod : defaultEnvironment;
    }
  }

  @visibleForTesting
  static String resolveApiBaseUrl({
    required AppEnvironment environment,
    required TargetPlatform platform,
    String overrideUrl = '',
  }) {
    final trimmedOverride = overrideUrl.trim();
    if (trimmedOverride.isNotEmpty) {
      return _stripTrailingSlashes(trimmedOverride);
    }

    switch (environment) {
      case AppEnvironment.prod:
        return _stripTrailingSlashes(prodApiBaseUrl);
      case AppEnvironment.local:
        switch (platform) {
          case TargetPlatform.android:
            return _stripTrailingSlashes(localAndroidApiBaseUrl);
          case TargetPlatform.iOS:
            return _stripTrailingSlashes(localIosApiBaseUrl);
          default:
            return _stripTrailingSlashes(localOtherApiBaseUrl);
        }
    }
  }

  @visibleForTesting
  static String resolveLiveKitUrlOverride({
    required AppEnvironment environment,
    String overrideUrl = '',
  }) {
    final trimmedOverride = overrideUrl.trim();
    if (trimmedOverride.isNotEmpty) {
      return trimmedOverride;
    }
    if (environment == AppEnvironment.local) {
      return localLiveKitUrlOverride.trim();
    }
    return '';
  }

  static String _stripTrailingSlashes(String url) {
    var result = url.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
