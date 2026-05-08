import 'package:flutter/material.dart';

/// Design tokens for the Pulse dark aesthetic.
///
/// Pulse intentionally uses a near-black canvas with a small set of soft accents.
/// All UI surfaces should pull colors from this class instead of hard-coding hex values.
abstract final class AppColors {
  static const Color background = Color(0xFF050608);
  static const Color surface = Color(0xFF0F1115);
  static const Color surfaceElevated = Color(0xFF181B22);
  static const Color outline = Color(0xFF2A2E38);

  static const Color textPrimary = Color(0xFFEDEEF2);
  static const Color textSecondary = Color(0xFF8A8F9A);
  static const Color textMuted = Color(0xFF55585F);

  /// Primary accent — used for active sessions and primary actions.
  static const Color pulse = Color(0xFFFF5C7A);
  static const Color pulseGlow = Color(0x66FF5C7A);

  /// Transport quality indicator colors.
  static const Color transportDirect = Color(0xFF4ADE80);
  static const Color transportLocal = Color(0xFF60A5FA);
  static const Color transportRelay = Color(0xFFFBBF24);
  static const Color transportSearching = Color(0xFF8A8F9A);

  /// Curated palette for connection avatars — all pass on a dark background.
  static const List<Color> avatarPalette = [
    Color(0xFFFF5C7A),
    Color(0xFFFFB05C),
    Color(0xFFFFE16A),
    Color(0xFF7CE0A1),
    Color(0xFF6BD3FF),
    Color(0xFF8A7CFF),
    Color(0xFFE07CFF),
    Color(0xFFFF7CC8),
  ];
}
