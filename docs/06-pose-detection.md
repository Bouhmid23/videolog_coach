# 06 — Détection de posture, classification et squelette

Ce document décrit le pipeline de détection de posture : capture des images de la caméra,
analyse par IA locale (MediaPipe), lissage, classification (debout / assis / allongé),
sérialisation et diffusion aux pairs.

## 1. Vue d'ensemble

```
Piste caméra locale
      │  capture JPEG en mémoire
      ▼
Détecteur MediaPipe lite (RunningMode.VIDEO, accélération demandée GPU)
      │  Pose : image landmarks + worldLandmarks
      ▼
Lissage exponentiel (α = 0.35)          ← posture_detection_service
      │  Pose lissée
      ├──────────────────────────────→ Rendu local du squelette
      ▼
Classification (debout / assis / allongé)
      │  {label, confidence}
      ▼
Sérialisation binaire compact → publishData(topic="posture")  (lossy, temps réel)
      │
      ▼
Tous les pairs : RemotePosture.tryParseBinary → stockage → rendu interpolé
```

## 2. Paramètres du pipeline

| Paramètre | Valeur |
|---|---|
| Fréquence d'analyse | Continue, sans plafond explicite; débit réel à mesurer sur appareil |
| Détecteur | Fork local `flutter_pose_detection` 0.4.1, MediaPipe lite, mode `VIDEO` |
| Paramètres détecteur | `maxPoses: 1`, seuils détection / présence / suivi à `0.5`, accélération GPU demandée |
| Nombre de landmarks | 33 points image et 33 world landmarks en mètres |
| Alpha de lissage | **0.35** |
| Source image | `captureFrame` de la piste caméra locale, JPEG transmis en mémoire |
| Concurrency | Boucle séquentielle (flag `_running`), un seul tick à la fois |
| Transport | DataChannel LiveKit **lossy** (`reliable: false`), payload binaire |
| Web | Détecteur désactivé (branche ignorée) |

### 2.1 Cycle d'un tick

La détection tourne dans une **boucle continue** (`_poseLoop`) tant que
`_running` est vrai : capture → détection → publication enchaînées sans attente
artificielle. Un `Future.delayed(Duration.zero)` rend la main à la boucle
d'événements entre deux frames ; un repli de 100 ms s'applique si aucune frame
n'a pu être traitée (caméra non prête).

```
si plateforme web ou _running faux → sortir
localiser la piste caméra locale (source camera)
si aucune piste → repli 100 ms
   1. capturer un frame JPEG en mémoire et mémoriser ses timestamps capture/VIDEO
   2. détecter la pose avec `detectForVideo` (si aucune pose → notification,
      repli 100 ms)
   3. lire les dimensions depuis le résultat de détection
   4. lisser la pose          (AVANT la classification, pour des libellés cohérents)
   5. classifier la pose lissée
   6. mettre à jour l'état + notification
   7. sérialiser et publier le squelette (même sans libellé, code « inconnu »)
yield (Duration.zero)
```

Après une perte de pose, le filtre image/world est réinitialisé. Le dernier label stable est conservé afin que la reprise repasse par l'hystérésis de trois frames.

### 2.2 Capture en mémoire

`captureFrame` retourne un buffer JPEG. L'app le transmet au plugin via le canal Flutter,
sans fichier temporaire. L'horodatage monotone transmis à MediaPipe sert au suivi `VIDEO`;
le paquet posture conserve l'heure epoch prise avant la capture.

Les logs `📊 pose` détaillent `capture`, `detect`, `infer`, `publish` et les débits
`capture/s`, `publishData/s` et `seq/s` afin d'isoler le goulot d'étranglement.

## 3. Lissage (filter exponentiel)

Pour chaque landmark (clé = type de landmark), état maintainu entre les ticks :

```
x = x + α × (x_nouveau − x)        // idem pour y et z
visibility : non lissée (conservée telle quelle)
α = 0.35
```

- Le premier échantillon d'un landmark initialise la position sans lissage.
- `reset()` vide l'état (appelé à l'arrêt).
- Le lissage se fait **en coordonnées source** (avant toute projection).

## 4. Classification de posture

Entrée : la **pose lissée**. Sortie : un modèle `{label, confidence}` ou `null`.

### 4.1 Points de référence

```
shoulderMid = milieu(leftShoulder, rightShoulder)
hipMid      = milieu(leftHip, rightHip)
kneeMid     = milieu(leftKnee, rightKnee)          (optionnel)
ankleMid    = milieu(leftAnkle, rightAnkle)        (optionnel)
```

- Si `shoulderMid` ou `hipMid` est indisponible → **`null`** (classification impossible).
- Les milieux sont calculés en coordonnées 2D (x, y).

### 4.2 Métriques géométriques

```
torsoDx = shoulderMid.x − hipMid.x
torsoDy = hipMid.y − shoulderMid.y                // y croissant vers le bas

torsoAngleDeg = atan2( |torsoDx|, max(|torsoDy|, 1e−6) ) × 180 / π

torsoLength = max(|hipMid.y − shoulderMid.y|, 1.0)

kneeDrop  = kneeMid  absent ? 0 : (kneeMid.y  − hipMid.y) / torsoLength
ankleDrop = ankleMid absent ? 0 : (ankleMid.y − hipMid.y) / torsoLength
```

> **Interprétation** : `torsoAngleDeg` mesure la **pente du torse** par rapport à la
> verticale (0° = parfaitement vertical, 90° = horizontal). `kneeDrop`/`ankleDrop`
> mesurent la descente des genoux/chevilles sous les hanches, **normalisée** par la
> longueur du torse.

### 4.3 Règle de décision

```
si torsoAngleDeg > 48        → "allongé"
sinon si kneeDrop < 0.35
      ET ankleDrop < 0.7     → "assis"
sinon                        → "debout"
```

### 4.4 Confiance

```
confidence = moyenne( visibility(leftShoulder), visibility(rightShoulder),
                      visibility(leftHip),      visibility(rightHip) )
clampée à [0, 1]
```
Seuls les landmarks présents sont pris en compte ; si aucun → 0.0.

### 4.5 Libellés produits

| Libellé | Condition |
|---|---|
| `allongé` | Torse à plus de 48° de la verticale |
| `assis` | Torse quasi vertical ET genoux/chevilles bas |
| `debout` | Sinon |

> Le texte des libellés est en français (encodé dans les payloads).

## 5. Schéma du message diffusé (topic `posture`)

Le publisher émet le codec big-endian v7 sur le DataChannel LiveKit lossy.
Chaque pose fait exactement **275 octets** : en-tête 11 octets et 33 points de 8 octets.
Le décodeur web doit accepter la version 7 et ce découpage avant d'utiliser ce publisher.

| Offset | Taille | Champ |
|---|---:|---|
| 0 | 1 | Version `7` |
| 1 | 1 | Label : `0` debout, `1` assis, `2` allongé, `255` inconnu |
| 2 | 1 | Confiance `0..255` (`0` signifie inconnue) |
| 3–4 | 2 | Séquence uint16 big-endian, modulo 65536 |
| 5–6 | 2 | Heure epoch de capture en ms, modulo 65536 |
| 7–8 | 2 | Largeur de frame uint16 |
| 9–10 | 2 | Hauteur de frame uint16 |
| 11…274 | 33 × 8 | Points dans l'ordre MediaPipe défini par `PostureCodec.sent` |

Chaque point est compacté ainsi :

| Octets relatifs | Bits | Valeurs |
|---|---|---|
| 0–2 | 12 + 12 | image x/y, quantifiés sur `[-0.5, 1.5]` |
| 3–5 | 12 + 12 | world x/y en mètres, chacun sur `[-1.5, 1.5]` |
| 6–7 | 12 + 4 | world z en mètres sur `[-1.5, 1.5]`, visibilité image `0..15` |

Les world landmarks viennent de MediaPipe `result.worldLandmarks()` et sont exprimés en
mètres, autour de l'origine du bassin. Le z image du format v6 est une profondeur relative,
à l'échelle de x ; il ne représente pas des mètres. Les paquets `lost` contiennent seulement
l'en-tête de 11 octets, la version 7 et le label `254`.
## 6. Réception côté pairs (`RemotePosture`)

### 6.1 Champs du modèle

| Champ | Type | Description |
|---|---|---|
| `label` | string | Libellé (requis) |
| `confidence` | double? | 0–1 |
| `receivedAt` | date | Horodatage local de réception |
| `pose` | `Pose?` | Pose déjà reconstruite (chemin binaire) |
| `landmarks` | liste de maps? | Points bruts (chemin JSON hérité) |
| `frameWidth` / `frameHeight` | double? | Dimensions source |
| `seq` | int? | Numéro de séquence émetteur (chemin binaire) |
| `timestampMs` | int? | Timestamp émetteur epoch ms (chemin binaire) |
| `hasSkeleton` | bool | (`pose` non vide **ou** `landmarks` non vide) **et** dimensions connues |
| `frameSize` | taille? | `(frameWidth, frameHeight)` |

### 6.2 Décodage tolérant

**1. Localisation du sous-objet** (`_extractPostureMap`) — essai dans l'ordre :
- `payload` si c'est un objet **et** qu'il ressemble à une payload de posture,
- `posture` ou `pose` si ce sont des objets,
- le message lui-même s'il ressemble à une payload,
- sinon → `FormatException` (rejet).

**Test « ressemble à une payload »** : `type == "posture"` ou `type == "pose"`, **ou**
présence d'une clé `posture` / `pose` / `label` / `status`.

**2. Lecture du libellé** — dans l'ordre : `posture`, `pose`, puis `label` / `status` /
`state` (doit être une string non vide, sinon rejet).

**3. Lecture de la confiance** — clés acceptées : `confidence`, `score`, `probability`
(numérique ou string parsable) ; clampée à [0, 1].

**4. Lecture des dimensions** — `frame_width` / `frame_height` : numériques ou strings.

**5. Lecture des landmarks** — doit être une liste ; chaque élément objet est conservé.

**`tryParse`** : renvoie `null` sur `FormatException` ou `TypeError` (aucune exception
propagée au consommateur).

### 6.3 Reconstruction d'une pose (`toPose`)

```
pour chaque landmark :
    idx = landmark["type"]
    si idx n'est pas un int valide dans l'enum → ignorer le point
    créer un point {type=enum[idx], x, y, z, visibility}
si aucun point valide → null
sinon → Pose(landmarks, score = 1.0)
```

> L'index `type` correspond à l'**ordre de l'enum de types de landmark** du moteur de
> pose côté émetteur. L'émetteur et le récepteur doivent partager le même ordre
> (standard MediaPipe, 33 points).

## 7. Stockage et usage côté réception

| Aspect | Comportement |
|---|---|
| Clé de stockage | identité du participant émetteur |
| Remplacement | dernier message = état courant |
| Purge | à la déconnexion du participant, et lors du recalcul pour les identités absentes |
| Bascule de visibilité | un ensemble d'identités « masquées » permet de masquer le squelette d'un pair |
| Tri des participants | le tri déclenche une notification (les squelettes sont liés aux entrées) |

## 8. Topologie d'affichage du squelette

| Zone | Portée | Description |
|---|---|---|
| Overlay vidéo | local + pairs | Squelette superposé à l'image |
| Panneau latéral (aside) | flux principal | Vidéo + colonne squelette (largeur 220 px) |
| PIP de posture | bascule globale | Mini-vue de posture (toggle dans les contrôles) |
| SideSheet de posture | participant sélectionné | Panneau latéral dédié (voir `07-ui-behavior.md`) |

### 8.1 Sources de la pose

| Émetteur | Pose utilisée |
|---|---|
| Local | Pose lissée courante (miroir X activé pour l'affichage) |
| Distant | Reconstruction depuis `RemotePosture.toPose()` (miroir X selon le contexte) |
| Si pas de squelette | Affichage de la vidéo seule (pas d'overlay) |

## 9. Dessin du squelette (référence de rendu)

### 9.1 Os standard (12 connexions)

| Nom | De → Vers |
|---|---|
| Shoulders | leftShoulder → rightShoulder |
| Left Torso | leftShoulder → leftHip |
| Right Torso | rightShoulder → rightHip |
| Hips | leftHip → rightHip |
| Left Upper Arm | leftShoulder → leftElbow |
| Left Forearm | leftElbow → leftWrist |
| Right Upper Arm | rightShoulder → rightElbow |
| Right Forearm | rightElbow → rightWrist |
| Left Thigh | leftHip → leftKnee |
| Left Calf | leftKnee → leftAnkle |
| Right Thigh | rightHip → rightKnee |
| Right Ankle | rightKnee → rightAnkle |

### 9.2 Éléments visuels (comportements à reproduire)

| Élément | Comportement |
|---|---|
| Points de tête / articulations | halo, anneau et cœur clair ; couleur par côté (gauche / droite) |
| Os | dégradé bleu du logo + cyan, avec halo et trait de lumière |
| Confiance faible | trait pointillé / opacité réduite |
| Miroir local | caméra frontale locale : overlay miroir X comme le renderer vidéo |
| Ligne de sol | droite horizontale basse |
| Graduations | graduations le long de la ligne de sol |
| Seuil de visibilité | points avec `visibility < 0.2` ignorés à la projection |

### 9.3 Projection des points (InterpolatedPose)

```
1. Détection des coordonnées normalisées :
      si |x| ≤ 1.01 ET |y| ≤ 1.01 → coordonnées normalisées
      → x = x × frameWidth, y = y × frameHeight
2. Miroir horizontal (si activé) : x = frameWidth − x
3. Ajustement « cover » de la boîte source (frame) dans la boîte destination (affichage)
      — centré, en conservant les proportions, comme le renderer vidéo
4. Normalisation dans la boîte source puis projection dans la boîte destination
```

### 9.4 Interpolation entre poses (rendu temps réel)

Le widget `_SkeletonOverlay` est **animé** : à chaque nouvelle pose reçue, il
interpole en continu depuis la pose affichée vers la nouvelle pose, ce qui
lisse la gigue réseau et rend la réplication fluide.

```
points : lerp linéaire par type de landmark (x, y, z, visibility)
         si un type n'existe que d'un côté → conservé tel quel
durée de transition ≈ intervalle réel entre deux frames,
                      bornée à [16 ms, 100 ms]
courbe : easeOut
```

> Un changement de résolution (`frameSize`) désactive l'interpolation pour la
> frame concernée (saut direct) afin d'éviter un étirement.
> Le contrôleur historique `PoseAnimationController` de `pose_animation.dart`
> reste inutilisable (construction avec un `vsync` invalide) — voir
> `08-kmp-porting.md`.

### 9.5 Palette (référence)

| Élément | Couleur / rendu |
|---|---|
| Côté gauche | `logoLight` `#66CCF5` |
| Côté droit | `logoBlue` `#22B8F0` |
| Axe / centre | `secondary` `#22D3EE` |
| Confiance > 0.45 | trait plein, épaisseur et alpha proportionnels à la confiance |
| Confiance ≤ 0.45 | trait pointillé, halo et alpha réduits |
| Articulations | halo extérieur, anneau coloré, cœur clair et point blanc |

## 10. Points d'attention pour le portage KMP

| Élément | Nature | Recommandation |
|---|---|---|
| Lissage exponentiel | Pur | Fonction/classe avec état + tests |
| `classifyPosture` | Pur | **Haute priorité** — fonction pure testable (angles, seuils) |
| Sérialisation du payload | Pur | Data class + codec binaire (`PostureCodec`, format v7) |
| Décodage tolérant `RemotePosture` | Pur | **Haute priorité** — nombreux formats acceptés, à tester |
| Reconstruction de pose depuis landmarks | Pur | Fonction pure (mapping index → type) |
| Table des os + palette | Pur | Constantes |
| Projection / interpolation de points | Pur | Fonctions pures |
| Capture de frame | Plateforme | Interface `FrameSource` (via WebRTC natif) |
| Détecteur MediaPipe | Plateforme | Interface `PoseDetector` (Android : MediaPipe/TFLite, iOS : Vision/Core ML) |
| Publication DataChannel | Transport | Via `RoomGateway` |

**Attention de compatibilité** : l'index `type` des landmarks doit être identique entre
émetteur et récepteur. En portant vers KMP, figer l'ordre (standard MediaPipe 33) dans
une **enum partagée** du module commun.
