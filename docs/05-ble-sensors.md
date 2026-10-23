# 05 — Capteurs sport BLE standard (cardio & cadence)

Ce document décrit l'intégration des capteurs Bluetooth standardisés (Bluetooth SIG) :
moniteur de fréquence cardiaque (HRM) et capteur de cadence cycliste (CSC).

## 1. Standards implémentés

| Service | UUID service | Characteristic | UUID char | Donnée |
|---|---|---|---|---|
| Heart Rate (0x180D) | `0000180D-0000-1000-8000-00805F9B34FB` | Heart Rate Measurement | `00002A37-0000-1000-8000-00805F9B34FB` | FC |
| Cycling Speed & Cadence (0x1816) | `00001816-0000-1000-8000-00805F9B34FB` | CSC Measurement | `00002A5B-0000-1000-8000-00805F9B34FB` | Cadence |
| Battery (0x180F) | `0000180F-0000-1000-8000-00805F9B34FB` | Battery Level | `00002A19-0000-1000-8000-00805F9B34FB` | Batterie |

## 2. Architecture du service

Un service gère **deux connexions indépendantes** : cardio (HRM) et cadence (CSC).
Chacune a sa propre connexion, ses souscriptions, son statut et son flux de données.

```
Scan (sans filtre) ─→ Classification côté client ─→ Connexion HRM et/ou Cadence
                                                          │
                                            Souscription measurement + battery
                                                          │
                                            Flux: heartRateStream / cadenceStream
```

## 3. Découverte et classification

### 3.1 Scan

| Paramètre | Valeur |
|---|---|
| Filtre de services | **aucun** (`withServices: []`) |
| Mode | `lowLatency` |
| Déduplication | par identifiant ; liste complète réémise |

> **Pourquoi sans filtre** : certains capteurs (ex. : produits Decathlon) n'annoncent pas
> leurs UUID de service dans la réponse de scan ; un filtre les exclurait silencieusement.
> La classification est donc faite côté client.

### 3.2 Règles de classification

```
hrm détecté si :
    un serviceUuid contient "180d"
    OU le nom contient "hrm" / "heart"

cadence détectée si :
    un serviceUuid contient "1816"
    OU le nom contient "cadence" / "csc" / "tilt"

Priorité :
    si hrm ET cadence → hrm      (capteur combiné, le cardio prime)
    sinon si hrm      → hrm
    sinon si cadence  → cadence
    sinon              → unknown
```

> Le nom est comparé en minuscules ; la recherche par sous-chaîne sur les UUID est
> également en minuscules.

## 4. Modèles de données

### 4.1 Type de capteur

`hrm` | `cadence` | `unknown`

### 4.2 État de connexion

`disconnected` | `connecting` | `connected` | `failed`

### 4.3 Statut (`SensorStatus`)

| Champ | Type | Description |
|---|---|---|
| `type` | type de capteur | HRM ou cadence |
| `state` | état | Voir 4.2 |
| `deviceId` | string? | Identifiant du périphérique |
| `deviceName` | string? | Nom affichable |
| `error` | string? | Détail d'erreur (état `failed`) |
| `battery` | int? | Niveau 0–100 |
| `isConnected` | bool (calculé) | `state == connected` |
| `isBusy` | bool (calculé) | `state == connecting` |

## 5. Connexion

### 5.1 Workflow (identique pour HRM et cadence)

```
1. Si déjà connecté à ce deviceId → ne rien faire (idempotent)
2. Déconnexion préalable de l'ancien capteur
3. state = connecting → émission du statut
4. Connexion (timeout 10 s)
5. Au statut "connected" :
      a. state = connected → émission
      b. Souscrire la caractéristique de mesure (0x2A37 ou 0x2A5B)
      c. Souscrire la batterie (si disponible)
6. Au statut "disconnected" :
      a. Réinitialiser deviceId, dernière valeur, état interne
      b. state = disconnected → émission
      c. Annuler les souscriptions
7. En erreur : state = failed + détail
```

### 5.2 Batterie

- Souscription best-effort : si la caractéristique n'existe pas, l'erreur est ignorée
  (beaucoup de capteurs ne l'exposent pas).
- À réception : `battery = clamp(octet, 0, 100)`, puis émission du statut mis à jour.

## 6. Parsing des mesures

### 6.1 Heart Rate Measurement (0x2A37)

```
Octet 0 : Flags
    bit 0 : 0 = FC sur UINT8, 1 = FC sur UINT16
    bit 1 : Energy Expended présent
    bit 2 : RR-Interval présent
Octet 1+ : valeur FC (1 ou 2 octets selon le bit 0)
```

**Algorithme :**
```
si aucun octet → null
isUint16 = (flags & 0x01) == 1
offset   = isUint16 ? 2 : 1
si longueur < offset → null
isUint16 ? (bytes[1] | bytes[2] << 8)  :  bytes[1]
```

> Seule la FC est extraite ; energy expended et RR-intervals sont ignorés.

### 6.2 CSC Measurement (0x2A5B)

```
Octet 0 : Flags
    bit 0 : données de roue présentes (Wheel Revolution Data)
    bit 1 : données de manivelle présentes (Crank Revolution Data)
Si bit 1 (manivelle) :
    Cumulative Crank Revolutions : UINT16 (2 octets, little-endian)
    Last Crank Event Time         : UINT16 (2 octets, unité 1/1024 s)
```

**Algorithme de localisation des données :**
```
si aucun octet → null
si bit 1 non défini → null          (pas de données de manivelle → pas de cadence)
si longueur < 5 → null
offset = 1                            (après les flags)
si bit 0 défini → offset += 6         (roue : cumulé 4B + dernier événement 2B)
si longueur < offset + 4 → null
crankRev  = u16le(bytes[offset..offset+1])
crankTime = u16le(bytes[offset+2..offset+3])
```

## 7. Calcul de la cadence (RPM)

```
état précédent : lastCrankRev, lastCrankTime   (null au premier échantillon)

// met à jour l'état AVANT de calculer (l'échantillon courant devient le précédent)
revDelta  = currentRev  - prevRev
si revDelta  < 0 → revDelta  += 65536          // débordement 16 bits
timeDelta = currentTime - prevTime
si timeDelta < 0 → timeDelta += 65536          // débordement 16 bits

si prevRev ou prevTime null → null             // premier échantillon
si timeDelta == 0 → null                       // division impossible

secondes  = timeDelta / 1024.0
rpm       = (revDelta / secondes) × 60.0
résultat  = round(rpm) clampé à [0, 200]
```

**Points critiques :**
- Le débordement 16 bits (65536) est géré **séparément** pour les révolutions et le temps.
- L'unité de temps est **1/1024 seconde**.
- La cadence est bornée à 0–200 RPM (valeurs réalistes).
- Au premier échantillon, aucun résultat n'est émis (besoin de deux échantillons).

## 8. Flux exposés

| Flux | Type | Description |
|---|---|---|
| `devicesStream` | liste | Résultats du scan |
| `heartRateStream` | int | FC en bpm, à chaque mesure valide |
| `cadenceStream` | int | Cadence en rpm, à chaque mesure valide |
| `hrmStatusStream` | statut | État du capteur cardio |
| `cscStatusStream` | statut | État du capteur cadence |

**Getters :** `isHrmConnected`, `isCadenceConnected`, `lastHeartRate`, `lastCadence`,
`hrmStatus`, `cscStatus`, `hrmDeviceId`, `cscDeviceId`, `discoveredDevices`,
`classifyDevice(device)`.

## 9. Intégration dans la session

| Aspect | Comportement |
|---|---|
| Démarrage des écoutes | Au démarrage de la session (souscriptions aux 4 flux) |
| Utilisation de la FC | Alimente la télémétrie, le HUD, les lunettes |
| Utilisation de la cadence | Alimente la télémétrie, le HUD, les lunettes |
| Condition d'envoi | Les valeurs ne sont émises dans la télémétrie **que si** le capteur correspondant est connecté |
| Permissions | Sollicitées à l'ouverture de la feuille capteurs : `bluetooth`, `bluetoothConnect`, `bluetoothScan`, `location` |
| Feuille de sélection | Sections cardio / cadence ; les appareils « inconnus » peuvent être rattachés manuellement à l'une ou l'autre |

## 10. Points d'attention pour le portage KMP

| Élément | Nature | Recommandation |
|---|---|---|
| Classification d'appareil | Pur | Fonction pure + tests (noms, UUIDs, capteur combiné) |
| Parsing HR (0x2A37) | Pur | Fonction pure + tests UINT8/UINT16 |
| Parsing CSC (0x2A5B) | Pur | Fonction pure + tests (avec/sans roue) |
| Calcul de cadence | Pur | Fonction pure avec état ; **tests débordement 16 bits** et timeDelta=0 |
| Transport BLE | Plateforme | Interface `BleTransport` (partagée avec les lunettes) |
| Deux connexions indépendantes | Logique | Deux instances ou sous-états dans un service commun |
