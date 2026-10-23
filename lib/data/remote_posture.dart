

import 'posture_codec.dart';

/// Posture classifiée (label + confiance).
///
/// Le squelette n'est plus porté par cette classe : il est envoyé en binaire
/// via [PostureCodec] et dessiné uniquement côté web.
class RemotePosture {
  const RemotePosture({
    required this.label,
    this.confidence,
    required this.receivedAt,
  });

  final String label;
  final double? confidence;
  final DateTime receivedAt;
}
