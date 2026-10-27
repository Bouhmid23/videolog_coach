# 08 — Guide de portage Kotlin Multiplatform (KMP)

Ce document synthétise comment découper le projet pour un portage en Kotlin
Multiplatform, en séparant ce qui est **portable** (logique métier, protocoles,
calculs) de ce qui reste **natif** (rendu, API plateforme).

## 1. Cible de portage

| Cible | Plateformes |
|---|---|
| POC actuel | Android + iOS (Flutter) |
| Cible KMP | Android (Compose) + iOS (SwiftUI), module `shared` commun |

## 2. Découpage en modules

```
shared/
├── core-protocol/      Protocoles binaires, formats JSON, constantes
│   ├── activelook      trames, cmdIds, layout HUD, fonts        (04)
│   ├── ble-sig         parsing HR 0x2A37, CSC 0x2A5B            (05)
│   ├── telemetry       schémas d'émission/réception              (02)
│   └── posture         schéma posture, classification, lissage   (06)
├── core-math/          Haversine, projections Mercator, fit-zoom, ACSM kcal   (02, 03)
├── data/               Data classes + codecs JSON tolérants       (02, 06)
├── domain-session/     Orchestrateur de session, tri participants, agrégation  (01, 02)
├── domain-ble/         Services lunettes + capteurs (logique, file, états)     (04, 05)
└── domain-pose/        Pipeline posture (lissage → classification → payload)   (06)

shared : interfaces (expect/actual ou DI)
├── BleTransport            scan, connexion, MTU, souscriptions, écritures
├── RoomGateway             connexion LiveKit, publishData, events, tracks
├── PoseDetector            initialisation, détection sur frame
├── FrameSource             capture d'image de la piste caméra
├── LocationSource          flux de positions, permission
├── TokenApi                POST /token
├── PreferencesStore        clé/valeur (préférences pré-connexion)
├── PermissionGateway       sollicitation des permissions
└── Wakelock                maintien de l'écran

app-android/   Compose UI
app-ios/       SwiftUI UI
```

## 3. Matrice portable / natif

| Sous-système | Portable (shared) | Natif (plateforme) | Doc |
|---|---|---|---|
| Contrat token HTTP | ✅ modèle + parsing | ✅ client HTTP | 01 |
| Paramètres de salle/encodage | ✅ constantes | — | 01 |
| Tri / agrégation des participants | ✅ fonctions pures | — | 01 |
| Sérialisation télémétrie | ✅ | — | 02 |
| Décodage télémétrie tolérant | ✅ | — | 02 |
| Haversine / conversion vitesse | ✅ | — | 02, 03 |
| Projections Mercator / fit-zoom | ✅ | — | 03 |
| Cache de tuiles | ✅ logique | ⚠️ téléchargement/décodage image | 03 |
| Protocole ActiveLook (trames, texte) | ✅ | — | 04 |
| File de commandes + back-pressure | ✅ (coroutines) | — | 04 |
| HUD : layout, formats, calories | ✅ | — | 04 |
| Parsing HR / CSC / calcul cadence | ✅ | — | 05 |
| Classification d'appareils BLE | ✅ | — | 05 |
| Lissage de pose | ✅ | — | 06 |
| `classifyPosture` (angles/seuils) | ✅ | — | 06 |
| Codec posture + décodage tolérant | ✅ | — | 06 |
| Table des os / palette / projection | ✅ | — | 06 |
| Machine à états de session | ✅ | — | 01, 07 |
| États de contrôle (micro, caméra…) | ✅ état | ⚠️ actions | 07 |
| Transport BLE | interface | ✅ Android BLE / CoreBluetooth | 04, 05 |
| WebRTC / LiveKit | interface | ✅ SDK LiveKit natif | 01 |
| Détection de pose (IA) | interface | ✅ MediaPipe / Vision | 06 |
| Capture de frame | interface | ✅ WebRTC | 06 |
| GPS | interface | ✅ FusedLocation / CLLocation | 03 |
| Permissions | interface | ✅ natif | 07 |
| Rendu UI | ❌ | ✅ Compose / SwiftUI | 07 |

## 4. Interfaces à définir (contrats)

### 4.1 `BleTransport`

```
scan(filter): Flow<List<BleDevice>>
connect(deviceId, timeout): Flow<BleConnectionState>
requestMtu(deviceId, mtu): Int
subscribe(deviceId, service, char): Flow<ByteArray>
write(deviceId, service, char, bytes, withResponse)
disconnect(deviceId)
```
> Utilisé à la fois par les lunettes (04) et les capteurs (05).

### 4.2 `RoomGateway`

```
prepare(url, token)
connect(url, token, fastConnect): Session
publishData(bytes, reliable, topic)
events: Flow<RoomEvent>          // Disconnected, Participant*, DataReceived, Track*
localTracks / remoteParticipants
setMicrophoneEnabled / setCameraEnabled / setCameraPosition / setSpeakerOn
disconnect()
```

### 4.3 `PoseDetector`

```
initialize()
detect(bytes): Pose?             // 33 landmarks + score
dispose()
```

### 4.4 Autres

| Interface | Méthodes essentielles |
|---|---|
| `FrameSource` | `capture(): ByteArray?` (frame de la piste caméra) |
| `LocationSource` | `flow: Flow<Position>`, `hasPermission()`, `requestPermission()` |
| `TokenApi` | `getToken(identity, room): String` |
| `PreferencesStore` | `getBool/putBool(key, value)` |
| `PermissionGateway` | `request(vararg permissions)` |
| `Wakelock` | `enable()`, `disable()` |

## 5. Ordre de portage recommandé

| Étape | Contenu | Justification |
|---|---|---|
| 1 | `core-protocol` + `core-math` + tests | Zéro dépendance plateforme, valeur immédiate |
| 2 | `data` (codecs tolérants) + tests | Formats d'échange figés |
| 3 | `domain-ble` sur `BleTransport` (fake en test) | Logique riche (files, états, parsing) |
| 4 | `domain-pose` sur `PoseDetector` (fake) | Classification testable |
| 5 | `domain-session` sur `RoomGateway` (fake) | Orchestration + agrégation |
| 6 | Intégration plateforme : BLE natif, LiveKit, GPS | Assemblage |
| 7 | UI Compose puis SwiftUI | Dernière couche, spécifiée par `07` |

## 6. Tests prioritaires (logique pure)

| Domaine | Cas de test |
|---|---|
| Protocole ActiveLook | taille/entête/pied de trame, payload texte big-endian, fragmentation MTU |
| File de commandes | ordre FIFO, attente quand flux bloqué, délai inter-commandes |
| Parsing HR | UINT8, UINT16, octets vides |
| Parsing CSC | avec/sans roue, offset dynamique, octets courts |
| Cadence | débordement 16 bits, `timeDelta = 0`, premier échantillon, clamp 0–200 |
| Haversine | paires de référence (connues), symétrie |
| Mercator / fit-zoom | pôles, équateur, bornes de zoom |
| Classification posture | debout / assis / allongé sur jeux de landmarks, landmarks manquants → null |
| Décodage télémétrie | `payload` absent, types string/num, `gps` null, mauvais `type` rejeté |
| Décodage posture | emplacements `payload`/`posture`/racine, libellé manquant → null, indices landmarks invalides |
| Tri participants | parlant > récent > ancienneté, screen share en tête |
| Calories | formule ACSM homme/femme, formule simplifiée, clamps |

## 7. Pièges et dettes connus

| # | Problème | Impact sur le portage |
|---|---|---|
| 1 | `core/livekit_service.dart` non utilisé (remplacé par l'usage direct de la salle) | Référence seulement ; candidate à une `RoomGateway` |
| 2 | `core/api_service.dart` actif (Bearer Firebase, `/token`, `/mobile/rooms`, Egress) | Contrat documenté dans `01` et `MOBILE_RECORDING_WORKFLOW.md` |
| 3 | Widgets non référencés : `smoothed_pose_avatar.dart`, `sound_waveform.dart`, `text_field.dart` | Non portés (ou portés plus tard si besoin) |
| 4 | **Bug** : `PoseAnimationController` construit un contrôleur d'animation avec un `vsync` invalide (`AnimatedGridState()`) — inutilisable tel quel | Réécrire proprement en KMP si l'interpolation est souhaitée |
| 5 | Dépendances déclarées mais inutilisées : `provider`, `flutter_svg`, `flutter_background`, `flutter_foreground_task`, `camera`, `o3d` | Aucune équivalence à porter |
| 6 | `o3d` (avatar 3D) déclaré mais l'avatar associé est orphelin | Fonctionnalité non intégrée |
| 7 | Authentification Firebase Auth (email / mot de passe) | Prévoir l'équivalent Firebase Auth côté KMP |
| 8 | Les libellés de posture sont en **français** et encodés dans les payloads | Décider : garder (compatibilité) ou internationaliser (breaking) |
| 9 | Index `type` des landmarks basé sur l'enum du moteur de pose | **Figer** l'ordre MediaPipe 33 dans une enum partagée |
| 10 | Distance interne en **miles**, affichage en km | Conserver l'unité interne pour la compatibilité des payloads |
| 11 | Schéma token unifié | `POST /token {room}` avec `Authorization: Bearer <Firebase ID token>` |
| 12 | Le test existant (template) est obsolète et échouerait | Le remplacer par les tests de la section 6 |
| 13 | `usesCleartextTraffic="true"` (Android) | À revoir pour la production |

## 8. Constantes à porter telles quelles

| Domaine | Constantes critiques | Doc |
|---|---|---|
| Réseau | `https://api.videolog.app/token`, `wss://livekit.videolog.app`, room `poc-room` | 01 |
| Fréquences | télémétrie 500 ms (2 Hz) ; posture **continue** (débit NPU, repli 100 ms) ; HUD lunettes throttle 2 s | 02, 06, 04 |
| ActiveLook | service `…CB7`, RX `…CBA`, cmdIds `00/01/05/10/22/37/39`, rotation `0x04`, fonts 1/2/3, couleurs `0x0F`/`0x09`, y = 25/85/145/205, MTU 512, chunk 128 | 04 |
| Capteurs | HR `180D/2A37`, CSC `1816/2A5B`, Battery `180F/2A19` | 05 |
| Posture | α = 0.35, seuils 48° / 0.35 / 0.7, confiance = moyenne épaules+hanches, visibilité filtre 0.2 | 06 |
| GPS | distanceFilter 5 m, précision haute, rayon 3958.8 mi, facteur 1.60934, 6 décimales | 03 |
| Carte | 140×140, zoom 18→3, fit 85 %, padding 20 %, tile 256 px | 03 |
| Calories | simplifiée `bpm × 0.05 × t_s / 60` clamp [0,9999] ; ACSM : coefficients −55.0969/0.6309/0.1988/0.2017 et −20.4022/0.4472/−0.1263/0.074, division 4.184 | 04 |

## 9. Checklist de validation du portage

- [ ] Tous les tests de la section 6 passent dans `shared`
- [ ] Émission/réception télémétrie **interopérable** avec l'app Flutter (mêmes JSON)
- [ ] Émission/réception posture interopérable (codec binaire v2 + index landmarks)
- [ ] HUD lunettes : mêmes trames binaires (vérifiable par capture BLE)
- [ ] Capteurs : FC et cadence correctes sur matériel réel (y compris débordement)
- [ ] Carte : cadrage identique sur les mêmes positions (golden tests de projection)
- [ ] Workflow complet : login → salles → token → session (paramètres par défaut)
- [ ] Permissions et behaviours plateforme conformes à `07-ui-behavior.md`
