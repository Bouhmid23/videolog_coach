# 07 — Comportements des écrans, contrôles et interactions

Ce document décrit le comportement de chaque écran et des contrôles, **sans référence au
framework UI**. Il sert de spécification fonctionnelle pour la réimplémentation native
(Compose / SwiftUI).

## 1. Cartographie des écrans

| Écran | Route | Rôle |
|---|---|---|
| Connexion | `/login` | Saisie d'identifiant |
| Accueil | `/home/:username` | Tableau de bord |
| Salles | `/rooms/:username` | Liste des salles |
| Connexion salle | `/connect/:roomName` | Saisie participant + token |
| Pré-connexion | `/prejoin` (pile principale) | Périphériques et options |
| Session | `/room` (pile principale) | Session de coaching |

| Transition | Mécanisme |
|---|---|
| Login → Home | navigation avec identifiant dans le chemin |
| Home → Rooms | navigation avec identifiant |
| Rooms → Connect | navigation avec nom de salle + identifiant en paramètre |
| Connect → PreJoin | navigation avec arguments complets (pile racine) |
| PreJoin → Room | navigation avec salle + écouteur (pile racine) |
| Room → précédent | retour (pop) à la déconnexion |
| PreJoin → arrière | retour + désactivation micro/caméra |
| Erreur de connexion → Home | retour forcé |

## 2. Écran de connexion

| Aspect | Comportement |
|---|---|
| Champs | email, mot de passe, case « Se souvenir de moi » |
| Validation | les deux champs doivent être non vides ; sinon message éphémère (« Veuillez remplir tous les champs ») |
| Identifiant dérivé | `displayName = partie avant "@" de l'email` |
| Authentification | **aucune vérification réseau** (accès fictif en attendant une API) |
| Suite | navigation vers l'accueil avec l'identifiant |

## 3. Écran d'accueil

| Aspect | Comportement |
|---|---|
| Contenu | **statique** : indicateurs codés en dur (charge 78 %, 12 séances, cardio moyen 162 bpm, score 91), carte « Prochaine séance » |
| Action principale | bouton → écran des salles |
| Aucune donnée réelle | aucun appel réseau, aucune persistance |

## 4. Écran des salles

| Aspect | Comportement |
|---|---|
| Contenu | une seule salle : `poc-room` (statique) |
| Action | « Rejoindre » → écran de connexion salle, identifiant propagé |

## 5. Écran de connexion salle

### 5.1 Affichage

| Bloc | Contenu |
|---|---|
| Logo | image de marque |
| Informations | `Room: <nom>`, `Server: <url WebSocket>`, `API: <url API>` |
| Saisie | « Nom du participant » (indice : `ex: driver-01`) |
| Rôle | sélecteur segmenté « Trainee » / « Coach » (défaut : Trainee) |
| Action | bouton « CONNECTER » (indicateur de chargement pendant le traitement) |

### 5.2 Comportement de connexion

```
si nom vide → dialogue d'erreur « Entrer un nom d'utilisateur »
sinon :
    état occupé = true
    POST /token (timeout 10 s)
    succès  → navigation vers la pré-connexion avec les arguments de jonction
    échec   → dialogue d'erreur avec le détail (code + corps)
    toujours → état occupé = false
```

### 5.3 Demande de permissions (Android uniquement)

Au montage : `bluetooth`, `bluetoothConnect`, `camera`, `microphone` — chacune sollicitée ;
un refus définitif est journalisé.

### 5.4 Arguments transmis (JoinArgs)

| Champ | Valeur par défaut |
|---|---|
| `url` | URL LiveKit |
| `token` | obtenu |
| `username` | saisi |
| `role` | `trainee` (ou `coach` si sélectionné) |
| `e2ee` | `false` |
| `e2eeKey` | `null` |
| `simulcast` | `true` |
| `adaptiveStream` | `true` |
| `dynacast` | `true` |
| `preferredCodec` | `VP8` |
| `enableBackupVideoCodec` | `true` si VP9/AV1, sinon `false` |

## 6. Écran de pré-connexion

### 6.1 Composition

| Zone | Contenu |
|---|---|
| Prévisualisation | aperçu caméra 320×240 (ou icône si désactivée) |
| Caméra | interrupteur + liste des caméras + liste des résolutions |
| Microphone | interrupteur + liste des micros |
| Action | bouton « JOIN » (indicateur pendant la connexion) |

### 6.2 Règles de périphériques

| Situation | Comportement |
|---|---|
| Périphérique sélectionné disparu | sélection vidée |
| Plus de périphériques | track associée libérée |
| Activation avec aucun sélectionné | sélection automatique du premier + création de track |
| Changement de périphérique | ancienne track **arrêtée**, nouvelle créée |
| Changement de résolution | nouvelle track créée avec les nouveaux paramètres |
| Chaque changement | persistance immédiate des préférences |

### 6.3 Retour arrière

Désactive caméra **et** micro (libère les tracks), puis revient en arrière.

### 6.4 Connexion

```
construire les options E2EE si demandées
créer l'écouteur d'événements
préparer la connexion
connecter avec fastConnectOptions (micro + caméra courants)
succès → navigation vers la session (pile racine)
échec  → dialogue d'erreur
toujours → retour vers l'accueil (écrans inférieurs détruits)
```

## 7. Écran de session

### 7.1 Composition (zones)

```
┌──────────────────────────────────────────┬─────────────┐
│                                          │             │
│        Flux principal (plein écran)      │  SideSheet  │
│   [overlay squelette / panneau aside]    │  posture    │
│                                          │  (220 px)   │
│                                          │             │
│  ┌────────────────────────────┐          │             │
│  │ Galerie des pairs          │ ← inset  │             │
│  └────────────────────────────┘          │             │
│                        ┌─────────┐       │             │
│                        │ Mini-   │       │             │
│                        │ carte   │       │             │
│                        └─────────┘       │             │
│  ┌──────────────────────────────────┐    │             │
│  │       Barre de contrôles         │    │             │
│  └──────────────────────────────────┘    │             │
└──────────────────────────────────────────┴─────────────┘
```

| Zone | Position | Taille / règle |
|---|---|---|
| Flux principal | plein écran | stats activées, squelette en aside |
| Galerie des pairs | bas-gauche, `bottom: 160` | hauteur 200 + 40 (HUD), largeur item 200, espacement 10 |
| Mini-carte | bas-droit | 140×140, `bottom: 160`, `right: 12` |
| PIP posture | bas-droit (selon bascule) | ~135 px, marge 16 |
| Barre de contrôles | bas, dans les marges sûres | padding horizontal 16, vertical 8 |
| SideSheet | colonne droite | 220 px |

### 7.2 Insets de la galerie (anti-chevauchement)

La galerie recule à droite pour éviter les chevauchements, dans cet ordre de priorité :

| Condition | Inset droit |
|---|---|
| SideSheet ouvert | **240** (largeur panneau + marge) |
| sinon : `max(PIP posture, mini-carte, 16)` | `PIP : 16 + 135` ; `carte : 16 + 140 + 12` |

L'animation de l'inset dure 300 ms (courbe `easeOut`).

### 7.3 Comportements de démarrage / arrêt

| Moment | Action |
|---|---|
| Création | initialisation de l'orchestrateur au premier rendu ; démarrage télémétrie + GPS + capteurs |
| Rôle **Trainee** | détection et publication de posture activées |
| Rôle **Coach** | observateur : aucune publication de posture |
| Android | haut-parleur activé |
| Déconnexion | retour à l'écran précédent |
| Libération | désactivation wakelock, arrêt de tous les flux, libération de la session |

## 8. Barre de contrôles

### 8.1 Boutons

| Contrôle | Comportement mobile | Comportement desktop |
|---|---|---|
| Micro | bascule directe | sélection d'entrée (menu) |
| Caméra on/off | bascule | bascule |
| Bascule caméra | avant ↔ arrière | idem |
| Haut-parleur | bascule (état reflété) | — |
| Sélection sortie audio | — | menu |
| Lunettes BLE | ouvre la feuille BLE ; icône + niveau batterie | idem |
| Capteurs | ouvre la feuille capteurs ; icône favori + point vert de statut | idem |
| Carte | bascule d'affichage de la mini-carte | idem |
| PIP posture | bascule d'affichage du PIP | idem |
| Déconnexion | quitte la session | idem |

### 8.2 États reflétés

| État | Source |
|---|---|
| Micro muet | participant local |
| Caméra active | participant local |
| Position caméra | état front/back |
| Batterie lunettes | flux métriques BLE |
| Capteur cardio connecté | statut HRM |
| Capteur cadence connecté | statut CSC |
| Session lunettes active | état de session BLE |
| Carte / PIP affichés | bascules locales |

## 9. Feuille des lunettes (BLE)

| Aspect | Comportement |
|---|---|
| Ouverture | demande les permissions (`bluetooth`, `bluetoothConnect`, `bluetoothScan`, `location`), puis démarre le scan |
| Liste | devices scannés avec nom et RSSI ; déduplication par identifiant |
| État de connexion | phase détaillée avec couleur + icône (idle / connecting / connected / initializing / ready / disconnecting / disconnected / failed) |
| Action connexion | connexion au device choisi |
| Session | boutons « Démarrer la session » / « Arrêter la session » |
| Déconnexion | bouton de déconnexion |
| Fermeture | arrêt du scan |

**Gestion de l'état de connexion** : le statut de phase est **hiérarchique** ; seul le
passage à l'état `ready` compte comme « connecté » pour l'UI (transition détectée pour
déclencher l'abonnement aux métriques côté orchestration).

## 10. Feuille des capteurs

| Aspect | Comportement |
|---|---|
| Type | feuille déplaçable (hauteur ajustable au scroll) |
| Permissions | mêmes permissions que la feuille BLE, puis scan |
| Sections | **Cardio (HRM)**, **Cadence (CSC)**, **Autres appareils** |
| Appareil inconnu | boutons « Cardio » / « Cadence » pour le rattacher manuellement à l'un des rôles |
| Appareil connecté | bannière avec nom, batterie, état |
| Connexion | une connexion HRM et une cadence **indépendantes** (parallèles) |
| Fermeture | arrêt du scan |

## 11. SideSheet de posture

| Aspect | Comportement |
|---|---|
| Ouverture | sélection d'un participant **distant** dans la galerie |
| Re-sélection du même | bascule (ferme s'il est ouvert, rouvre sinon) |
| Sélection d'un autre | bascule et affiche le nouveau |
| Contenu | titre « Posture » + bouton fermer ; squelette du participant si des données existent, sinon message « Aucune donnée de posture » |
| Taille | 220 px de large, bordure gauche, fond sombre |
| Données affichées | dernière posture reçue du participant sélectionné (sans HUD de données) |

## 12. Visibilité des squelettes

| Aspect | Comportement |
|---|---|
| Ensemble de masquage | par identité de participant distant |
| Bascule | action sur l'entrée du participant |
| Effet | recalcule de la liste (le squelette disparaît/réapparaît) |
| PIP global | une bascule globale contrôle l'affichage des squelettes (PIP + overlays) |

## 13. Notifications et messages

| Type | Usage |
|---|---|
| Dialogue d'erreur | échecs de connexion, erreurs de session, refus de publier |
| Dialogue de déconnexion | confirmation de départ |
| Message éphémère (snackbar) | validation du formulaire de connexion |
| Journal (debug) | erreurs de décodage, erreurs BLE, états de capteurs |

## 14. Gestion des permissions par plateforme

| Permission | Où demandée | Plateforme |
|---|---|---|
| Caméra, micro | écran connexion salle | Android |
| Bluetooth, bluetoothConnect | écran connexion salle | Android |
| Bluetooth, bluetoothConnect, bluetoothScan, location | ouverture feuilles BLE / capteurs | Mobile (hors web) |
| Localisation | au démarrage du suivi GPS (si refusé → abandon silencieux) | Toutes |
| Foreground service | manifeste (caméra, micro, périphériques connectés) | Android |

## 15. Points d'attention pour le portage KMP

| Élément | Recommandation |
|---|---|
| Règles de navigation | Reprendre la cartographie (section 1) comme graphe d'états |
| Insets / géométrie | Valeurs numériques à porter telles quelles (sections 7.1–7.2) |
| États de boutons | Machine à états partagée dans le module commun, rendu natif |
| Feuilles (sheets) | Composants natifs (bottom sheet Compose / SwiftUI sheet) |
| Validation de formulaire | Logique pure (section 2) |
| Permissions | API natives par plateforme |
