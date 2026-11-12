import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import '../data/livekit_token.dart';
import '../data/mobile_room.dart';
import '../data/recording_state.dart';
import 'auth_service.dart';

/// Client des routes mobiles Videolog.
///
/// Toutes les requêtes portent l'ID token Firebase courant en Bearer. Aucun
/// secret LiveKit, MinIO ou Firebase Admin n'est présent côté application.
class ApiService {
  ApiService({http.Client? httpClient, AuthService? authService})
    : _httpClient = httpClient ?? http.Client(),
      _authService = authService; // ignore: prefer_initializing_formals

  /// Instance partagée par défaut (réutilise les connexions HTTP keep-alive).
  static ApiService instance = ApiService();

  static const String baseUrl = 'https://api.videolog.app';
  static const Duration _timeout = Duration(seconds: 15);

  final http.Client _httpClient;
  final AuthService? _authService;

  AuthService get _auth => _authService ?? AuthService.instance;

  static Future<List<MobileRoom>> getRooms({int limit = 50}) =>
      instance.fetchRooms(limit: limit);

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

  Future<List<MobileRoom>> fetchRooms({int limit = 50}) async {
    final body = await _send(
      'GET',
      '/mobile/rooms',
      query: {'limit': limit.clamp(1, 100).toString()},
    );
    final rooms = body['rooms'];
    if (rooms is! List) {
      throw const ApiException(0, 'Réponse des rooms invalide.');
    }
    final parsed = rooms
        .whereType<Map>()
        .map((item) => MobileRoom.fromJson(Map<String, dynamic>.from(item)))
        .where((room) => room.name.isNotEmpty)
        .toList();
    if (kDebugMode) {
      debugPrint(
        '[API] GET /mobile/rooms -> ${rooms.length} élément(s) reçu(s), '
        '${parsed.length} room(s) valide(s)',
      );
    }
    if (rooms.isNotEmpty && parsed.isEmpty) {
      throw const ApiException(
        0,
        'Réponse des rooms invalide : champs manquants.',
      );
    }
    return parsed;
  }

  Future<LiveKitToken> fetchLiveKitToken(String roomName) async {
    final body = await _send('POST', '/token', body: {'room': roomName});
    final LiveKitToken token;
    try {
      token = LiveKitToken.fromJson(body);
    } on FormatException catch (error) {
      throw ApiException(0, error.message);
    }
    final url = Uri.tryParse(token.url);
    if (url == null || url.scheme != 'wss' || url.host.isEmpty) {
      throw const ApiException(
        0,
        'URL LiveKit invalide dans la réponse token.',
      );
    }
    return token;
  }

  Future<RecordingState> requestStartRecording(
    String roomName, {
    String layout = 'grid',
  }) async {
    final body = await _send(
      'POST',
      '/mobile/rooms/${Uri.encodeComponent(roomName)}/recording/start',
      query: {'layout': layout},
    );
    return _recordingFrom(body, roomName);
  }

  Future<RecordingState> requestStopRecording(String roomName) async {
    final body = await _send(
      'POST',
      '/mobile/rooms/${Uri.encodeComponent(roomName)}/recording/stop',
    );
    return _recordingFrom(body, roomName);
  }

  Future<RecordingState> fetchRecording(String roomName) async {
    final body = await _send(
      'GET',
      '/mobile/rooms/${Uri.encodeComponent(roomName)}/recording',
    );
    return _recordingFrom(body, roomName);
  }

  static RecordingState _recordingFrom(
    Map<String, dynamic> body,
    String fallbackRoomName,
  ) {
    final normalized = Map<String, dynamic>.from(body);
    if ((normalized['room_name'] as String?)?.isEmpty ?? true) {
      normalized['room_name'] = fallbackRoomName;
    }
    return RecordingState.fromJson(normalized);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    bool retriedAfterUnauthorized = false,
  }) async {
    final idToken = await _auth.requireIdToken(
      forceRefresh: retriedAfterUnauthorized,
    );
    final base = Uri.parse('$baseUrl$path');
    final uri = query == null ? base : base.replace(queryParameters: query);
    final headers = <String, String>{
      'Authorization': 'Bearer $idToken',
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };
    final isRecordingRequest = path.contains('/recording');

    if (kDebugMode) {
      debugPrint('[API] -> $method $uri');
    }

    late final http.Response response;
    try {
      if (method == 'GET') {
        response = await _httpClient.get(uri, headers: headers).timeout(_timeout);
      } else {
        response = await _httpClient
            .post(
              uri,
              headers: headers,
              body: body == null ? null : jsonEncode(body),
            )
            .timeout(_timeout);
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

    if (response.statusCode == 401 && !retriedAfterUnauthorized) {
      if (kDebugMode) {
        debugPrint('[API] 401 sur $method $path -> rafraîchissement du jeton et nouvel essai');
      }
      return _send(
        method,
        path,
        query: query,
        body: body,
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
      throw ApiException(response.statusCode, 'Réponse serveur invalide.');
    }
    final map = Map<String, dynamic>.from(decoded);
    final apiError = map['error'];
    if (apiError != null && apiError.toString().isNotEmpty) {
      throw ApiException(response.statusCode, apiError.toString());
    }
    return map;
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
      case 401:
        return 'Session expirée. Reconnectez-vous.';
      case 403:
        return 'Accès refusé à cette session.';
      case 404:
        return 'Session introuvable.';
      case 409:
        return detail ?? 'Une opération d\'enregistrement est déjà en cours.';
      case 422:
        return 'Requête invalide.';
      case 502:
        return 'Le serveur multimédia n\'a pas pu exécuter l\'opération.';
      case 503:
        return 'Service d\'authentification indisponible côté serveur.';
      default:
        return detail ?? 'Erreur API ($statusCode).';
    }
  }
}

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message, {this.detail});

  final int statusCode;
  final String message;
  final String? detail;

  bool get isUnauthorized => statusCode == 401;

  bool get isForbidden => statusCode == 403;

  bool get isConflict => statusCode == 409;

  @override
  String toString() => message;
}
