import 'dart:convert';

import 'package:livekit_client/livekit_client.dart';

import '../core/auth_service.dart';
import '../utils.dart';

/// Clé utilisée dans les metadata / attributes LiveKit pour partager le nom
/// affiché entre clients.
const String kDisplayNameKey = 'display_name';

/// Longueur maximale d'un UID affiché tel quel. Au-delà, on tronque pour
/// éviter d'afficher un identifiant Firebase de 28 caractères dans la vidéo.
const int _kMaxIdentityLength = 16;

/// Nom lisible d'un participant.
///
/// L'identité LiveKit est le UID Firebase et le token serveur ne porte pas de
/// nom : on regarde donc, dans l'ordre :
/// 1. le compte Firebase local (participant local) ;
/// 2. les metadata LiveKit publiées par le client ([kDisplayNameKey]) ;
/// 3. les attributes LiveKit (`display_name`) ;
/// 4. le nom fourni par LiveKit, s'il diffère de l'identité ;
/// 5. l'identité, tronquée en dernier recours.
String displayNameForParticipant(Participant participant) {
  if (participant is LocalParticipant) {
    final localName = AuthService.instance.displayName.trim();
    if (localName.isNotEmpty) return localName;
  }

  final metadataName = displayNameFromMetadata(participant.metadata);
  if (metadataName != null) return metadataName;

  final attributeName = participant.attributes[kDisplayNameKey]?.trim();
  if (attributeName != null && attributeName.isNotEmpty) {
    return attributeName;
  }

  final liveKitName = participant.name.trim();
  if (liveKitName.isNotEmpty && liveKitName != participant.identity) {
    return displayNameForIdentity(liveKitName);
  }

  return _shortIdentity(displayNameForIdentity(participant.identity));
}

/// Payload JSON publié dans les metadata LiveKit du participant local.
String buildDisplayNameMetadata(String displayName) =>
    jsonEncode({kDisplayNameKey: displayName});

/// Extrait un nom depuis les metadata LiveKit.
///
/// Accepte un objet JSON (`{"display_name": "..."}`) ou, par tolérance, une
/// chaîne brute qui n'est pas du JSON.
String? displayNameFromMetadata(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;

  if (value.startsWith('{')) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        for (final key in const ['display_name', 'displayName', 'name']) {
          final candidate = decoded[key];
          if (candidate is String && candidate.trim().isNotEmpty) {
            return candidate.trim();
          }
        }
      }
    } catch (_) {
      // Metadata illisible : on ignore.
    }
    return null;
  }

  // Metadata textuelles simples (autres clients).
  return value;
}

String _shortIdentity(String value) {
  if (value.length <= _kMaxIdentityLength) return value;
  return '${value.substring(0, 8)}…';
}
