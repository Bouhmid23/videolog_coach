# Amélioration de l'UI et de l'Expérience Utilisateur

Ce plan détaille les modifications pour améliorer l'aspect visuel, la convivialité de la télémétrie, la cartographie et l'ajout d'un panneau latéral pour la détection de posture.

## User Review Required

> [!IMPORTANT]
> L'ajout d'un `SideSheet` modifiera la disposition de la galerie des participants quand il sera ouvert. Il faudra s'assurer que l'expérience reste fluide sur mobile.

## Proposed Changes

### 1. Télémétrie et Flux Vidéo

#### [MODIFY] [participant.dart](file:///D:/Projets/POC OPK/livekitapp/lib/presentation/widgets/participant.dart)
- Déplacer `_DataHud` (télémétrie) de la `Column` vers le `Stack` dans `_buildVideoStack` pour qu'il soit superposé au flux vidéo.
- Ajouter un `SafeArea` (ou du padding conditionnel) à la télémétrie pour qu'elle ne soit pas collée à la barre de statut lorsqu'elle est en haut du flux principal.
- Moderniser le style de `_DataHud` (effet flou/glassmorphism, bordures plus fines).

### 2. Cartographie des Participants

#### [MODIFY] [participants_map.dart](file:///D:/Projets/POC OPK/livekitapp/lib/presentation/widgets/participants_map.dart)
- Améliorer l'algorithme de centrage pour s'assurer que tous les participants distants avec une position GPS sont visibles.
- Ajouter un léger délai ou une animation de transition lors du changement de zoom/position.
- Améliorer le rendu visuel de la carte (ombre portée, bordure plus élégante).

### 3. Navigation et Galerie (Room)

#### [MODIFY] [room.dart](file:///D:/Projets/POC OPK/livekitapp/lib/presentation/screens/room.dart)
- Implémenter un `SideSheet` (panneau latéral droit) pour afficher la posture d'un participant sélectionné.
- Gérer l'état de sélection du participant pour le `SideSheet`.
- Ajuster les insets de la galerie lorsque le `SideSheet` est ouvert.

#### [MODIFY] [room_viewmodel.dart](file:///D:/Projets/POC OPK/livekitapp/lib/viewmodels/room_viewmodel.dart) [NEW] (ou modifier l'existant)
- Ajouter la gestion de l'identité du participant sélectionné pour la posture.

### 4. Suggestions UI/UX (Bonus)
- Utilisation de `BackdropFilter` pour un effet de verre dépoli sur les éléments flottants (Map, Controls, Hud).
- Amélioration des contrastes pour une meilleure lisibilité en extérieur.

## Verification Plan

### Manual Verification
1. Lancer l'application et rejoindre une room.
2. Vérifier que la télémétrie locale n'empiète pas sur la barre de statut.
3. Vérifier que les flux vidéo des participants distants affichent la télémétrie en superposition.
4. Ajouter des participants simulés (ou réels) et vérifier le centrage de la carte.
5. Ouvrir le `SideSheet` de posture pour un participant distant et vérifier qu'il s'affiche/se ferme correctement.
