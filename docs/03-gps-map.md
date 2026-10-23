# 03 — GPS, distance parcourue et mini-carte

Ce document décrit le suivi de position, le calcul de distance cumulée et la mini-carte
des participants.

## 1. Suivi GPS

### 1.1 Configuration du flux de position

| Paramètre | Valeur |
|---|---|
| Précision | Haute (`high`) |
| Filtre de distance | **5 mètres** (nouvelle position seulement si déplacement ≥ 5 m) |
| Source | Fournisseur de position natif (GPS) |

### 1.2 Démarrage (avec garde-fous)

```
1. Vérifier que les services de localisation sont activés
      → si non : abandon, message de journal
2. Vérifier la permission
      → denied        → demander ; si encore denied : abandon
      → deniedForever → abandon
3. S'abonner au flux de positions
      → sur chaque position :
            si une position précédente existe :
                 delta = haversine(pos_précédente, pos_nouvelle)
                 distanceTotale += delta
            dernièrePosition = pos_nouvelle
```

> La première position n'ajoute **aucune** distance (initialisation seulement).

### 1.3 Calcul de distance (Haversine)

Formule appliquée à chaque nouveau point :

```
rayon = 3958.8 miles                    // rayon moyen terrestre
dLat  = radians(lat2 - lat1)
dLon  = radians(lon2 - lon1)
a     = sin²(dLat/2) + cos(radians(lat1)) × cos(radians(lat2)) × sin²(dLon/2)
d     = rayon × 2 × atan2(√a, √(1-a))   // en miles
distanceTotale += d
```

- L'unité interne de distance cumulée est le **mile**.
- Conversion affichée (lunettes) : `km = miles × 1.60934`.

### 1.4 Vitesse affichée

La vitesse utilisée provient directement du fournisseur de position (m/s) et est
convertie : `km/h = m/s × 3.6` (1 décimale).

## 2. Mini-carte des participants

### 2.1 Modèle d'entrée

| Champ | Type | Description |
|---|---|---|
| `identity` | string | Identité du participant |
| `label` | string? | Nom affiché (« Moi (nom) » pour le local) |
| `lat` | double? | Latitude |
| `lng` | double? | Longitude |
| `isLocal` | bool | `true` pour le participant local |
| `hasPosition` | bool (calculé) | `lat != null && lng != null` |

**Construction des entrées :**

| Type | Identité | Label | Position |
|---|---|---|---|
| Local | identité locale | `Moi (<name ou identity>)` | télémétrie locale |
| Distant | identité du pair | nom du pair ou identité | dernière télémétrie reçue |

> Les participants **sans position** sont conservés dans la liste mais ignorés au rendu.

### 2.2 Dimensionnement et cadrage

| Paramètre | Valeur |
|---|---|
| Taille de la carte | 140 × 140 px |
| Zoom par défaut | 15 |
| Facteur de remplissage | 85 % de la zone (fit) |
| Fourchette de zoom | 18 → 3 (décroissant) |
| Padding autour des points | 20 % de l'étendue (lat/lng) |

**Algorithme de cadrage :**

1. Filtrer les entrées avec position.
2. Cibler en priorité les participants **distants** ; s'il n'y en a pas, inclure tout le monde.
3. Calculer min/max lat et lng, puis ajouter 20 % de padding de part et d'autre.
4. **Zoom d'ajustement** : pour `z` de 18 descendent à 3, retourner le premier `z` pour
   lequel l'étendue projetée tient dans `size × 0.85` (largeur **et** hauteur) ;
   sinon `z = 3`.
5. Centrer sur le milieu du bounding box, convertir en coordonnées monde, puis décaler
   de `-size/2` pour obtenir le coin supérieur gauche de la vue.
6. Calculer la plage de tuiles `txMin..txMax`, `tyMin..tyMax` correspondante.

### 2.3 Projections Web Mercator

```
worldX(lng, z) = (lng + 180) / 360 × (256 × 2^z)

worldY(lat, z) :
    rad  = radians(lat)
    merc = ln(tan(rad) + 1/cos(rad))
    y    = (1 - merc/π) / 2 × (256 × 2^z)
```

Le rendu d'un point écran :
```
px = worldX(lng, zoom) - left
py = worldY(lat, zoom) - top
```

### 2.4 Sources de tuiles

| Source | Template d'URL | Marqueurs |
|---|---|---|
| OpenStreetMap (par défaut) | `https://tile.openstreetmap.org/{z}/{x}/{y}.png` | bordure/fond sombre `#2F3542` |
| Google Satellite | `https://www.google.cn/maps/vt?lyrs=s@189&gl=cn&x={x}&y={y}&z={z}` | bordure ambre `#F5A623`, texte blanc |

- La bascule est **circulaire** (deux états qui s'enchaînent).
- Chaque requête de tuile inclut un en-tête `User-Agent: livekitapp-hud/1.0`.
- Seules les réponses HTTP 200 sont décodées.

### 2.5 Cache de tuiles

| Aspect | Comportement |
|---|---|
| Clé de cache | `urlTemplate|z/x/y` |
| Signature de vue | `urlTemplate|zoom|txMin:txMax|tyMin:tyMax` |
| Invalidation | si la signature ne change pas → simple rafraîchissement, **aucun téléchargement** |
| Réutilisation | les tuiles déjà en mémoire sont conservées |
| Libération | les tuiles hors de la nouvelle vue sont libérées |
| Échec de téléchargement | ignoré ; la tuile de secours reste visible |

### 2.6 Rendu

1. **Fond de secours** : quadrillage de « routes » procédurales (graines aléatoires fixes)
   — visible pendant le chargement ou si le réseau échoue.
2. **Tuiles** téléchargées par-dessus.
3. **Boussole** : triangle + lettre « N » en haut au centre.
4. **Marqueurs** :
   - halo (rayon 10, alpha 0.25),
   - disque plein (rayon 5),
   - anneau (rayon 5, épaisseur 1.4),
   - point blanc central pour le participant local,
   - couleurs : local = bleu ; distant = selon la source de tuiles.
5. **Étiquette** : nom tronqué à 8 caractères + « … », fond noir arrondi sous le
   marqueur, centrée, contrainte dans la carte.

### 2.7 États vides

- Aucun participant avec position → texte « Aucune position GPS » centré.
- Carte affichée même sans position (fond de secours), avec ce texte.

## 3. Intégration dans la session

| Aspect | Comportement |
|---|---|
| Démarrage | En même temps que la session (init) |
| Arrêt | À la déconnexion de la session et à la libération |
| Source de la position locale | Dernière position reçue (stockée par l'orchestrateur) |
| Source des positions distantes | Dernière télémétrie reçue de chaque pair |
| Toggle d'affichage | Bouton de bascule de la carte dans la barre de contrôles |
| Position relative | En haut à droite de la zone vidéo, au-dessus de la galerie ; laisse la place au panneau latéral et au PIP de posture |

## 4. Points d'attention pour le portage KMP

| Élément | Nature | Recommandation |
|---|---|---|
| Haversine | Pur | Fonction pure + tests unitaires (valeurs de référence) |
| Fit-zoom / projections Mercator | Pur | Fonction pure ; attention aux degrés/radians |
| Cache de tuiles | Logique + I/O | Module commun (gestion du cache) ; téléchargement via client HTTP natif |
| Modèle d'entrée carte | Pur | Data class |
| Flux de positions | Plateforme | Interface `LocationSource` (Android : FusedLocation, iOS : CLLocation) |
| Rendu | Natif | Canvas Compose / SwiftUI — seules les coordonnées calculées viennent du commun |
