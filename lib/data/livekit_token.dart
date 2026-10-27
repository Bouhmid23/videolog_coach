/// Réponse de `POST /token`.
class LiveKitToken {
  const LiveKitToken({
    required this.token,
    required this.url,
    this.room,
    this.identity,
  });

  final String token;
  final String url;
  final String? room;
  final String? identity;

  factory LiveKitToken.fromJson(Map<String, dynamic> json) {
    final token = json['token'];
    final url = json['url'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('Champ "token" absent ou invalide.');
    }
    if (url is! String || url.isEmpty) {
      throw const FormatException('Champ "url" absent ou invalide.');
    }
    return LiveKitToken(
      token: token,
      url: url,
      room: json['room'] as String?,
      identity: json['identity'] as String?,
    );
  }
}
