import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sensors_plus/sensors_plus.dart';

/// Direction « vers le haut » (opposée à la gravité), exprimée dans les axes
/// des worldLandmarks MediaPipe, pour que le viewer redresse l'avatar quand la
/// caméra est penchée (plongée, téléphone incliné, tenu à la main).
///
/// Axes des worldLandmarks (image non retournée, téléphone en portrait) :
///   x vers la droite de l'image, y vers le bas, z en s'éloignant de la caméra.
///
/// L'accéléromètre Android lit +9,8 m/s² vers le HAUT à l'arrêt (téléphone
/// droit : y = +9,8). Axes du téléphone : x à droite, y en haut, z hors de
/// l'écran (vers l'utilisateur).
///   Caméra avant  : image x = −x téléphone, image y(bas) = −y, profondeur = +z
///   Caméra arrière: image x = +x téléphone, image y(bas) = −y, profondeur = −z
/// Contrôle : téléphone droit (portrait), le vecteur renvoyé vaut ≈ (0, −1, 0).
class GravityService {
  GravityService._();
  static final GravityService instance = GravityService._();

  /// À tenir à jour lors du changement de caméra (ControlsViewModel.switchCamera).
  bool frontCamera = true;

  StreamSubscription<AccelerometerEvent>? _sub;
  bool _hasValue = false;
  double _x = 0, _y = 0, _z = 0;

  /// Lissage exponentiel du vecteur unitaire : ~0,1 s de constante de temps à
  /// 50 Hz. Retire les secousses sans retarder visiblement un changement
  /// d'inclinaison.
  static const double _alpha = 0.1;

  void start() {
    if (_sub != null) return;
    try {
      _sub = accelerometerEventStream(
        samplingPeriod: SensorInterval.normalInterval,
      ).listen(
        _onEvent,
        onError: (Object error) {
          _hasValue = false;
          debugPrint('⚠️ Accéléromètre indisponible : $error');
        },
      );
    } catch (error) {
      debugPrint('⚠️ Accéléromètre indisponible : $error');
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _hasValue = false;
  }

  DateTime _lastLog = DateTime.fromMillisecondsSinceEpoch(0);

  void _onEvent(AccelerometerEvent e) {
    final n = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    // Chute libre ou capteur muet : pas de direction exploitable.
    if (!n.isFinite || n < 1.0) return;
    final ux = e.x / n, uy = e.y / n, uz = e.z / n;
    if (!_hasValue) {
      _x = ux;
      _y = uy;
      _z = uz;
      _hasValue = true;
    } else {
      _x += (ux - _x) * _alpha;
      _y += (uy - _y) * _alpha;
      _z += (uz - _z) * _alpha;
    }
    // Contrôle sur le terrain (logcat) : téléphone droit en portrait → up ≈ (0.00, -1.00, 0.00).
    final now = DateTime.now();
    if (now.difference(_lastLog) >= const Duration(seconds: 2)) {
      _lastLog = now;
      final up = upInCameraAxes;
      if (up != null) {
        debugPrint(
          '🧭 gravity up=(${up[0].toStringAsFixed(2)}, ${up[1].toStringAsFixed(2)}, ${up[2].toStringAsFixed(2)}) '
          'camera=${frontCamera ? 'avant' : 'arrière'}',
        );
      }
    }
  }

  /// Vecteur unitaire « haut » dans les axes de l'image (x droite, y bas,
  /// z s'éloignant de la caméra), ou null si le capteur n'a rien donné.
  List<double>? get upInCameraAxes {
    if (!_hasValue) return null;
    final n = math.sqrt(_x * _x + _y * _y + _z * _z);
    if (n < 0.5) return null;
    final ux = _x / n, uy = _y / n, uz = _z / n;
    return frontCamera ? [-ux, -uy, uz] : [ux, -uy, -uz];
  }
}
