import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/ball_marker.dart';

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
class MarkerOverlay extends StatelessWidget {
  static const String assetPath = 'docs/ballon.svg';

  /// Taille minimale d'un ballon en pixels logiques.
  static const double minDiameter = 28;

  /// Diamètre = ce ratio du plus petit côté de la vidéo affichée.
  static const double diameterRatio = 0.10;

  final ValueListenable<List<BallMarker>> markers;
  final Size? frameSize;
  final BoxFit fit;
  final bool mirrorX;

  const MarkerOverlay({
    required this.markers,
    required this.frameSize,
    this.fit = BoxFit.cover,
    this.mirrorX = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<List<BallMarker>>(
        valueListenable: markers,
        builder: (context, markers, _) {
          final frame = frameSize;
          if (markers.isEmpty || frame == null || frame.isEmpty) {
            return const SizedBox.shrink();
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              if (size.isEmpty) return const SizedBox.shrink();

              final diameter = math.max(
                minDiameter,
                size.shortestSide * diameterRatio,
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
      fit: fit,
      mirrorX: mirrorX,
    );

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
