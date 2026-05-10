import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Pill-shaped pink-to-violet gradient button used for primary CTAs in the
/// Pulse design (e.g. Subscription, "Try free for 7 days").
///
/// Material's [ElevatedButton] cannot host a gradient background out of the
/// box, so this widget wraps an [InkWell] over a rounded gradient container
/// with the same vertical rhythm as the standard elevated button defined in
/// [buildPulseTheme].
class HeroButton extends StatelessWidget {
  const HeroButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final child = Container(
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: AppColors.pulseHalo,
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    final wrapped = Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            child: child,
          ),
        ),
      ),
    );
    return fullWidth ? SizedBox(width: double.infinity, child: wrapped) : wrapped;
  }
}
