import 'dart:async';

import 'package:livekit_client/livekit_client.dart';

FutureOr<void> Function()? onWindowShouldClose;

/// Séparateur entre le nom affiché et le suffixe d'unicité de l'identité.
const String kIdentitySuffixSeparator = '#';

/// Retire le suffixe d'unicité ajouté à l'identité LiveKit pour l'affichage.
String displayNameForIdentity(String value) {
  final separatorIndex = value.lastIndexOf(kIdentitySuffixSeparator);
  if (separatorIndex <= 0) return value;
  final suffix = value.substring(separatorIndex + 1);
  if (suffix.length > 8) return value;
  return value.substring(0, separatorIndex);
}

/// Extrait l'UID Firebase de base depuis une identité LiveKit
/// (ex. `"uid123:web"` ou `"uid123#a1b2"` -> `"uid123"`).
String baseUidForIdentity(String identity) {
  final stripped = displayNameForIdentity(identity.trim()).trim();
  if (stripped.isEmpty) return '';
  return stripped.split(':').first.trim();
}

/// Indique si l'identité LiveKit correspond à une session ouverte depuis le Web.
bool isWebParticipantIdentity(String identity) =>
    identity.trim().endsWith(':web');

/// Résout le nom d'affichage humain à partir d'une identité LiveKit et d'un nom.
///
/// Priorité :
/// 1. [name] (issu de `participant.name`) s'il est non vide et différent de l'UID brut.
/// 2. [fallbackName] (ex. nom du profil local ou d'un coach connu) s'il est non vide
///    et différent de l'UID brut.
/// 3. [name] nettoyé s'il est non vide, sinon l'UID de base sans suffixe `:web`/`#...`.
String displayNameFromIdentityAndName({
  required String identity,
  String? name,
  String? fallbackName,
}) {
  final trimmedIdentity = identity.trim();
  final baseUid = baseUidForIdentity(trimmedIdentity);

  final cleanedName = displayNameForIdentity((name ?? '').trim()).trim();
  if (cleanedName.isNotEmpty &&
      cleanedName != trimmedIdentity &&
      cleanedName != baseUid) {
    return cleanedName;
  }

  final cleanedFallback = (fallbackName ?? '').trim();
  if (cleanedFallback.isNotEmpty &&
      cleanedFallback != trimmedIdentity &&
      cleanedFallback != baseUid) {
    return cleanedFallback;
  }

  if (cleanedName.isNotEmpty) return cleanedName;
  if (baseUid.isNotEmpty) return baseUid;
  return displayNameForIdentity(trimmedIdentity);
}

/// Résout le nom lisible d'un participant LiveKit tout en laissant
/// `participant.identity` intact comme clé technique.
String displayNameForParticipant(
  Participant participant, {
  String? fallbackName,
}) {
  return displayNameFromIdentityAndName(
    identity: participant.identity,
    name: participant.name,
    fallbackName: fallbackName,
  );
}