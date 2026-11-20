import 'dart:ui' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/core/posture_detection_service.dart';
import 'package:videolog_coach/data/pose_models.dart';
import 'package:videolog_coach/data/remote_posture.dart';
import 'package:videolog_coach/viewmodels/pose/motion_detector.dart';
import 'package:videolog_coach/viewmodels/pose/posture_classifier.dart';

Pose _buildPose({
  required Map<LandmarkType, ({double x, double y, double z, double v})> points,
  List<WorldLandmark> worldLandmarks = const [],
}) {
  final landmarks = <PoseLandmark>[];
  for (final type in LandmarkType.values) {
    final p = points[type];
    landmarks.add(
      PoseLandmark(
        type: type,
        x: p?.x ?? 0.5,
        y: p?.y ?? 0.5,
        z: p?.z ?? 0.0,
        visibility: p?.v ?? 0.9,
      ),
    );
  }
  return Pose(
    landmarks: landmarks,
    worldLandmarks: worldLandmarks,
    score: 0.9,
  );
}

void main() {
  group('MotionDetector (C1.1)', () {
    test('détecte une posture statique après 15 frames quasi-immobiles et réinitialise sur mouvement', () {
      final detector = MotionDetector();
      final staticPose = _buildPose(points: {
        LandmarkType.nose: (x: 0.5, y: 0.2, z: 0.0, v: 0.95),
      });

      // Première frame : initialise la référence -> non statique
      expect(detector.update(staticPose), isFalse);

      // Frames 1 à 14 immobiles -> toujours en dessous du seuil (15 frames)
      for (int i = 1; i < 15; i++) {
        expect(detector.update(staticPose), isFalse, reason: 'Frame $i');
      }

      // 15ème frame immobile -> bascule en mode statique
      expect(detector.update(staticPose), isTrue);
      expect(detector.update(staticPose), isTrue);

      // Un mouvement significatif (> 0.015) ramène immédiatement à non-statique
      final movedPose = _buildPose(points: {
        LandmarkType.nose: (x: 0.85, y: 0.85, z: 0.0, v: 0.95),
        LandmarkType.leftShoulder: (x: 0.85, y: 0.85, z: 0.0, v: 0.95),
        LandmarkType.rightShoulder: (x: 0.85, y: 0.85, z: 0.0, v: 0.95),
      });
      // Déplacement de tous les points de +0.1
      final allMovedPose = Pose(
        landmarks: staticPose.landmarks
            .map(
              (lm) => PoseLandmark(
                type: lm.type,
                x: lm.x + 0.1,
                y: lm.y + 0.1,
                z: lm.z,
                visibility: lm.visibility,
              ),
            )
            .toList(),
        score: 0.9,
      );
      expect(movedPose.landmarks.isNotEmpty, isTrue);
      expect(detector.update(allMovedPose), isFalse);

      // reset() remet le compteur à zéro
      detector.reset();
      expect(detector.update(staticPose), isFalse);
    });
  });

  group('PostureClassifier & PostureStabilizer (C1.2)', () {
    const classifier = PostureClassifier();
    const frameSize = Size(720, 1280);

    test('classifie correctement les postures debout, assis et allongé', () {
      // 1. Debout : épaules en haut (y=0.25), hanches au milieu (y=0.50), genoux (y=0.72), chevilles (y=0.92)
      final standingPose = _buildPose(points: {
        LandmarkType.leftShoulder: (x: 0.45, y: 0.25, z: 0, v: 0.9),
        LandmarkType.rightShoulder: (x: 0.55, y: 0.25, z: 0, v: 0.9),
        LandmarkType.leftHip: (x: 0.46, y: 0.50, z: 0, v: 0.9),
        LandmarkType.rightHip: (x: 0.54, y: 0.50, z: 0, v: 0.9),
        LandmarkType.leftKnee: (x: 0.46, y: 0.72, z: 0, v: 0.9),
        LandmarkType.rightKnee: (x: 0.54, y: 0.72, z: 0, v: 0.9),
        LandmarkType.leftAnkle: (x: 0.46, y: 0.92, z: 0, v: 0.9),
        LandmarkType.rightAnkle: (x: 0.54, y: 0.92, z: 0, v: 0.9),
      });
      final standing = classifier.classify(standingPose, frameSize: frameSize);
      expect(standing?.label, equals('debout'));
      expect(standing?.confidence, closeTo(0.9, 1e-4));

      // 2. Assis : genoux proches du niveau vertical des hanches (kneeDrop < 0.35) et chevilles repliées (ankleDrop < 0.7)
      final sittingPose = _buildPose(points: {
        LandmarkType.leftShoulder: (x: 0.45, y: 0.25, z: 0, v: 0.9),
        LandmarkType.rightShoulder: (x: 0.55, y: 0.25, z: 0, v: 0.9),
        LandmarkType.leftHip: (x: 0.46, y: 0.55, z: 0, v: 0.9),
        LandmarkType.rightHip: (x: 0.54, y: 0.55, z: 0, v: 0.9),
        LandmarkType.leftKnee: (x: 0.46, y: 0.60, z: 0, v: 0.9),
        LandmarkType.rightKnee: (x: 0.54, y: 0.60, z: 0, v: 0.9),
        LandmarkType.leftAnkle: (x: 0.46, y: 0.70, z: 0, v: 0.9),
        LandmarkType.rightAnkle: (x: 0.54, y: 0.70, z: 0, v: 0.9),
      });
      final sitting = classifier.classify(sittingPose, frameSize: frameSize);
      expect(sitting?.label, equals('assis'));

      // 3. Allongé : axe épaules-hanches horizontal (torsoAngleDeg > 48°)
      final lyingPose = _buildPose(points: {
        LandmarkType.leftShoulder: (x: 0.20, y: 0.50, z: 0, v: 0.9),
        LandmarkType.rightShoulder: (x: 0.20, y: 0.54, z: 0, v: 0.9),
        LandmarkType.leftHip: (x: 0.75, y: 0.52, z: 0, v: 0.9),
        LandmarkType.rightHip: (x: 0.75, y: 0.56, z: 0, v: 0.9),
      });
      final lying = classifier.classify(lyingPose, frameSize: frameSize);
      expect(lying?.label, equals('allongé'));
    });

    test('retourne null si les repères du tronc ont une visibilité < 0.5', () {
      final lowVisPose = _buildPose(points: {
        LandmarkType.leftShoulder: (x: 0.45, y: 0.25, z: 0, v: 0.2),
        LandmarkType.rightShoulder: (x: 0.55, y: 0.25, z: 0, v: 0.9),
        LandmarkType.leftHip: (x: 0.46, y: 0.50, z: 0, v: 0.9),
        LandmarkType.rightHip: (x: 0.54, y: 0.50, z: 0, v: 0.9),
      });
      expect(classifier.classify(lowVisPose, frameSize: frameSize), isNull);
    });

    test('PostureStabilizer applique une hystérésis de 3 frames avant de changer de label', () {
      final stabilizer = PostureStabilizer();
      RemotePosture raw(String label) => RemotePosture(
            label: label,
            confidence: 0.9,
            receivedAt: DateTime.now(),
          );

      // 1er label adopté immédiatement
      expect(stabilizer.stabilize(raw('debout'))?.label, equals('debout'));

      // 1 ou 2 frames 'assis' ne suffisent pas à basculer
      expect(stabilizer.stabilize(raw('assis'))?.label, equals('debout'));
      expect(stabilizer.stabilize(raw('assis'))?.label, equals('debout'));

      // 3ème frame consécutive 'assis' -> bascule effective
      expect(stabilizer.stabilize(raw('assis'))?.label, equals('assis'));

      // reset() réinitialise l'état stable
      stabilizer.reset();
      expect(stabilizer.stabilize(raw('allongé'))?.label, equals('allongé'));
    });
  });

  group('PostureSmoothing (C1.3)', () {
    test('lisse les coordonnées image et world avec EMA alpha=0.5 et se réinitialise sur reset()', () {
      final smoother = PostureSmoothing(alpha: 0.5);

      final pose1 = _buildPose(
        points: {
          LandmarkType.nose: (x: 0.2, y: 0.4, z: 0.0, v: 0.9),
        },
        worldLandmarks: const [
          WorldLandmark(typeIndex: 0, x: 1.0, y: 2.0, z: 3.0, visibility: 0.9),
        ],
      );
      final pose2 = _buildPose(
        points: {
          LandmarkType.nose: (x: 0.6, y: 0.8, z: 0.4, v: 0.9),
        },
        worldLandmarks: const [
          WorldLandmark(typeIndex: 0, x: 3.0, y: 4.0, z: 5.0, visibility: 0.9),
        ],
      );

      // 1ère frame : valeur exacte
      final s1 = smoother.smooth(pose1);
      expect(s1.getLandmark(LandmarkType.nose).x, closeTo(0.2, 1e-6));
      expect(s1.worldLandmarks.first.x, closeTo(1.0, 1e-6));

      // 2ème frame avec alpha=0.5 : moyenne (0.2 + 0.5*(0.6-0.2) = 0.4)
      final s2 = smoother.smooth(pose2);
      expect(s2.getLandmark(LandmarkType.nose).x, closeTo(0.4, 1e-6));
      expect(s2.getLandmark(LandmarkType.nose).y, closeTo(0.6, 1e-6));
      expect(s2.getLandmark(LandmarkType.nose).z, closeTo(0.2, 1e-6));
      expect(s2.worldLandmarks.first.x, closeTo(2.0, 1e-6));
      expect(s2.worldLandmarks.first.y, closeTo(3.0, 1e-6));
      expect(s2.worldLandmarks.first.z, closeTo(4.0, 1e-6));

      // reset() efface la mémoire EMA -> la frame suivante repart de la valeur brute
      smoother.reset();
      final s3 = smoother.smooth(pose2);
      expect(s3.getLandmark(LandmarkType.nose).x, closeTo(0.6, 1e-6));
    });
  });
}
