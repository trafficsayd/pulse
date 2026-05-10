import 'package:flutter/material.dart';

/// Design tokens for the Pulse dark aesthetic.
///
/// Pulse renders on a near-black canvas with a violet undertone. Primary
/// accents are violet/pink — the mockup's "neon-on-velvet" feel — with a
/// pink → violet gradient for hero CTAs and bonded modes.
abstract final class AppColors {
  static const Color background = Color(0xFF0A0612);
  static const Color surface = Color(0xFF15101F);
  static const Color surfaceElevated = Color(0xFF1F1830);
  static const Color outline = Color(0xFF2C2440);

  static const Color textPrimary = Color(0xFFEDEEF2);
  static const Color textSecondary = Color(0xFF9A93AA);
  static const Color textMuted = Color(0xFF655B7A);

  /// Primary accent — violet `purple-500`, used for active sessions and
  /// primary affordances.
  static const Color pulse = Color(0xFFA855F7);

  /// Soft outer glow under the violet accent.
  static const Color pulseGlow = Color(0x66A855F7);

  /// Strong outer halo, used on hero CTAs and active partner avatars.
  static const Color pulseHalo = Color(0x33A855F7);

  /// Pink companion to [pulse]. Pairs with [pulse] in gradients (Half-Heart,
  /// Subscription CTA) and in alert pills.
  static const Color pulsePink = Color(0xFFEC4899);

  /// Pink → violet hero gradient. Use for primary CTAs in the redesign.
  static const Gradient heroGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [pulsePink, pulse],
  );

  /// Background "velvet" gradient — applied as an overlay over [background]
  /// to give screens a subtle violet wash.
  static const Gradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0F0820), Color(0xFF0A0612)],
  );

  /// Transport quality indicator colors.
  static const Color transportDirect = Color(0xFF22C55E);
  static const Color transportLocal = Color(0xFF60A5FA);
  static const Color transportRelay = Color(0xFFFBBF24);
  static const Color transportSearching = Color(0xFF7A7290);

  /// Status colors used by `ConnectionStatus` pills and toggle states.
  static const Color statusActive = Color(0xFF22C55E);
  static const Color statusPaused = Color(0xFFFBBF24);
  static const Color statusArchived = Color(0xFF7A7290);
  static const Color danger = Color(0xFFFF6B6B);

  /// Curated palette for connection avatar rings. All pass against the dark
  /// canvas — pinks, violets and blues that match the mockup vocabulary.
  static const List<Color> avatarPalette = [
    Color(0xFFA855F7), // violet
    Color(0xFFEC4899), // pink
    Color(0xFF60A5FA), // sky
    Color(0xFFFBBF24), // gold
    Color(0xFF22C55E), // mint
    Color(0xFFFF7CC8), // rose
    Color(0xFF8A7CFF), // periwinkle
    Color(0xFFE07CFF), // orchid
  ];
}
