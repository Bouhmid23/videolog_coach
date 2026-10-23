# 04 — Lunettes connectées ActiveLook / Engo (protocole BLE propriétaire)

Ce document décrit l'intégralité du sous-système des lunettes de réalité augmentée
(ActiveLook / Engo) : découverte, connexion, protocole binaire, cycle de session d'affichage
et rendu du HUD de sport.

## 1. Vue d'ensemble

```
Scan BLE ─→ Connexion ─→ Négociation MTU ─→ Souscription de 5 caractéristiques
                                                    │
                                         Envoi commandes (file sérialisée)
                                                    │
   ┌────────────────────────────────────────────────┴──────────────────────────┐
   │  Session d'affichage : power on → luminosité max → READY → 3-2-1-GO       │
   │  puis, 2× par seconde : HOLD → CLEAR → textes → FLUSH (rendu atomique)   │
   └───────────────────────────────────────────────────────────────────────────┘
```

Les lunettes sont un **périphérique de sortie** (HUD de sport) : l'application y affiche
distance, FC, calories et cadence. Le casque est en **miroir horizontal** (système optique),
ce qui impose une compensation de rotation sur le texte.

## 2. Identification GATT

### 2.1 UUIDs du service propriétaire

| Rôle | UUID |
|---|---|
| Service | `0783B03E-8535-B5A0-7140-A304D2495CB7` |
| TX (notifications → app) | `0783B03E-8535-B5A0-7140-A304D2495CB8` |
| RX (commandes ← app) | `0783B03E-8535-B5A0-7140-A304D2495CBA` |
| Control (contrôle de flux) | `0783B03E-8535-B5A0-7140-A304D2495CB9` |
| Gesture | `0783B03E-8535-B5A0-7140-A304D2495CBB` |
| Touch | `0783B03E-8535-B5A0-7140-A304D2495CBC` |

### 2.2 Service batterie standard (Bluetooth SIG)

| Rôle | UUID |
|---|---|
| Service Battery | `0000180F-0000-1000-8000-00805F9B34FB` |
| Characteristic Level | `00002A19-0000-1000-8000-00805F9B34FB` |

### 2.3 Paramètres de liaison

| Paramètre | Valeur |
|---|---|
| MTU cible | 512 octets |
| MTU effectif utile | `MTU négocié − 3` |
| Taille de fragment max | 128 octets (plancher : 20) |
| Timeout de connexion | 12 secondes |
| Délai entre commandes en file | 8 ms |
| Attente si flux bloqué | 20 ms (boucle) |
| Délai entre fragments | 5 ms |

## 3. Protocole binaire

### 3.1 Format de trame (§3.1)

```
[0xFF] [cmdId] [CmdFormat=0x00] [Length] [Data...] [0xAA]
```

| Octet | Taille | Description |
|---|---|---|
| `0xFF` | 1 | Début de trame (header) |
| `cmdId` | 1 | Identifiant de commande |
| `0x00` | 1 | Format de commande |
| `Length` | 1 | Taille totale = `5 + len(Data)` (header 4 + footer 1 + data) |
| `Data` | n | Données spécifiques à la commande |
| `0xAA` | 1 | Fin de trame (footer) |

**Réception (TX)** : une trame valide doit faire ≥ 5 octets, commencer par `0xFF` et finir
par `0xAA`. `data = bytes[4 .. len-2]`.

### 3.2 Commandes émises

| cmdId | Nom | Données | Usage |
|---|---|---|---|
| `0x00` | Display Power | `0x01` allumer / `0x00` éteindre | Début/fin de session |
| `0x01` | Clear | *(vide)* | Effacer l'écran |
| `0x05` | Battery | *(vide)* | Demander le niveau batterie |
| `0x10` | Luminance | `0x0F` = niveau 15 (max) | Luminosité pour le sport extérieur |
| `0x22` | ALS only | `0x00` = désactiver | Désactive la luminosité automatique |
| `0x32` | Line | — | Ligne (non utilisée dans l'app actuelle) |
| `0x37` | Text display | voir 3.4 | Afficher du texte |
| `0x39` | Hold/Flush | `0x00` hold, `0x01` flush, `0xFF` reset-flush | Rendu atomique |

### 3.3 Contrôle de flux (§3.5) — caractéristique Control

| Valeur reçue | Signification | Réaction |
|---|---|---|
| `0x01` | On peut envoyer | `_canSendData = true` |
| `0x02` | Buffer à 75 % : pause | `_canSendData = false`, journal d'avertissement |
| `≥ 0x03` | Erreur firmware | `_canSendData = false`, journal avec code hexadécimal |

La file d'envoi **attend** (20 ms / cycle) tant que `_canSendData == false`.

### 3.4 Commande Texte (§5.7) — payload cmdId `0x37`

```
s16 x   (2 octets big-endian)   coin supérieur-gauche du 1er caractère
s16 y   (2 octets big-endian)
u8  r   (1 octet)               rotation — 0x04 pour compensation miroir Engo
u8  f   (1 octet)               id de font (1, 2 ou 3)
u8  c   (1 octet)               couleur niveaux de gris 0–15
str     (n octets)              ASCII, sans null-terminator (le footer 0xAA termine)
```

### 3.5 Constantes d'affichage

| Constante | Valeur | Signification |
|---|---|---|
| Largeur écran | 304 px | Origine (0,0) en haut-gauche, X → droite, Y → bas |
| Hauteur écran | 256 px | |
| Rotation texte | `0x04` | Compense le miroir optique des lunettes Engo (0x00 = texte inversé) |
| Couleur blanc max | `0x0F` | Valeurs 15 |
| Couleur gris (labels) | `0x09` | Valeur 9 |
| Font 1 (small) | ~16 px | Labels (DIST, BPM…) ; largeur ~10 px/car |
| Font 2 (big) | ~24 px | Compte à rebours ; largeur ~14 px/car |
| Font 3 (value) | ~32 px | Valeurs numériques ; largeur ~20 px/car |

> Seules les fonts 1, 2, 3 existent par défaut dans le firmware ; une font inconnue fait
> échouer silencieusement l'affichage.

## 4. Modèles de données

### 4.1 Phase de connexion (`BleConnectionPhase`)

| Phase | Signification |
|---|---|
| `idle` | Prêt pour une connexion |
| `connecting` | Connexion en cours |
| `connected` | Liaison établie |
| `initializing` | Initialisation (MTU, souscriptions, session) |
| `ready` | Lunettes prêtes / session active |
| `disconnecting` | Déconnexion en cours |
| `disconnected` | Déconnecté |
| `failed` | Connexion échouée |

### 4.2 Statut de connexion (`BleConnectionStatus`)

| Champ | Type | Description |
|---|---|---|
| `phase` | phase | Phase courante |
| `deviceId` | string? | Périphérique concerné |
| `message` | string | Message lisible (français) |
| `error` | string? | Détail d'erreur |
| `updatedAt` | date | Dernière mise à jour |
| `isBusy` | bool (calculé) | `connecting`, `connected`, `initializing` ou `disconnecting` |

État initial : `idle` / « Prêt pour une connexion BLE ».

### 4.3 Métriques sportives (`SportMetrics`)

| Champ | Type | Description |
|---|---|---|
| `distanceMiles` | double | Distance (miles, défaut 0) |
| `bpm` | int | Fréquence cardiaque |
| `kcal` | int | Calories |
| `battery` | int? | Batterie 0–100 |
| `gestureDetected` | bool? | Geste détecté |
| `touchDetected` | bool? | Toucher détecté |

> Les flux de gestes/toucher/batterie émettent des instances **partielles** (les autres
> champs à leur valeur par défaut) : le consommateur doit fusionner l'état.

## 5. Cycle de vie

### 5.1 Découverte (scan)

| Paramètre | Valeur |
|---|---|
| Filtre de services | aucun (tous les périphériques) |
| Mode de scan | `lowLatency` |
| Déduplication | par identifiant ; la liste complète est réémise à chaque découverte |

### 5.2 Connexion (`connectAndListen`)

```
1. Déconnexion préalable si déjà connecté
2. phase = connecting (« Connexion BLE... »)
3. Souscription à l'état de connexion (timeout 12 s)
4. Au statut "connected" :
      a. phase = connected (« Connexion établie »)
      b. phase = initializing (« Initialisation... »)
      c. Négocier MTU 512 → utile = MTU − 3  (fallback 20 si échec)
      d. Souscrire les 5 caractéristiques du service + batterie
      e. Session d'affichage inactive ; pause 200 ms
      f. Envoyer la commande Batterie (cmdId 0x05)
      g. phase = ready (« Lunettes prêtes »)
5. Au statut "disconnected" :
      a. deviceId = null, session inactive
      b. phase = disconnected
      c. Annuler toutes les souscriptions
6. En cas d'erreur : phase = failed (« Connexion échouée ») + détail
```

### 5.3 Souscriptions

| Caractéristique | Traitement |
|---|---|
| **TX** | Parsing des trames ; si `cmdId == 0x05` (batterie) et data non vide → `battery = clamp(data[0], 0, 100)` |
| **Control** | Contrôle de flux (voir 3.3) |
| **Gesture** | `data[0] == 0x01` → `gestureDetected = true` |
| **Touch** | `data[0] == 0x01` → `touchDetected = true` |
| **Battery (SIG)** | `battery = clamp(data[0], 0, 100)` |

### 5.4 File de commandes

- File FIFO de tuples `(deviceId, commandBytes)`.
- Un drainer unique consomme la file, **dans l'ordre** :
  - si le flux est bloqué (`_canSendData == false`) → attendre 20 ms, réessayer ;
  - envoyer, puis attendre **8 ms** avant la suivante.
- L'envoi d'une trame de plus de `chunk` octets est **fragmenté** (sous-listes de `chunk`
  octets, 5 ms entre fragments).

## 6. Session d'affichage

### 6.1 Démarrage (`startDisplaySession`)

```
1. phase = initializing (« Démarrage session... »)
2. Power ON                      (cmdId 0x00, data 0x01)      [pause 300 ms]
3. Désactiver l'ALS uniquement   (cmdId 0x22, data 0x00)       — conserve le geste
4. Luminosité max                (cmdId 0x10, data 0x0F)       [pause 100 ms]
5. ResetFlush                    (cmdId 0x39, data 0xFF)       [pause 100 ms]
6. Clear                         (cmdId 0x01)                  [pause 300 ms]
      — efface « Connection successful » affiché par le firmware
7. Écran READY 1,5 s
8. Compte à rebours 3 → 2 → 1 → GO!  (1 s chacun ; GO! 800 ms)
9. ResetFlush + Clear
10. phase = ready (« Session ActiveLook active »), session active = true
```

**Écran READY** :
- HOLD → CLEAR → « READY » (font 3, blanc, centré verticalement) →
  « Session en cours... » (font 1, gris, 8 px en dessous) → FLUSH.

**Compte à rebours** : pour chaque étape, HOLD → CLEAR → chiffre (font 2, blanc,
centré) → FLUSH, puis pause.

### 6.2 Arrêt (`stopDisplaySession`)

```
1. phase = disconnecting (« Arrêt session... »)
2. HOLD → CLEAR → « Session terminee » (font 1, blanc, centré) → FLUSH
3. Pause 1 s
4. Power OFF (cmdId 0x00, data 0x00)
5. phase = ready (« Session arrêtée »), session active = false
```

### 6.3 Affichage du HUD (rendu atomique)

Déclenché par l'orchestrateur (voir plus bas), **throttlé à 1 trame / 2 s max**, et
**uniquement si** un device est connecté, la session est active et le flux est autorisé.

```
HOLD  (cmdId 0x39, data 0x00)          ← fige l'affichage
CLEAR (cmdId 0x01)                     ← efface l'ancien contenu
  → texte DIST  (x=250, y=25,  font 3, blanc)
  → texte BPM   (x=250, y=85,  font 3, blanc)
  → texte KCAL  (x=250, y=145, font 3, blanc)
  → texte RPM   (x=250, y=205, font 3, blanc)
FLUSH (cmdId 0x39, data 0x01)          ← affiche d'un coup (pas de scintillement)
```

**Format des chaînes :**

| Zone | Format | Exemple | Conversion |
|---|---|---|---|
| DIST | `{km:.2} km` | `12.34 km` | `miles × 1.60934` |
| BPM | `{bpm} bpm` | `145 bpm` | clamp 30–220 |
| KCAL | `{kcal} kcal` | `320 kcal` | clamp 0–9999 |
| RPM | `{rpm} rpm` | `82 rpm` | `cadence ?? 0` |

**Coordonnées verticales (y du haut du texte) :**

| Élément | y |
|---|---|
| Valeur DIST | 25 |
| Valeur BPM | 85 |
| Valeur KCAL | 145 |
| Valeur RPM | 205 |
| Marge horizontale de sécurité | 16 |
| Zone utile recommandée (§6.4) | x ∈ [8, 295], y ∈ [8, 247] |

> Les labels (« DIST », « BPM »…) sont définis par les positions de séparation du
> layout 3+1 zones ; l'app actuelle n'affiche **que les valeurs** (labels commentés).

### 6.4 Calcul des calories affichées

L'orchestrateur calcule, pour l'affichage lunettes :

```
kcal = round(heartRate × 0.05 × tempsÉcoulé_s / 60)   clampé à [0, 9999]
```

où `tempsÉcoulé_s` est le compteur de session (incrémenté de 0.5 s à chaque tick de
télémétrie, soit le temps écoulé depuis le début de l'envoi).

**Alternative documentée** (formule ACSM, non utilisée à l'écran actuel mais exposée
comme méthode utilitaire) :

```
Homme  : kcal = ((-55.0969 + 0.6309×bpm + 0.1988×poids_kg + 0.2017×âge) / 4.184) × minutes
Femme  : kcal = ((-20.4022 + 0.4472×bpm − 0.1263×poids_kg + 0.074×âge)  / 4.184) × minutes
```

## 7. Intégration dans la session

| Aspect | Comportement |
|---|---|
| Déclencheur d'affichage | Chaque tick de télémétrie (2 Hz) **si** FC disponible |
| Throttle | Au plus une trame HUD toutes les 2 secondes |
| Métriques envoyées | distance cumulée (miles), FC, calories, cadence |
| Abonnement métriques | L'orchestrateur s'abonne après connexion (callback « connecté ») |
| Batterie | Remontée via le flux métriques → icône dans la barre de contrôles |
| Demande de permissions | Au moment d'ouvrir la feuille BLE : `bluetooth`, `bluetoothConnect`, `bluetoothScan`, `location` |
| Déconnexion | Annulation de l'abonnement métriques, remise à zéro de l'état |

## 8. Flux exposés (résumé)

| Flux | Type d'élément | Description |
|---|---|---|
| `devicesStream` | liste de devices | Résultats de scan (liste complète réémise) |
| `metricsStream` | métriques | FC/calories/distance, batterie, gestes, touchers |
| `connectionStream` | état de connexion natif | États brut du transport BLE |
| `connectionStatusStream` | statut | Phases + messages (voir 4.2) |

## 9. Points d'attention pour le portage KMP

| Élément | Nature | Recommandation |
|---|---|---|
| Format de trame, cmdIds, payload texte | Protocole pur | **Haute priorité** — testable sans matériel |
| File de commandes + back-pressure | Logique concurrente | Coroutine KMP avec `Mutex` + état `_canSendData` |
| Fragmentation MTU | Pur | Fonction pure |
| Parsing RX (batterie) | Pur | Fonction pure |
| Layout HUD (coordonnées, formats) | Pur | Data object de constantes |
| Calcul de calories (ACSM) | Pur | Fonction pure + tests |
| Transport BLE | Plateforme | Interface `BleTransport` (Android : BLE natif, iOS : CoreBluetooth) |
| Permissions | Plateforme | À solliciter avant scan sur Android 12+ |

**Piège Connue** : la compensation de rotation `0x04` a été validée expérimentalement
sur Engo — la conserver telle quelle pour tout matériel équivalent (miroir optique).
