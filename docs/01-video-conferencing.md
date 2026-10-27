# 01 — Visioconférence temps réel (LiveKit)

Ce document décrit le sous-système de visioconférence : obtention de token, création de
session, paramètres média, contrôle des flux et gestion des participants. Aucune
dépendance au framework UI n'est requise pour comprendre ce document.

## 1. Paramètres de connexion

| Constante | Valeur |
|---|---|
| URL API (token) | `https://api.videolog.app` |
| Endpoint token | `POST /token` (Bearer Firebase, body `{room}`) |
| URL serveur LiveKit (WebSocket) | renvoyée dans `url` (`wss://livekit.videolog.app` en production) |
| Room par défaut | `poc-room` (fallback local) |
| Timeout des requêtes API | 15 secondes |

## 2. Workflow d'entrée dans une session

```
Écran Connect
   │  1. Compte Firebase courant et room sélectionnée
   │  2. Demande des permissions Android (bluetooth, bluetoothConnect,
   │     camera, microphone) — uniquement sur Android
   │  3. POST /token {room} + Bearer Firebase → {token, room, identity, url}
   │  4. Création de la Room + écouteur, connexion
   │     (nouvelle tentative unique avec un token rafraîchi)
   │  5. Publication du micro et de la caméra avant par défaut
   ▼
Écran Room
       6. Session active : écoute des événements, publication/réception
```

### 2.1 Contrat HTTP du token

**Requête**
```
POST https://api.videolog.app/token
Content-Type: application/json
Authorization: Bearer <Firebase ID token>
Timeout: 15 s

{ "room": "<nom room>" }
```

**Réponse attendue** : `200 OK`
```json
{
  "token": "<JWT LiveKit>",
  "room": "<nom room>",
  "identity": "<UID Firebase vérifié>",
  "url": "wss://livekit.videolog.app"
}
```

L'identité LiveKit est dérivée du UID Firebase par le serveur ; le client ne
l'envoie pas. Tout autre code HTTP provoque une erreur affichée à l'utilisateur
(`401` non connecté, `403` non autorisé, `404` session absente). L'API côté
serveur délègue à `livekit-api` qui signe le JWT avec l'API_KEY/SECRET du
serveur LiveKit. Le JWT expire après dix minutes ; le client redemande un token
en cas d'échec de connexion.

### 2.2 Paramètres par défaut de la salle

| Paramètre | Valeur | Rôle |
|---|---|---|
| `adaptiveStream` | `true` | Ajuste la qualité reçue à la taille d'affichage |
| `dynacast` | `true` | Coupe les sous-encodages inutilisés côté émission |
| `simulcast` | `true` | Émission multi-qualités |
| `preferredCodec` | `VP8` | Codec vidéo préféré |
| `enableBackupVideoCodec` | `false` (VP8) ; `true` si VP9/AV1 | Codec de secours |
| `e2ee` | `false` | Chiffrement de bout en bout désactivé par défaut |
| Nom de piste audio | `custom_audio_track_name` | Identifiant de la piste publiée |

### 2.3 Paramètres de capture

| Source | Paramètres |
|---|---|
| Caméra | 1280×720, fréquence max 30 fps |
| Partage d'écran | 1920×1080 (16:9), extension de diffusion iOS activée |
| Encodage caméra | débit max 5 Mbps, 30 fps |
| Encodage partage d'écran | débit max 3 Mbps, 15 fps |

### 2.4 Étapes de connexion

1. Création d'un écouteur d'événements (`createListener`) **avant** la connexion.
2. `prepareConnection(url, token)` — pré-résolution et pré-connexion.
3. `connect(url, token, fastConnectOptions)` — publication immédiate du microphone et
   de la caméra déjà créés (fast connect), évitant un cycle muet/sans vidéo.
4. Navigation vers l'écran de session en passant la salle et l'écouteur.
5. En cas d'échec : dialogue d'erreur ; dans tous les cas, retour à l'écran Home.

### 2.5 E2EE (optionnel)

Si activé avec une clé :
- Création d'un fournisseur de clés (`BaseKeyProvider`).
- `E2EEOptions` attachées aux options de la salle.
- La clé est définie avant la connexion.

### 2.6 Permissions

Sur Android, à l'ouverture de l'écran Connect :
`bluetooth`, `bluetoothConnect`, `camera`, `microphone` — chacune sollicitée à
l'utilisateur ; un refus définitivement accordé est journalisé.

## 3. Cycle de vie de la session (écran Room)

| Moment | Comportement |
|---|---|
| Création de l'écran | Instanciation de l'orchestrateur de session, initialisation différée (après le premier rendu) |
| Android | Haut-parleur activé automatiquement au démarrage |
| Fermeture de fenêtre (desktop) | Déconnexion puis attente de l'événement `RoomDisconnected` (timeout 5 s) |
| Déconnexion | Arrêt de la télémétrie et de la détection de posture, retour à l'écran précédent |
| Verrouillage écran | **Wakelock activé** à l'entrée, désactivé à la libération |

### 3.1 Événements de session gérés

| Événement | Action |
|---|---|
| `RoomDisconnected` | Stop télémétrie + détection, callback de retour |
| `ParticipantEvent` (générique) | Recalcul de la liste des participants |
| `LocalTrackPublished` / `LocalTrackUnpublished` | Recalcul de la liste |
| `TrackSubscribed` / `TrackUnsubscribed` | Recalcul de la liste |
| `ParticipantConnected` | Recalcul de la liste |
| `ParticipantDisconnected` | Purge des postures et télémétries du participant, recalcul |
| `DataReceived` | Décodage UTF-8 → routage par topic (`telemetry` / `posture`) |

## 4. Modèle des participants affichés

L'unité d'affichage est une **entrée de participant** (« ParticipantTrack ») :

| Champ | Type | Description |
|---|---|---|
| `participant` | participant (local ou distant) | Référence LiveKit |
| `type` | `userMedia` ou `screenShare` | Type de flux |
| `posture` | posture distante (optionnelle) | Dernière posture reçue |
| `telemetry` | télémétrie (optionnelle) | Dernière télémétrie reçue |
| `pose` / `poseFrameSize` | pose + dimensions (local) | Pose locale courante |
| `avatarOnly` | bool | `true` pour le flux local |
| `showPosePip` / `showPosture` | bool | Visibilité du PIP de posture |
| `onTogglePosture` | callback | Bascule la visibilité |

### 4.1 Ordre d'affichage (algorithme de tri)

1. Les flux de **partage d'écran** sont séparés et placés **en tête** de liste.
2. Les flux **caméra** (userMedia) sont triés par :
   a. participants actuellement en train de parler (les plus forts d'abord, selon le
      niveau audio) ;
   b. sinon, les ayant parlé le plus récemment (`lastSpokeAt` décroissant) ;
   c. sinon, par ancienneté de présence (`joinedAt` croissant).
3. Les flux **locaux** sont ajoutés en dernier avec la posture courante, la télémétrie
   locale et le marqueur `avatarOnly`.

Résultat : `[screenShares..., userMedia...]`.

### 4.2 Répartition écran principal / secondaire

- **Track principal** : le flux local de type userMedia ; à défaut, la première entrée.
- **Tracks secondaires** : toutes les autres entrées (galerie horizontale des pairs).

### 4.3 Déduplication des postures

Avant le tri, les postures enregistrées dont l'identité n'est plus présente dans la salle
sont supprimées.

## 5. Contrôles média

| Action | Comportement |
|---|---|
| Micro (mobile) | Bascule directe muet / non muet |
| Micro (desktop) | Sélection de l'entrée audio (dropdown) |
| Caméra on/off | Active/désactive la piste caméra |
| Caméra switch | Alterne position avant/arrière (front ↔ back) |
| Haut-parleur | Bascule haut-parleur (`setSpeakerOn`, sans forcer) |
| Entrée audio | Sélection de la source d'entrée |
| Sortie audio | Sélection du périphérique de sortie |
| État reflété | `isMuted`, `isCameraEnabled`, position caméra, niveau batterie lunettes, état des capteurs |

### 5.1 Changement de périphérique

L'énumération des périphériques est réactive : à chaque changement matériel (connexion
d'un casque, etc.), les listes entrées/sorties sont rafraîchies et les sélections
invalidées si le périphérique sélectionné a disparu.

## 6. Connexion avec les paramètres par défaut

Il n'y a plus d'écran de pré-connexion. La publication démarre dès la connexion :

| Élément | Valeur par défaut |
|---|---|
| Microphone | activé immédiatement (`setMicrophoneEnabled`) |
| Caméra | avant, 640×480, 30 fps max (`setCameraEnabled`) |
| Capture caméra | `CameraCaptureOptions` de `RoomOptions` |
| Codec vidéo | `H264`, codec de secours activé |
| Simulcast | désactivé |
| Adaptive stream / dynacast | activés |
| E2EE | désactivé |

Après l'entrée dans la room, l'utilisateur peut couper/réactiver le micro et la caméra,
changer de caméra ou sélectionner les périphériques depuis la barre de contrôles. Aucune
préférence PreJoin n'est plus persistée.

## 7. Rendu des participants

### 7.1 Bords et état

- Bordure bleue lorsque le participant **parle**.
- Menu contextuel (participant distant) : s'abonner / se désabonner de la piste.
- Sous-menus de qualité : FPS (30 / 15 / 8) et résolution (HIGH / MEDIUM / LOW).
- La couche de statistiques est activée sur le flux principal.

### 7.2 HUD de données par participant

Trois pastilles affichées quand les données existent :

| Pastille | Format | Source |
|---|---|---|
| FC | `145 bpm` | télémétrie `heart_rate` |
| Vitesse | `12.4 km/h` | télémétrie `speed` |
| Cadence | `82 rpm` | télémétrie `cadence` |

### 7.3 Posture affichée

Le squelette peut être affiché en **overlay** sur la vidéo ou en **panneau latéral** à
côté de la vidéo (voir `06-pose-detection.md` et `07-ui-behavior.md`).

## 8. Points d'attention pour le portage KMP

| Élément | Référence |
|---|---|
| Interface à définir : `RoomGateway` (connect, publishData, toggle tracks, events) | Section 2, 3 |
| Interface à définir : `MediaDeviceRegistry` (énumération, changement réactif) | Section 5.1 |
| Le format du token et le workflow HTTP sont purement métier | Section 2.1 |
| Le tri des participants est une fonction pure testable | Section 4.1 |
| Les paramètres de salle/encodage sont des constantes | Sections 2.2–2.3 |
