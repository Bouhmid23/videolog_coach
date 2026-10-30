import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Compteur sportif télémétrique haute performance à 120 Hz.
///
/// Garantit :
/// 1. Des chiffres à chasse fixe ([ui.FontFeature.tabularFigures]) pour éliminer tout saut de largeur (jitter).
/// 2. Une interpolation fluide du défilement numérique via [TweenAnimationBuilder].
/// 3. Une prise en charge du mode plein soleil (Outdoor Sun Mode) avec typographie blanc pur (#FFFFFF) et contraste maximal.
class AnimatedSportsCount extends StatelessWidget {
  final double value;
  final int fractionDigits;
  final String prefix;
  final String suffix;
  final TextStyle? style;
  final bool outdoorSunMode;
  final Duration duration;
  final Curve curve;

  const AnimatedSportsCount({
    required this.value,
    this.fractionDigits = 0,
    this.prefix = '',
    this.suffix = '',
    this.style,
    this.outdoorSunMode = false,
    this.duration = const Duration(milliseconds: 250),
    this.curve = Curves.easeOutCubic,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = (style ?? Theme.of(context).textTheme.labelSmall ?? const TextStyle()).copyWith(
      fontFeatures: const [ui.FontFeature.tabularFigures()],
      color: outdoorSunMode ? Colors.white : (style?.color ?? Colors.white),
      fontWeight: outdoorSunMode ? FontWeight.w900 : (style?.fontWeight ?? FontWeight.w700),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: value, end: value),
      duration: duration,
      curve: curve,
      builder: (context, animatedValue, _) {
        final formatted = fractionDigits > 0
            ? animatedValue.toStringAsFixed(fractionDigits)
            : animatedValue.round().toString();
        return Text(
          '$prefix$formatted$suffix',
          style: effectiveStyle,
          maxLines: 1,
          softWrap: false,
        );
      },
    );
  }
}
