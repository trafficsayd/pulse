import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Four-bar signal-strength indicator, used on the connection status screen.
///
/// [activeBars] should be in `0..4`. Inactive bars are drawn at a low
/// opacity in the same hue so the rhythm of the indicator stays readable
/// on the dark canvas.
class ChannelBars extends StatelessWidget {
  const ChannelBars({
    super.key,
    required this.activeBars,
    required this.color,
    this.barWidth = 4,
    this.height = 20,
    this.spacing = 3,
  });

  final int activeBars;
  final Color color;
  final double barWidth;
  final double height;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: barWidth * 4 + spacing * 3,
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) SizedBox(width: spacing),
            Expanded(
              child: Container(
                height: height * (0.4 + 0.2 * i),
                decoration: BoxDecoration(
                  color: i < activeBars ? color : color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(barWidth / 2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Semi-transparent panel surface used for the status banner on the
/// connection-status screen ("Приложение работает без интернета..."). Kept
/// here so it can be reused on the Settings/Subscription screens too.
class GhostBanner extends StatelessWidget {
  const GhostBanner({
    super.key,
    required this.icon,
    required this.text,
    this.iconColor = AppColors.transportDirect,
  });

  final IconData icon;
  final String text;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
