import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Circular emoji avatar for a saved connection.
///
/// Pulse never transmits the user's display name or photo — every person is
/// represented by a curated emoji ([connection.emoji]) inside a tinted ring
/// pulled from [AppColors.avatarPalette]. This widget is the canonical way
/// to render that pair so every screen stays visually consistent.
class ConnectionAvatar extends StatelessWidget {
  const ConnectionAvatar({
    super.key,
    required this.emoji,
    required this.colorIndex,
    this.size = 48,
    this.showRing = true,
    this.glow = false,
    this.fontSize,
  });

  final String emoji;
  final int colorIndex;
  final double size;

  /// Whether to draw the colored ring border. Disable for very large
  /// "hero" presentations where the emoji speaks for itself.
  final bool showRing;

  /// Drop a soft halo behind the avatar — used in the Sneak In incoming
  /// overlay where the avatar is the focal point.
  final bool glow;

  /// Override the inner emoji size. Defaults to ~`size * 0.6`.
  final double? fontSize;

  Color get _color =>
      AppColors.avatarPalette[colorIndex % AppColors.avatarPalette.length];

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.16),
        border: showRing ? Border.all(color: color, width: 1.6) : null,
        boxShadow: glow
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 32,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        emoji,
        style: TextStyle(fontSize: fontSize ?? size * 0.55),
      ),
    );
  }
}
