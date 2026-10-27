# 07 — Comportements des écrans, contrôles et interactions

Ce document décrit le comportement de chaque écran et des contrôles, **sans référence au
framework UI**. Il sert de spécification fonctionnelle pour la réimplémentation native
(Compose / SwiftUI).

## 1. Cartographie des écrans

| Écran | Route | Rôle |
|---|---|---|
| Connexion | `/login` | Saisie email / mot de passe Firebase |
| Salles | `/rooms` | Liste réelle des sessions autorisées |
| Connexion salle | `/connect/:roomName` | Compte Firebase + token LiveKit |
| Session | `/room` (pile principale) | Session de coaching + contrôle Egress |

| Transition | Mécanisme |
|---|---|
| Route protégée sans session | redirection vers `/login` |
| Login → Rooms | redirection automatique après connexion Firebase |
| Rooms → Connect | navigation avec la room sélectionnée (nom, participants, enregistrement, `can_control_recording`) |
| Connect → Room | connexion avec les paramètres par défaut, puis remplacement de l'écran |
| Room → précédent | retour (pop) vers `/rooms` à la déconnexion |
| Erreur de connexion → Connect | dialogue d'erreur, l'écran reste affiché |
| Déconnexion | `signOut()` Firebase → redirection vers `/login` |

## 2. Écran de connexion

| Aspect | Comportement |
|---|---|
| Champs | email, mot de passe, case « Se souvenir de moi » |
| Validation | les deux champs doivent être non vides ; sinon message éphémère |
| Authentification | **Firebase Auth** (`signInWithEmailAndPassword`) ; le mot de passe n'est jamais envoyé à l'API Videolog |
| Token | l'ID token Firebase est demandé à chaque appel API (`getIdToken`) |
| Erreurs | messages traduits (identifiants invalides, réseau, trop de tentatives, compte désactivé) |
| Déconnexion | `signOut()` ; si « Se souvenir de moi » est décoché, la session est effacée au prochain démarrage |
| Suite | navigation vers `/rooms` |

## 3. Écran des salles

| Aspect | Comportement |
|---|---|
| En-tête | salutation, nombre de sessions, sessions en direct, enregistrements en cours |
| Contenu | cartes issues de `GET /mobile/rooms` : nom, statut (disponible / en direct / enregistrement), nombre de participants, droit de contrôle Egress, dernière activité |
| Action carte | toute la carte ou le bouton « Rejoindre la session » ouvre l'écran de connexion salle |
| États | chargement, erreur avec « Réessayer », liste vide avec « Actualiser », rafraîchissement par glissement |
| Actualisation | bouton dans l'en-tête et glissement vers le bas ; la room sélectionnée est transmise à l'écran suivant |

## 4. Écran de connexion salle

### 4.1 Affichage

| Bloc | Contenu |
|---|---|
| Session | nom de la session, statut (prête / participants / enregistrement), contrôle Egress, connexion sécurisée |
| Compte | initiales, email Firebase, état d'authentification |
| Configuration | caméra avant 640×480 · 30 fps, microphone activé, réglages modifiables en session |
| Information | entrée directe, sans écran de prévisualisation |
| Action | bouton « REJOINDRE MAINTENANT » fixé en bas, avec étapes de progression (préparation, connexion, activation média) |

### 4.2 Progression

| Étape | Libellé |
|---|---|
| Préparation | `PRÉPARATION...` |
| Connexion LiveKit | `CONNEXION...` |
| Publication micro / caméra | `ACTIVATION MÉDIA...` |
| Repos | `REJOINDRE MAINTENANT` |

### 4.3 Comportement de connexion

```
état occupé = true
Authorization: Bearer <Firebase ID token>
POST /token { "room": "<room>" } (timeout 15 s)
créer la Room LiveKit et l'écouteur d'événements
préparer puis connecter (nouvelle tentative unique avec un token rafraîchi)
publier le micro et la caméra avant avec les paramètres par défaut
succès  → pushReplacement vers /room (retour vers /rooms à la sortie)
échec   → dialogue d'erreur avec le message serveur (401 / 403 / 404)
toujours → état occupé = false
```

### 4.4 Demande de permissions (Android uniquement)

Au montage : `bluetooth`, `bluetoothConnect`, `camera`, `microphone` — chacune sollicitée ;
un refus définitif est journalisé.

### 4.5 Paramètres de connexion par défaut

| Paramètre | Valeur |
|---|---|
| Microphone | activé, capture audio par défaut |
| Caméra | avant, 640×480, 30 fps max |
| `adaptiveStream` | `true` |
| `dynacast` | `true` |
| `simulcast` | `false` |
| Codec vidéo | `H264` (codec de secours activé) |
| E2EE | désactivé |
| Rôle | `trainee` |
| `canControlRecording` | `can_control_recording` renvoyé par `GET /mobile/rooms` |

## 5. Connexion sans écran de pré-connexion

Il n'y a **plus d'écran PreJoin** : la room est rejointe directement depuis l'écran de
connexion salle. Le micro et la caméra avant sont publiés avec les paramètres par défaut ;
l'utilisateur peut ensuite les modifier depuis la barre de contrôles de la session.

## 6. Écran de session

### 6.1 Composition (zones)

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

### 6.2 Insets de la galerie (anti-chevauchement)

La galerie recule à droite pour éviter les chevauchements, dans cet ordre de priorité :

| Condition | Inset droit |
|---|---|
| SideSheet ouvert | **240** (largeur panneau + marge) |
| sinon : `max(PIP posture, mini-carte, 16)` | `PIP : 16 + 135` ; `carte : 16 + 140 + 12` |

L'animation de l'inset dure 300 ms (courbe `easeOut`).

### 6.3 Comportements de démarrage / arrêt

| Moment | Action |
|---|---|
| Création | initialisation de l'orchestrateur au premier rendu ; démarrage télémétrie + GPS + capteurs |
| Rôle **Trainee** | détection et publication de posture activées |
| Rôle **Coach** | observateur : aucune publication de posture |
| Android | haut-parleur activé |
| Déconnexion | retour à l'écran précédent |
| Libération | désactivation wakelock, arrêt de tous les flux, libération de la session |

## 7. Barre de contrôles

### 7.1 Boutons

| Contrôle | Comportement mobile | Comportement desktop |
|---|---|---|
| Micro | bascule directe | sélection d'entrée (menu) |
| Caméra on/off | bascule | bascule |
| Bascule caméra | avant ↔ arrière | idem |
| Haut-parleur | bascule (état reflété) | — |
| Sélection sortie audio | — | menu |
| Lunettes BLE | ouvre la feuille Engo ; icône lunettes + niveau batterie | idem |
| Capteurs | ouvre la feuille capteurs ; icône favori + point vert de statut | idem |
| Carte | bascule d'affichage de la mini-carte | idem |
| PIP posture | bascule d'affichage du PIP | idem |
| Déconnexion | quitte la session | idem |

### 7.2 États reflétés

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

## 8. Feuille des lunettes Engo (BLE)

| Aspect | Comportement |
|---|---|
| Ouverture | demande les permissions (`bluetooth`, `bluetoothConnect`, `bluetoothScan`, `location`), puis démarre le scan |
| Liste | **uniquement les appareils Engo/ActiveLook** (`isEngoDevice`), avec nom et RSSI ; déduplication par identifiant |
| État de connexion | phase détaillée avec couleur + icône (idle / connecting / connected / initializing / ready / disconnecting / disconnected / failed) |
| Action connexion | connexion au device choisi |
| Session | boutons « Démarrer la session » / « Arrêter la session » |
| Déconnexion | bouton de déconnexion |
| Fermeture | arrêt du scan |

**Gestion de l'état de connexion** : le statut de phase est **hiérarchique** ; seul le
passage à l'état `ready` compte comme « connecté » pour l'UI (transition détectée pour
déclencher l'abonnement aux métriques côté orchestration).

## 9. Feuille des capteurs

| Aspect | Comportement |
|---|---|
| Type | feuille déplaçable (hauteur ajustable au scroll) |
| Permissions | mêmes permissions que la feuille BLE, puis scan |
| Sections | **Cardio (HRM)** et **Cadence (CSC)** uniquement |
| Appareil non reconnu | masqué de la liste |
| Appareil connecté | bannière avec nom, batterie, état |
| Connexion | une connexion HRM et une cadence **indépendantes** (parallèles) |
| Fermeture | arrêt du scan |

## 10. SideSheet de posture

| Aspect | Comportement |
|---|---|
| Ouverture | sélection d'un participant **distant** dans la galerie |
| Re-sélection du même | bascule (ferme s'il est ouvert, rouvre sinon) |
| Sélection d'un autre | bascule et affiche le nouveau |
| Contenu | titre « Posture » + bouton fermer ; squelette du participant si des données existent, sinon message « Aucune donnée de posture » |
| Taille | 220 px de large, bordure gauche, fond sombre |
| Données affichées | dernière posture reçue du participant sélectionné (sans HUD de données) |

## 11. Visibilité des squelettes

| Aspect | Comportement |
|---|---|
| Ensemble de masquage | par identité de participant distant |
| Bascule | action sur l'entrée du participant |
| Effet | recalcule de la liste (le squelette disparaît/réapparaît) |
| PIP global | une bascule globale contrôle l'affichage des squelettes (PIP + overlays) |

## 12. Notifications et messages

| Type | Usage |
|---|---|
| Dialogue d'erreur | échecs de connexion, erreurs de session, refus de publier |
| Dialogue de déconnexion | confirmation de départ |
| Message éphémère (snackbar) | validation du formulaire de connexion |
| Journal (debug) | erreurs de décodage, erreurs BLE, états de capteurs |

## 13. Gestion des permissions par plateforme

| Permission | Où demandée | Plateforme |
|---|---|---|
| Caméra, micro | écran connexion salle | Android |
| Bluetooth, bluetoothConnect | écran connexion salle | Android |
| Bluetooth, bluetoothConnect, bluetoothScan, location | ouverture feuilles BLE / capteurs | Mobile (hors web) |
| Localisation | au démarrage du suivi GPS (si refusé → abandon silencieux) | Toutes |
| Foreground service | manifeste (caméra, micro, périphériques connectés) | Android |

## 14. Points d'attention pour le portage KMP

| Élément | Recommandation |
|---|---|
| Règles de navigation | Reprendre la cartographie (section 1) comme graphe d'états |
| Insets / géométrie | Valeurs numériques à porter telles quelles (sections 7.1–7.2) |
| États de boutons | Machine à états partagée dans le module commun, rendu natif |
| Feuilles (sheets) | Composants natifs (bottom sheet Compose / SwiftUI sheet) |
| Validation de formulaire | Logique pure (section 2) |
| Permissions | API natives par plateforme |
