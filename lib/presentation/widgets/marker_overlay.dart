import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/ball_marker.dart';

/// Taille candidate de l'image caméra, utilisée par le diagnostic
/// d'alignement des ballons (debug uniquement).
///
/// Les trois sources possibles — dimensions de publication LiveKit,
/// résolution demandée à la capture et taille des images de pose — doivent
/// avoir le même ratio que l'image affichée, sinon la projection est fausse.
class FrameCandidate {
  final String label;
  final Size? size;

  const FrameCandidate(this.label, this.size);
}

/// Projette une position normalisée (fractions de l'image caméra) vers
/// l'écran, avec exactement la même transformation que `PoseOverlay` :
/// `BoxFit.cover` + recadrage centré + miroir optionnel.
///
/// Le rendu vidéo utilisé par l'app est `VideoViewFit.cover`, donc le
/// squelette et les ballons doivent passer par cette fonction pour rester
/// alignés sur l'image affichée.
Offset projectMarker(
  Offset normalized,
  Size frameSize,
  Size canvasSize, {
  BoxFit fit = BoxFit.cover,
  bool mirrorX = false,
}) {
  if (frameSize.isEmpty || canvasSize.isEmpty) return Offset.zero;

  final fitted = applyBoxFit(fit, frameSize, canvasSize);
  final source = Alignment.center.inscribe(
    fitted.source,
    Offset.zero & frameSize,
  );
  final destination = Alignment.center.inscribe(
    fitted.destination,
    Offset.zero & canvasSize,
  );
  if (source.isEmpty) return Offset.zero;

  var px = normalized.dx * frameSize.width;
  final py = normalized.dy * frameSize.height;
  // L'aperçu local est en miroir : le message du coach est toujours envoyé
  // dans le repère "sans miroir" de la caméra du sportif.
  if (mirrorX) px = frameSize.width - px;

  return Offset(
    destination.left + (px - source.left) / source.width * destination.width,
    destination.top + (py - source.top) / source.height * destination.height,
  );
}

/// Affiche les ballons envoyés par le coach sur la vidéo locale du sportif.
///
/// À placer en `Positioned.fill` au-dessus du `PoseOverlay`. Le widget ne
/// capte aucun geste et ne touche ni au flux `posture` ni à la détection.
class MarkerOverlay extends StatefulWidget {
  static const String assetPath = 'docs/ballon.svg';

  /// Taille minimale d'un ballon en pixels logiques.
  static const double minDiameter = 28;

  /// Diamètre = ce ratio du plus petit côté de la vidéo affichée.
  static const double diameterRatio = 0.10;

  final ValueListenable<List<BallMarker>> markers;
  final Size? frameSize;
  final BoxFit fit;
  final bool mirrorX;

  /// Tailles d'image candidates, journalisées en debug pour diagnostiquer
  /// un désalignement (ratio, fit, miroir, marges).
  final List<FrameCandidate> debugFrameCandidates;

  const MarkerOverlay({
    required this.markers,
    required this.frameSize,
    this.fit = BoxFit.cover,
    this.mirrorX = false,
    this.debugFrameCandidates = const [],
    super.key,
  });

  @override
  State<MarkerOverlay> createState() => _MarkerOverlayState();
}

class _MarkerOverlayState extends State<MarkerOverlay> {
  /// Dernière signature journalisée par ballon : évite un log à chaque
  /// rebuild tant que la géométrie et la position ne changent pas.
  final Map<String, String> _logged = {};

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<List<BallMarker>>(
        valueListenable: widget.markers,
        builder: (context, markers, _) {
          final frame = widget.frameSize;
          if (markers.isEmpty || frame == null || frame.isEmpty) {
            _logged.clear();
            return const SizedBox.shrink();
          }

          if (kDebugMode) {
            final alive = <String>{
              for (final marker in markers)
                if (!marker.isExpired) _markerKey(marker),
            };
            _logged.removeWhere((key, _) => !alive.contains(key));
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              if (size.isEmpty) return const SizedBox.shrink();

              final diameter = math.max(
                MarkerOverlay.minDiameter,
                size.shortestSide * MarkerOverlay.diameterRatio,
              );

              return Stack(
                children: [
                  for (final marker in markers)
                    if (!marker.isExpired)
                      _buildMarker(marker, frame, size, diameter),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMarker(
    BallMarker marker,
    Size frame,
    Size size,
    double diameter,
  ) {
    final center = projectMarker(
      Offset(marker.x, marker.y),
      frame,
      size,
      fit: widget.fit,
      mirrorX: widget.mirrorX,
    );

    if (kDebugMode) _debugLog(marker, frame, size, center);

    return Positioned(
      left: center.dx - diameter / 2,
      top: center.dy - diameter / 2,
      width: diameter,
      height: diameter,
      child: _BallSprite(
        key: ValueKey(marker.id),
        marker: marker,
        diameter: diameter,
      ),
    );
  }

  String _markerKey(BallMarker marker) =>
      '${marker.id}@${marker.receivedAt.microsecondsSinceEpoch}';

  /// Journalise, pour chaque ballon, tout ce qui peut expliquer un
  /// désalignement :
  /// - `fit` et `mirrorX` ;
  /// - la taille de l'écran (canevas de l'overlay) et son ratio ;
  /// - l'image retenue pour la projection et son ratio ;
  /// - les trois tailles candidates (publication, capture, pose) ;
  /// - la zone réellement affichée et les marges de l'overlay ;
  /// - le point projeté.
  ///
  /// Lecture du diagnostic :
  /// - centre juste mais bords de plus en plus faux → ratio/fit ;
  /// - gauche et droite échangées → miroir ;
  /// - décalage constant en hauteur → l'overlay ne couvre pas la vidéo.
  void _debugLog(
    BallMarker marker,
    Size frame,
    Size canvas,
    Offset point,
  ) {
    final signature = [
      widget.fit.name,
      '${widget.mirrorX}',
      _fmtPx(canvas),
      _fmtPx(frame),
      for (final candidate in widget.debugFrameCandidates)
        '${candidate.label}:${_fmtFrame(candidate.size)}',
      point.dx.toStringAsFixed(1),
      point.dy.toStringAsFixed(1),
    ].join('|');

    final key = _markerKey(marker);
    if (_logged[key] == signature) return;
    _logged[key] = signature;

    final fitted = applyBoxFit(widget.fit, frame, canvas);
    final source = Alignment.center.inscribe(
      fitted.source,
      Offset.zero & frame,
    );
    final destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & canvas,
    );

    final canvasRatio = canvas.width / canvas.height;
    final frameRatio = frame.width / frame.height;
    final zoom = source.isEmpty ? 0.0 : destination.width / source.width;

    final lines = <String>[
      '🎯 [BALLON] ${marker.id} @ '
          '(${marker.x.toStringAsFixed(3)}, ${marker.y.toStringAsFixed(3)})',
      '   fit=${widget.fit.name}  mirrorX=${widget.mirrorX}',
      '   écran=${_fmtPx(canvas)}  ratio=${canvasRatio.toStringAsFixed(4)}',
      '   image retenue=${_fmtPx(frame)}  '
          'ratio=${frameRatio.toStringAsFixed(4)}',
      '   zone source=${_fmtPx(source.size)} @'
          '(${source.left.toStringAsFixed(1)}, ${source.top.toStringAsFixed(1)})'
          '  → affichée=${_fmtPx(destination.size)} @'
          '(${destination.left.toStringAsFixed(1)}, '
          '${destination.top.toStringAsFixed(1)})  zoom=×'
          '${zoom.toStringAsFixed(3)}',
      '   marges overlay : haut=${destination.top.toStringAsFixed(1)} '
          'bas=${(canvas.height - destination.bottom).toStringAsFixed(1)} '
          'gauche=${destination.left.toStringAsFixed(1)} '
          'droite=${(canvas.width - destination.right).toStringAsFixed(1)}',
      '   → point écran (${point.dx.toStringAsFixed(1)}, '
          '${point.dy.toStringAsFixed(1)})',
    ];

    if (widget.debugFrameCandidates.isNotEmpty) {
      final ratios = <double>[];
      lines.add('   tailles candidates :');
      for (final candidate in widget.debugFrameCandidates) {
        final size = candidate.size;
        final ratio = size == null || size.isEmpty
            ? null
            : size.width / size.height;
        final delta = ratio == null
            ? null
            : (ratio - frameRatio).abs() / frameRatio * 100;
        if (ratio != null && !_sameRatio(ratios, ratio)) ratios.add(ratio);
        lines.add(
          '     • ${candidate.label.padRight(11)} ${_fmtFrame(size)}'
          '${ratio == null ? '' : '  ratio=${ratio.toStringAsFixed(4)}'}'
          '${delta == null ? '' : '  écart=${delta.toStringAsFixed(1)} %'}',
        );
      }

      if (ratios.length <= 1) {
        lines.add('   ✅ ratios cohérents entre candidats');
      } else {
        lines.add(
          '   ⚠️ RATIOS DIFFÉRENTS entre candidats '
          '(${ratios.length} valeurs) → cause 2 (ratio/fit)',
        );
      }

      if (!_sameRatio([frameRatio], canvasRatio)) {
        lines.add(
          '   ℹ️ ratio écran ≠ ratio image : marges en contain, '
          'recadrage latéral en cover',
        );
      }
    }

    debugPrint(lines.join('\n'));
  }

  static bool _sameRatio(List<double> ratios, double ratio) =>
      ratios.any((r) => (r - ratio).abs() / ratio <= 0.002);

  static String _fmtPx(Size size) =>
      '${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}';

  static String _fmtFrame(Size? size) => size == null || size.isEmpty
      ? 'inconnue'
      : '${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)}';
}

/// Ballon individuel : apparition (40 % → 100 %) puis fondu sur la dernière
/// seconde, avec le retrait définitif à `ttl`.
class _BallSprite extends StatefulWidget {
  static const Duration appearDuration = Duration(milliseconds: 180);
  static const Duration fadeDuration = Duration(milliseconds: 1000);

  final BallMarker marker;
  final double diameter;

  const _BallSprite({
    required this.marker,
    required this.diameter,
    super.key,
  });

  @override
  State<_BallSprite> createState() => _BallSpriteState();
}

class _BallSpriteState extends State<_BallSprite>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.marker.ttl,
    )..forward();
  }

  @override
  void didUpdateWidget(covariant _BallSprite oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.marker.receivedAt != widget.marker.receivedAt ||
        oldWidget.marker.ttl != widget.marker.ttl) {
      _controller
        ..stop()
        ..duration = widget.marker.ttl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Duration get _elapsed {
    final elapsed = DateTime.now().difference(widget.marker.receivedAt);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  double get _scale {
    final appearMs = _BallSprite.appearDuration.inMilliseconds;
    final elapsedMs = _elapsed.inMilliseconds;
    if (elapsedMs >= appearMs) return 1;
    return 0.4 + 0.6 * Curves.easeOutCubic.transform(elapsedMs / appearMs);
  }

  double get _opacity {
    final totalMs = widget.marker.ttl.inMilliseconds;
    if (totalMs <= 0) return 0;
    final fadeMs = math.min(
      _BallSprite.fadeDuration.inMilliseconds.toDouble(),
      totalMs.toDouble(),
    );
    if (fadeMs <= 0) return 1;
    final remainingMs = totalMs - _elapsed.inMilliseconds;
    if (remainingMs >= fadeMs) return 1;
    if (remainingMs <= 0) return 0;
    return (remainingMs / fadeMs).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: SvgPicture.asset(
        MarkerOverlay.assetPath,
        width: widget.diameter,
        height: widget.diameter,
        fit: BoxFit.contain,
      ),
      builder: (context, child) {
        return Opacity(
          opacity: _opacity,
          child: Transform.scale(scale: _scale, child: child),
        );
      },
    );
  }
}
