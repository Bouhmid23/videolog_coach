import 'dart:ui' show Size;

/// Remet une taille d'image en portrait quand l'écran l'est.
///
/// Les capteurs Android annoncent souvent leurs dimensions en paysage
/// (640×480) alors que l'image est affichée en portrait (480×640). Comme les
/// coordonnées du coach sont des fractions, seul le ratio compte : 240×320 et
/// 360×480 donnent exactement le même résultat.
Size frameSizeForOrientation(Size size, {required bool portrait}) {
  if (!portrait) return size;
  if (size.width <= size.height) return size;
  return Size(size.height, size.width);
}

/// Ratio d'image portrait 3:4 attendu pour la vidéo locale du sportif.
const double portraitFrameRatio = 0.75;
