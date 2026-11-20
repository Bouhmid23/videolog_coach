import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../data/account_models.dart';
import '../data/activity_models.dart';
import '../data/directory_models.dart';
import '../data/livekit_token.dart';
import '../data/mobile_room.dart';
import '../data/pmc_models.dart';
import '../data/recording_state.dart';
import '../data/room_lobby.dart';
import '../data/session_models.dart';
import '../data/training_models.dart';
import 'auth_service.dart';

part 'api/api_account.dart';
part 'api/api_directory.dart';
part 'api/api_rooms.dart';
part 'api/api_training.dart';

/// Socle de transport HTTP authentifié (Bearer Firebase ID Token) pour [ApiService].
abstract class _ApiClientBase {
  _ApiClientBase({
    http.Client? httpClient,
    AuthService? authService,
    String? baseUrl,
    this.allowInsecureLiveKit,
  }) : _httpClient = httpClient ?? http.Client(),
       _authService = authService, // ignore: prefer_initializing_formals
       _baseUrlOverride = baseUrl;

  static const Duration _timeout = Duration(seconds: 15);

  final http.Client _httpClient;
  final AuthService? _authService;
  final String? _baseUrlOverride;
  final bool? allowInsecureLiveKit;

  AuthService get _auth => _authService ?? AuthService.instance;

  String get _effectiveBaseUrl {
    final override = _baseUrlOverride?.trim();
    if (override != null && override.isNotEmpty) {
      var normalized = override;
      while (normalized.endsWith('/')) {
        normalized = normalized.substring(0, normalized.length - 1);
      }
      return normalized;
    }
    return AppConfig.apiBaseUrl;
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    bool requiresAuth = true,
    bool retriedAfterUnauthorized = false,
  }) async {
    final decoded = await _sendRaw(
      method,
      path,
      query: query,
      body: body,
      requiresAuth: requiresAuth,
      retriedAfterUnauthorized: retriedAfterUnauthorized,
    );
    if (decoded is! Map) {
      throw const ApiException(0, 'Réponse serveur invalide.');
    }
    final map = Map<String, dynamic>.from(decoded);
    final apiError = map['error'];
    if (apiError != null && apiError.toString().isNotEmpty) {
      throw ApiException(200, apiError.toString());
    }
    return map;
  }

  Future<List<dynamic>> _sendList(
    String method,
    String path, {
    Map<String, String>? query,
    bool requiresAuth = true,
  }) async {
    final decoded = await _sendRaw(
      method,
      path,
      query: query,
      requiresAuth: requiresAuth,
    );
    if (decoded is! List) {
      throw const ApiException(0, 'Réponse serveur invalide (liste attendue).');
    }
    return decoded;
  }

  Future<Object?> _sendRaw(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    bool requiresAuth = true,
    bool retriedAfterUnauthorized = false,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };

    if (requiresAuth) {
      final idToken = await _auth.requireIdToken(
        forceRefresh: retriedAfterUnauthorized,
      );
      headers['Authorization'] = 'Bearer $idToken';
    }

    final base = Uri.parse('$_effectiveBaseUrl$path');
    final uri = query == null ? base : base.replace(queryParameters: query);
    final isRecordingRequest = path.contains('/recording');

    if (kDebugMode) {
      debugPrint('[API] -> $method $uri');
    }

    final encodedBody = body == null ? null : jsonEncode(body);
    late final http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await _httpClient.get(uri, headers: headers).timeout(_timeout);
        case 'POST':
          response = await _httpClient
              .post(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);
        case 'PUT':
          response = await _httpClient
              .put(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);
        case 'PATCH':
          response = await _httpClient
              .patch(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);
        case 'DELETE':
          response = await _httpClient
              .delete(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);
        default:
          throw ApiException(0, 'Méthode HTTP non supportée: $method');
      }
    } on TimeoutException {
      if (kDebugMode) debugPrint('[API] TIMEOUT $method $path');
      throw const ApiException(0, 'Délai dépassé. Vérifiez votre connexion.');
    } on SocketException {
      if (kDebugMode) debugPrint('[API] SOCKET $method $path');
      throw const ApiException(
        0,
        'Réseau indisponible. Vérifiez votre connexion.',
      );
    } on http.ClientException {
      if (kDebugMode) debugPrint('[API] CLIENT $method $path');
      throw const ApiException(0, 'Connexion au serveur impossible.');
    }

    if (kDebugMode) {
      debugPrint('[API] $method $path -> HTTP ${response.statusCode}');
      if (path == '/mobile/rooms' || isRecordingRequest) {
        final raw = response.body;
        final preview = raw.length > 2000
            ? '${raw.substring(0, 2000)}… (${raw.length} caractères)'
            : raw;
        debugPrint('[API] $method $path body: $preview');
      }
    }

    if (requiresAuth &&
        response.statusCode == 401 &&
        !retriedAfterUnauthorized) {
      if (kDebugMode) {
        debugPrint(
          '[API] 401 sur $method $path -> rafraîchissement du jeton et nouvel essai',
        );
      }
      return _sendRaw(
        method,
        path,
        query: query,
        body: body,
        requiresAuth: requiresAuth,
        retriedAfterUnauthorized: true,
      );
    }

    Object? decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = null;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = _extractDetail(decoded);
      throw ApiException(
        response.statusCode,
        _messageFor(response.statusCode, detail),
        detail: detail,
      );
    }

    return decoded;
  }

  /// Télécharge une ressource binaire (ex: export `.fit`, `.zwo`, `.erg`).
  Future<Uint8List> getBytes(
    String path, {
    Map<String, String>? query,
    bool requiresAuth = true,
    bool retriedAfterUnauthorized = false,
  }) async {
    final headers = <String, String>{};
    if (requiresAuth) {
      final idToken = await _auth.requireIdToken(
        forceRefresh: retriedAfterUnauthorized,
      );
      headers['Authorization'] = 'Bearer $idToken';
    }

    final base = Uri.parse('$_effectiveBaseUrl$path');
    final uri = query == null ? base : base.replace(queryParameters: query);

    if (kDebugMode) {
      debugPrint('[API] -> GET (bytes) $uri');
    }

    late final http.Response response;
    try {
      response = await _httpClient.get(uri, headers: headers).timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(0, 'Délai dépassé. Vérifiez votre connexion.');
    } on SocketException {
      throw const ApiException(
        0,
        'Réseau indisponible. Vérifiez votre connexion.',
      );
    } on http.ClientException {
      throw const ApiException(0, 'Connexion au serveur impossible.');
    }

    if (requiresAuth &&
        response.statusCode == 401 &&
        !retriedAfterUnauthorized) {
      return getBytes(
        path,
        query: query,
        requiresAuth: requiresAuth,
        retriedAfterUnauthorized: true,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      Object? decoded;
      if (response.body.isNotEmpty) {
        try {
          decoded = jsonDecode(response.body);
        } on FormatException {
          decoded = null;
        }
      }
      final detail = _extractDetail(decoded);
      throw ApiException(
        response.statusCode,
        _messageFor(response.statusCode, detail),
        detail: detail,
      );
    }

    return response.bodyBytes;
  }

  /// Envoie un fichier en `multipart/form-data` (ex: import `.fit`, `.gpx`, `.tcx`).
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    String? filePath,
    Uint8List? fileBytes,
    String? filename,
    String fileField = 'file',
    Map<String, String>? fields,
    bool requiresAuth = true,
    bool retriedAfterUnauthorized = false,
  }) async {
    if (filePath == null && fileBytes == null) {
      throw ArgumentError('filePath ou fileBytes doit être fourni.');
    }

    final base = Uri.parse('$_effectiveBaseUrl$path');
    final request = http.MultipartRequest('POST', base);

    if (requiresAuth) {
      final idToken = await _auth.requireIdToken(
        forceRefresh: retriedAfterUnauthorized,
      );
      request.headers['Authorization'] = 'Bearer $idToken';
    }

    if (fields != null && fields.isNotEmpty) {
      request.fields.addAll(fields);
    }

    if (fileBytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          fileField,
          fileBytes,
          filename: filename ?? 'upload.bin',
        ),
      );
    } else {
      request.files.add(
        await http.MultipartFile.fromPath(
          fileField,
          filePath!,
          filename: filename,
        ),
      );
    }

    if (kDebugMode) {
      debugPrint('[API] -> POST (multipart) $base');
    }

    late final http.Response response;
    try {
      final streamed = await _httpClient.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException(0, 'Délai dépassé. Vérifiez votre connexion.');
    } on SocketException {
      throw const ApiException(
        0,
        'Réseau indisponible. Vérifiez votre connexion.',
      );
    } on http.ClientException {
      throw const ApiException(0, 'Connexion au serveur impossible.');
    }

    if (requiresAuth &&
        response.statusCode == 401 &&
        !retriedAfterUnauthorized) {
      return postMultipart(
        path,
        filePath: filePath,
        fileBytes: fileBytes,
        filename: filename,
        fileField: fileField,
        fields: fields,
        requiresAuth: requiresAuth,
        retriedAfterUnauthorized: true,
      );
    }

    Object? decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = null;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = _extractDetail(decoded);
      throw ApiException(
        response.statusCode,
        _messageFor(response.statusCode, detail),
        detail: detail,
      );
    }

    if (decoded is! Map) {
      throw const ApiException(0, 'Réponse serveur invalide.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static String? _extractDetail(Object? decoded) {
    if (decoded is! Map) return null;
    final detail = decoded['detail'] ?? decoded['error'];
    if (detail is String && detail.isNotEmpty) return detail;
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] is String) {
        return first['msg'] as String;
      }
      return first.toString();
    }
    return null;
  }

  static String _messageFor(int statusCode, String? detail) {
    switch (statusCode) {
      case 400:
        return detail ?? 'Requête refusée.';
      case 401:
        return 'Session expirée. Reconnectez-vous.';
      case 403:
        return detail ?? 'Accès refusé à cette session.';
      case 404:
        return detail ?? 'Ressource introuvable.';
      case 409:
        return detail ?? 'Une opération d\'enregistrement est déjà en cours.';
      case 410:
        return detail ?? 'Ce lien ou cette ressource n\'est plus disponible.';
      case 422:
        return detail ?? 'Données invalides.';
      case 429:
        return detail ?? 'Trop de demandes envoyées. Veuillez réessayer plus tard.';
      case 502:
        return 'Le serveur multimédia n\'a pas pu exécuter l\'opération.';
      case 503:
        return 'Service d\'authentification indisponible côté serveur.';
      default:
        return detail ?? 'Erreur API ($statusCode).';
    }
  }
}

/// Client des routes mobiles et back-office v1 Videolog.
///
/// Découpé par domaine métier :
/// - [_ApiRoomsMixin] (`api/api_rooms.dart`)
/// - [_ApiAccountMixin] (`api/api_account.dart`)
/// - [_ApiTrainingMixin] (`api/api_training.dart`)
/// - [_ApiDirectoryMixin] (`api/api_directory.dart`)
class ApiService extends _ApiClientBase
    with
        _ApiRoomsMixin,
        _ApiAccountMixin,
        _ApiTrainingMixin,
        _ApiDirectoryMixin {
  ApiService({
    super.httpClient,
    super.authService,
    super.baseUrl,
    super.allowInsecureLiveKit,
  });

  /// Instance partagée par défaut (réutilise les connexions HTTP keep-alive).
  static ApiService instance = ApiService();

  static String get baseUrl => AppConfig.apiBaseUrl;

  static Future<List<MobileRoom>> getRooms({int limit = 50}) =>
      instance.fetchRooms(limit: limit);

  static Future<RoomLobby> getRoomLobby(String roomName) =>
      instance.fetchRoomLobby(roomName);

  static Future<LiveKitToken> getLiveKitToken(String roomName) =>
      instance.fetchLiveKitToken(roomName);

  static Future<RecordingState> startRecording(
    String roomName, {
    String layout = 'grid',
  }) => instance.requestStartRecording(roomName, layout: layout);

  static Future<RecordingState> stopRecording(String roomName) =>
      instance.requestStopRecording(roomName);

  static Future<RecordingState> getRecording(String roomName) =>
      instance.fetchRecording(roomName);
}

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message, {this.detail});

  final int statusCode;
  final String message;
  final String? detail;

  bool get isUnauthorized => statusCode == 401;

  bool get isForbidden => statusCode == 403;

  bool get isNotFound => statusCode == 404;

  bool get isConflict => statusCode == 409;

  bool get isGone => statusCode == 410;

  bool get isUnprocessable => statusCode == 422;

  bool get isTooManyRequests => statusCode == 429;

  @override
  String toString() => message;
}
