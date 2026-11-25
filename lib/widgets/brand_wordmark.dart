import 'package:flutter/material.dart';

/// Green gradient wordmark for Luak Explorer brand placements.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({
    required this.text,
    required this.fontSize,
    this.letterSpacing = 0,
    this.onDarkSurface = false,
    super.key,
  });

  final String text;
  final double fontSize;
  final double letterSpacing;
  final bool onDarkSurface;

  @override
  Widget build(BuildContext context) {
    final darkSurface =
        onDarkSurface || Theme.of(context).brightness == Brightness.dark;
    final gradient = darkSurface
        ? const LinearGradient(
            colors: [Color(0xFFE1F5D9), Color(0xFF9DDB91), Color(0xFF65B96C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [Color(0xFF4B9D48), Color(0xFF1B5E20), Color(0xFF103D25)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(bounds),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontFamily: 'serif',
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          fontStyle: FontStyle.italic,
          letterSpacing: letterSpacing,
          height: 1.1,
        ),
      ),
    );
  }
}
