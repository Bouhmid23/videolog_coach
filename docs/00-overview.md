# 00 — Vue d'ensemble du projet

## 1. Vision produit

**Videolog Coach** (nom Android : *Videolog Coach*, nom affiché dans l'app : *VideoLog*,
*Videolog Sport* sur l'écran de connexion) est une application mobile de **coaching sportif
en temps réel**. Elle permet à un coach (ou à plusieurs paires) de :

1. Se voir et s'entendre en **visioconférence** (audio/vidéo haute qualité).
2. Échanger en continu leurs **données sportives** : fréquence cardiaque, cadence,
   vitesse, position GPS, calories.
3. Suivre la **posture** de chaque participant en temps réel, affichée sous forme de
   squelette 33 points et classée automatiquement (debout / assis / allongé).
4. Projeter les métriques clés sur des **lunettes connectées** (HUD de sport —
   ActiveLook / Engo) portées par le coach ou l'athlète.
5. Situer tous les participants sur une **mini-carte**.

L'application cible **Android et iOS uniquement** (aucune plateforme web/desktop/mobile
n'est déclarée, bien qu'une partie du code contienne des branches de compatibilité).

## 2. Stack technique

| Domaine | Technologie |
|---|---|
| Framework UI | Flutter (SDK Dart `^3.10.3`), Material 3, thème sombre custom |
| Temps réel audio/vidéo | LiveKit (`livekit_client ^2.6.4`) + WebRTC |
| Bluetooth basse consommée | `flutter_reactive_ble ^5.4.2` |
| Détection de pose (IA locale) | MediaPipe via `flutter_pose_detection ^0.4.0` (détecteur GPU) |
| Positionnement | `geolocator ^13.0.2` |
| Authentification | Firebase Auth (`firebase_core`, `firebase_auth`) — email / mot de passe |
| Requêtes HTTP | `http ^1.6.0` (token, rooms, enregistrement) |
| Persistance locale | `shared_preferences` (préférences de pré-connexion) |
| Permissions | `permission_handler ^12.0.1` |
| Gestion d'état | `ChangeNotifier` (pattern observateur) — le package `provider` est déclaré mais non utilisé |
| Navigation | `go_router ^14.8.1` |
| Verrouillage écran | `wakelock_plus` |
| Polices / rendu | `google_fonts`, `flutter_svg`, `dropdown_button2` |

> **Note KMP** : aucune de ces dépendances n'est obligatoire côté « logique métier ».
> Le portage consiste à isoler les règles métier (protocoles, calculs, formats de données)
> dans un module commun, puis à réimplémenter les adaptateurs plateforme (WebRTC, BLE,
> IA, GPS) en utilisant les API natives.

## 3. Architecture en couches

Le code source est organisé en quatre couches :

```
lib/
├── core/            → SERVICES (accès aux périphériques et aux protocoles)
│   ├── ble_telemetry_service      protocole lunettes ActiveLook
│   ├── ble_sensor_service         capteurs cardio/cadence BLE
│   ├── posture_detection_service  lissage des landmarks
│   ├── api_service                (orpheLIN) obtention de token
│   └── livekit_service            (orpheLIN) encapsulation de session
├── data/            → MODÈLES DE DONNÉES DISTANTES
│   ├── remote_telemetry           télémétrie reçue d'un pair
│   └── remote_posture             posture reçue d'un pair
├── viewmodels/      → ORCHESTRATION / ÉTAT
│   ├── room_viewmodel             orchestrateur central de la session
│   ├── controls_viewmodel         contrôles média + BLE
│   └── pose_detection_viewmodel   détection → classification → diffusion
└── presentation/    → ÉCRANS ET COMPOSANTS D'UI
    ├── screens/                   login, rooms, connect, room
    └── widgets/                   contrôles, participant, carte, squelette…
```

### Règle de séparation pour le portage

| Couche | Portable en KMP ? |
|---|---|
| `core/` (hors dépendance BLE concrète) | ✅ Oui — protocoles binaires, parsing, calculs |
| `data/` | ✅ Oui — modèles et décodage JSON |
| `viewmodels/` | ✅ En grande partie — orchestration, sérialisation, tris, agrégation |
| `presentation/` | ❌ Non — rendu natif (Compose / SwiftUI) ; seules les données à dessiner sont portables |

## 4. Flux utilisateur

```
┌──────────┐   ┌──────────┐   ┌────────────┐   ┌──────────┐
│  Login   │ → │  Rooms   │ → │  Connect   │ → │   Room   │
└──────────┘   └──────────┘   └────────────┘   └──────────┘
  /login        /rooms          /connect/:room   /room
                                                (extra: args)
```

1. **Login** — email / mot de passe envoyés directement à **Firebase Authentication**
   (jamais à l'API Videolog). Le routeur redirige toute route protégée vers `/login`
   tant qu'aucune session Firebase n'existe.
2. **Rooms** — liste réelle via `GET /mobile/rooms`, avec statut d'enregistrement et
   `can_control_recording`.
3. **Connect** — le compte Firebase et la room sont affichés ; le token LiveKit est
   obtenu via `POST /token` avec l'ID token Firebase en Bearer. L'identité LiveKit
   est l'UID Firebase dérivé côté serveur. La connexion utilise les paramètres par
   défaut (micro et caméra avant) et remplace l'écran par la room.
4. **Room** — session complète : vidéo plein écran, barre de contrôles, galerie des pairs,
   mini-carte, panneau latéral de posture.

## 5. Matrice des fonctionnalités

| Fonctionnalité | État | Référence détaillée |
|---|---|---|
| Authentification | ✅ Réelle (Firebase Auth, email / mot de passe) | `01-video-conferencing.md` |
| Liste des sessions mobiles | ✅ Réelle (`GET /mobile/rooms`) | `MOBILE_RECORDING_WORKFLOW.md` |
| Obtention de token LiveKit | ✅ Réelle (HTTP POST authentifié) | `01-video-conferencing.md` |
| Appel audio/vidéo | ✅ Réel (LiveKit) | `01-video-conferencing.md` |
| Chiffrement de bout en bout (E2EE) | ✅ Supporté (désactivé par défaut) | `01-video-conferencing.md` |
| Partage d'écran | ⚠️ Affichage des flux reçus uniquement (pas de bouton d'initialisation) | `01-video-conferencing.md` |
| Chat texte | ❌ Absent | — |
| Enregistrement de session (Egress) | ✅ Manuel : démarrer / suivre / arrêter, durée max 180 s | `MOBILE_RECORDING_WORKFLOW.md` |
| Télémétrie temps réel (DataChannel) | ✅ Réelle, 2 Hz | `02-telemetry.md` |
| Suivi GPS + distance | ✅ Réel | `03-gps-map.md` |
| Mini-carte des participants | ✅ Réelle | `03-gps-map.md` |
| Lunettes ActiveLook (HUD) | ✅ Réelles (protocole complet) | `04-ble-glasses.md` |
| Capteurs cardio/cadence BLE | ✅ Réels (standards Bluetooth SIG) | `05-ble-sensors.md` |
| Détection de posture locale | ✅ Réelle (MediaPipe GPU, continu) | `06-pose-detection.md` |
| Diffusion de posture aux pairs | ✅ Réelle (DataChannel) | `06-pose-detection.md` |
| Squelette 33 points + HUD métriques | ✅ Réel | `06-pose-detection.md`, `07-ui-behavior.md` |
| Wakelock (écran maintenu actif) | ✅ Actif pendant la session | `01-video-conferencing.md` |

## 6. Endpoints et constantes globales

| Constante | Valeur |
|---|---|
| URL API | `https://api.videolog.app` |
| Authentification | Firebase Auth (projet `videolog-on-air`), ID token en Bearer |
| Endpoint token | `POST /token` (body `{room}`) |
| Liste des sessions | `GET /mobile/rooms?limit=50` |
| Enregistrement | `POST /mobile/rooms/{room}/recording/start?layout=grid`, `GET .../recording`, `POST .../recording/stop` |
| URL LiveKit (WebSocket) | `wss://livekit.videolog.app` (champ `url` de la réponse token) |
| Room par défaut | `poc-room` (fallback local ; la liste réelle vient de l'API) |

> `usesCleartextTraffic="true"` est activé dans le manifeste Android, ce qui autorise le
> HTTP non chiffré (utile pour les tests en local).

## 7. Permissions déclarées

### Android (`AndroidManifest.xml`)
`INTERNET`, `CAMERA`, `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`, `WAKE_LOCK`,
`BLUETOOTH`, `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION`,
`ACCESS_COARSE_LOCATION`, `FOREGROUND_SERVICE` (types : camera, microphone,
connectedDevice), `POST_NOTIFICATIONS`, `ACCESS_NETWORK_STATE`.

Un service *foreground* est déclaré avec `foregroundServiceType="camera|microphone|connectedDevice"`.

### iOS (`Info.plist`)
- Modes arrière-plan : `audio`, `voip`, `location`
- Descriptions de permissions en français : caméra, microphone, Bluetooth
  (`NSBluetoothAlwaysUsageDescription`), localisation (quand en usage + toujours).

## 8. État du dépôt et dettes techniques

- **Tests** : 5 tests de modèles (`RecordingState`, `MobileRoom`) ; pas encore de test UI.
- **README** : template Flutter par défaut (non personnalisé).
- **Code mort** à ne pas porter (détails dans `08-kmp-porting.md`) :
  - `core/livekit_service.dart`
  - `widgets/smoothed_pose_avatar.dart`, `widgets/sound_waveform.dart`, `widgets/text_field.dart`
- **Bug connu** : `PoseAnimationController` instancie un contrôleur d'animation avec un
  `vsync` invalide (non utilisé en l'état).
- **Dépendances déclarées mais inutilisées** : `provider`, `flutter_svg`,
  `flutter_background`, `flutter_foreground_task`, `camera`, `o3d`.
