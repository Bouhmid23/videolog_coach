import 'package:flutter/material.dart';

class GlassesIcon extends StatelessWidget {
  const GlassesIcon({
    required this.size,
    required this.color,
    super.key,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'images/glasses-svgrepo.png',
      width: size,
      height: size,
      color: color,
      colorBlendMode: BlendMode.srcIn,
    );
  }
}
