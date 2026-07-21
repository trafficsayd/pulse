import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A soft circular halo used as the background ornament around hero
/// elements (the QR on pairing, the avatar on the Sneak-In overlay).
///
/// Stacks two layers: an inner stroke and an outer drop-shadow blur, so it
/// reads correctly on the near-black hub background without falling back
/// to opaque fills.
class GlowRing extends StatelessWidget {
  const GlowRing({
    super.key,
    required this.size,
    this.color = AppColors.pulse,
    this.glow,
    this.strokeWidth = 2,
    this.blurRadius = 32,
    this.spreadRadius = 0,
    this.child,
    this.fill,
  });

  final double size;
  final Color color;
  final Color? glow;
  final double strokeWidth;
  final double blurRadius;
  final double spreadRadius;

  /// Optional background fill *inside* the ring. Use a translucent value
  /// (e.g. `AppColors.pulse.withValues(alpha: .08)`) so the halo stays the
  /// dominant element.
  final Color? fill;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final glowColor = glow ?? color.withValues(alpha: 0.45);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: color, width: strokeWidth),
        boxShadow: [
          BoxShadow(
            color: glowColor,
            blurRadius: blurRadius,
            spreadRadius: spreadRadius,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}
