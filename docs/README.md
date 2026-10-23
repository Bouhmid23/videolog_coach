# Documentation fonctionnelle — Videolog Coach (livekitapp)

Cette documentation décrit **l'intégralité des fonctionnalités** du projet, de façon
**indépendante du framework Flutter**. Elle sert de référence pour porter l'application
en **Kotlin Multiplatform (KMP)** : chaque document décrit un domaine métier avec ses
données, ses protocoles, ses algorithmes et ses comportements, sans aucune référence aux
widgets ou au code Dart.

## Sommaire

| # | Fichier | Domaine |
|---|---------|---------|
| 00 | [00-overview.md](00-overview.md) | Vue d'ensemble, architecture, flux utilisateur, matrice des fonctionnalités |
| 01 | [01-video-conferencing.md](01-video-conferencing.md) | Visioconférence temps réel (LiveKit) : token, salle, médias, participants |
| 02 | [02-telemetry.md](02-telemetry.md) | Télémétrie temps réel échangée entre participants |
| 03 | [03-gps-map.md](03-gps-map.md) | Suivi GPS, distance parcourue et mini-carte |
| 04 | [04-ble-glasses.md](04-ble-glasses.md) | Lunettes connectées ActiveLook / Engo (protocole BLE propriétaire) |
| 05 | [05-ble-sensors.md](05-ble-sensors.md) | Capteurs sport BLE standard (cardio, cadence) |
| 06 | [06-pose-detection.md](06-pose-detection.md) | Détection de posture, classification et squelette |
| 07 | [07-ui-behavior.md](07-ui-behavior.md) | Comportements des écrans, contrôles et interactions |
| 08 | [08-kmp-porting.md](08-kmp-porting.md) | Guide de portage Kotlin Multiplatform |

## Comment lire cette documentation

- Chaque fichier est **autonome** : il peut être lu indépendamment des autres.
- Les constantes (URLs, UUIDs, seuils, fréquences, formules) sont celles **réellement
  présentes dans le code** au moment de la rédaction.
- Le vocabulaire est **framework-agnostic** : on parle de « service », « flux », « modèle »,
  « écran », « participant », jamais de widget Flutter, Provider ou GoRouter.
- Les schémas JSON et les protocoles binaires sont donnés en tableaux, directement
  implémentables en Kotlin.

## Convention de nommage dans le code source

Pour rapprocher la documentation du code, les équivalences suivantes s'appliquent :

| Concept doc | Classe / fichier source |
|---|---|
| Orchestrateur de session | `RoomViewModel` (`viewmodels/room_viewmodel.dart`) |
| Contrôles média & BLE | `ControlsViewModel` (`viewmodels/controls_viewmodel.dart`) |
| Pipeline de posture | `PoseDetectionViewModel` (`viewmodels/pose_detection_viewmodel.dart`) |
| Service lunettes | `BleTelemetryService` (`core/ble_telemetry_service.dart`) |
| Service capteurs | `BleSensorService` (`core/ble_sensor_service.dart`) |
| Modèle télémétrie distante | `RemoteTelemetry` (`data/remote_telemetry.dart`) |
| Modèle posture distante | `RemotePosture` (`data/remote_posture.dart`) |
