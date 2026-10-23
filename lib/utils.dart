import 'dart:async';

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