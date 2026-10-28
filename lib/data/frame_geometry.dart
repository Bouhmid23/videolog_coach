import 'dart:ui';

/// Oriente la taille d'une image caméra pour qu'elle ait le même sens (portrait ou paysage)
/// que l'écran qui l'affiche.
///
/// LiveKit annonce toujours 640×480 (paysage) pour les dimensions publiées, alors que
/// l'image réellement affichée et analysée est en portrait (480×640, 240×320...). Projeter
/// une position normalisée avec le cadre paysage fausse le recadrage `cover` : le centre reste
/// juste mais les bords s'écartent (environ 38 % de la largeur d'un écran 411×890 à x = 0,2 ou 0,8).
Size orientFrameToScreen(Size frame, {required bool portraitScreen}) {
  if (frame.isEmpty) return frame;
  final framePortrait = frame.height > frame.width;
  final frameLandscape = frame.width > frame.height;
  if (portraitScreen && frameLandscape) return Size(frame.height, frame.width);
  if (!portraitScreen && framePortrait) return Size(frame.height, frame.width);
  return frame;
}
