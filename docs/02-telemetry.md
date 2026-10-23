# 02 — Télémétrie temps réel

Ce document décrit le canal de télémétrie échangé entre tous les participants d'une
session : format des messages, fréquence, sources de données, calculs dérivés et
consommation côté réception.

## 1. Vue d'ensemble

```
Capteurs BLE (FC, cadence)   +   GPS   +   (vitesse)
            │                      │
            └──────────┬───────────┘
                       ▼
            Agrégation (orchestrateur de session)
                       │  toutes les 500 ms (2 Hz)
                       ▼
        publishData(json, reliable=true, topic="telemetry")
                       │
                       ▼   DataChannel LiveKit
            Tous les pairs reçoivent le message
                       │
                       ▼
        Décodage → modèle RemoteTelemetry → stockage par identité
```

- **Transport** : DataChannel du serveur LiveKit (SFU), messagerie applicative.
- **Topic** : `telemetry`
- **Fiabilité** : `reliable = true` (livraison garantie, ordre préservé).
- **Fréquence d'émission** : **2 Hz** (intervalle de 500 ms).
- **Encodage** : JSON UTF-8.

## 2. Schéma du message émis

```json
{
  "type": "telemetry",
  "ts": 1730000000000,
  "payload": {
    "role": "trainee",
    "speed": 12.4,
    "heart_rate": 145,
    "cadence": 82,
    "gps": { "lat": 48.856600, "lng": 2.352200 }
  }
}
```

### 2.1 Champs

| Chemin | Type | Présent | Description |
|---|---|---|---|
| `type` | string | toujours | `"telemetry"` |
| `ts` | number | toujours | Horodatage epoch millis de l'émission |
| `payload.role` | string | toujours | Rôle choisi à la connexion : `"trainee"` ou `"coach"` |
| `payload.speed` | number \| null | si position disponible | Vitesse en **km/h**, 1 décimale |
| `payload.heart_rate` | number \| null | si capteur connecté | FC en **bpm** |
| `payload.cadence` | number \| null | si capteur connecté | Cadence en **rpm** |
| `payload.gps` | object \| null | si position disponible | `{lat, lng}` en degrés décimaux, **6 décimales** |

> Toute valeur non disponible est envoyée `null` (jamais omise), sauf `gps` qui est
> `null` en entier si aucune position.

### 2.2 Règles d'agrégation à l'émission

| Champ | Source | Condition d'inclusion |
|---|---|---|
| `heart_rate` | Capteur cardio BLE | Uniquement si le capteur cardio est **connecté** ; sinon `null` |
| `cadence` | Capteur cadence BLE | Uniquement si le capteur cadence est **connecté** ; sinon `null` |
| `speed` | Dernière position GPS : `speed_m_s × 3.6`, arrondi 1 décimale | Si une position existe ; sinon `null` |
| `lat` / `lng` | Dernière position GPS, 6 décimales | Si une position existe ; sinon `gps = null` |

> L'émission n'a lieu que si la session est **connectée** ; sinon le tick est ignoré.

## 3. Modèle de réception (`RemoteTelemetry`)

### 3.1 Champs

| Champ | Type | Description |
|---|---|---|
| `heartRate` | int? | FC en bpm |
| `cadence` | double? | Cadence en rpm |
| `speed` | double? | Vitesse en km/h |
| `lat` | double? | Latitude |
| `lng` | double? | Longitude |
| `role` | string? | Rôle (`trainee`, `coach`) |
| `receivedAt` | date | Horodatage de réception local |
| `hasHrm` | bool (calculé) | `heartRate != null` |

### 3.2 Règles de décodage tolérant

1. **Filtre d'entrée** : le message n'est accepté que si `type == "telemetry"`.
   Sinon → `null` (rejet silencieux).
2. **Dépliage** : si `payload` est un objet, ses champs sont lus ; sinon les champs sont
   lus à la racine du message (tolérance de format).
3. **Lecture GPS** : `gps` est un objet `{lat, lng}` ; chaque valeur accepte `number`
   ou `string` interprétable.
4. **Types numériques** :
   - `heart_rate` : `int` direct ; `double` arrondi ; autre `num` → `toInt()` ; sinon `null`.
   - `cadence`, `speed` : `num` → `double` ; `string` parsé ; sinon `null`.
5. **Toute erreur de décodage** produit `null` (jamais d'exception propagée).

### 3.3 Routage à la réception

```
DataReceived → décodage UTF-8 → JSON
   ├─ topic == "telemetry"  OU  map["type"] == "telemetry"
   │      → RemoteTelemetry.tryParse
   │      → stockage: map[identité du participant émetteur] = modèle
   │      → notification UI
   ├─ topic == "posture"  OU  map["type"] == "posture"
   │      → RemotePosture.tryParse (voir 06-pose-detection.md)
   └─ sinon → ignoré
```

- Le stockage est une **carte indexée par identité** du participant : un nouveau message
  **remplace** le précédent (état « dernière valeur connue »).
- À la déconnexion d'un participant, son entrée est **supprimée**.
- Les postures dont l'identité n'est plus dans la salle sont également purgées lors du
  recalcul.

## 4. Télémétrie locale (vue agrégée)

L'orchestrateur expose une vue « télémétrie locale » combinant les sources directes :

| Champ | Condition | Transformation |
|---|---|---|
| `heartRate` | capteur cardio connecté | valeur bpm brute |
| `cadence` | capteur cadence connecté | valeur rpm brute (→ double) |
| `speed` | dernière position GPS | `speed_m_s × 3.6`, 1 décimale |
| `lat` / `lng` | dernière position GPS | bruts |
| `role` | toujours | rôle choisi (`trainee` / `coach`) |
| `receivedAt` | toujours | heure courante |

Cette vue est utilisée pour :
- l'affichage du HUD local,
- la mini-carte (position « Moi »),
- la construction du payload émis.

## 5. Consommation côté pairs

Pour chaque pair, la dernière télémétrie reçue alimente :
- les **pastilles HUD** de l'entrée vidéo (FC / vitesse / cadence),
- les **marqueurs de carte** (lat/lng),
- le **panneau latéral** et les vues de détail.

## 6. Formules associées

### 6.1 Conversion vitesse
```
speed_kmh = round(speed_m_s * 3.6, 1)
```
`speed_m_s` provient du fournisseur de position (dernière position connue).

### 6.2 Arrondi des coordonnées
```
lat = round(lat, 6)   // ≈ 0.11 m de précision
lng = round(lng, 6)
```

## 7. Points d'attention pour le portage KMP

| Élément | Nature | Recommandation |
|---|---|---|
| Sérialisation / désérialisation du payload | Pur | Module commun, avec tests de tolérance (types string/num, `payload` absent) |
| Horodatage `ts` | Pur | Epoch millis UTC |
| Agrégation des sources | Orchestration | Module commun ; dépend des interfaces `HeartRateSource`, `CadenceSource`, `LocationSource` |
| publication `publishData` | Transport | Derrière l'interface `RoomGateway` |
| Stockage par identité + purge | Orchestration | Map observable côté commun |

## 8. Exemple de cycle complet

```
t=0.0s  capteur cardio → 145 bpm ; GPS → 34.7 m/s
        émission: speed=124.9, heart_rate=145, cadence=null, gps={...}
        (note: 34.7 m/s → 124.9 km/h, valeur de test realiste pour vélo)

t=0.5s  même payload rafraîchi
t=1.0s  déconnexion du capteur → heart_rate=null (le champ reste présent)
t=1.5s  perte GPS → gps=null, speed=null
```
