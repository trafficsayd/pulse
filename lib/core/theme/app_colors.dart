import 'package:flutter/material.dart';

/// Design tokens for the Pulse dark aesthetic.
///
/// Pulse uses a near-black canvas tinted with deep violet, paired with a
/// vivid purple primary, a magenta heart accent, and soft per-channel
/// status colours. All UI surfaces should pull colors from this class
/// instead of hard-coding hex values.
abstract final class AppColors {
  static const Color background = Color(0xFF06070C);
  static const Color surface = Color(0xFF101218);
  static const Color surfaceElevated = Color(0xFF181B22);
  static const Color outline = Color(0xFF2A2E38);
  static const Color outlineSoft = Color(0xFF1F2230);

  static const Color textPrimary = Color(0xFFEDEEF2);
  static const Color textSecondary = Color(0xFF8A8F9A);
  static const Color textMuted = Color(0xFF55585F);

  // --- Apple (HIG) semantic aliases -------------------------------------
  // These do not introduce new hues — they are named the way iOS/macOS
  // names its dark-mode text and fill roles (labelPrimary/Secondary/
  // Tertiary, separator, systemFill) so screens can express intent while
  // still resolving to the exact tokens above. No existing hex changes.

  /// Same value as [textPrimary] — Apple's `label` role.
  static const Color labelPrimary = textPrimary;

  /// Same value as [textSecondary] — Apple's `secondaryLabel` role.
  static const Color labelSecondary = textSecondary;

  /// New accessible token for small/tertiary *text* (captions, helper
  /// copy, timestamps). Roughly ~4:1 contrast against [background] and
  /// [surface] — legible at small sizes, unlike [textMuted] which stays
  /// reserved for purely decorative elements (e.g. disabled icon tints)
  /// rather than text a user needs to read.
  static const Color labelTertiary = Color(0xFF6B6F79);

  /// Apple's `separator` role — hairline dividers, list separators.
  /// Same value as [outline].
  static const Color separator = outline;

  /// Apple's `systemFill`-style translucent fill, for subtle control
  /// backgrounds (segmented controls, chip backgrounds) layered over a
  /// surface color rather than replacing it.
  static const Color fill = Color(0x14FFFFFF);

  /// Primary accent — violet glow used everywhere from the QR ring on the
  /// pairing screen to the active item in the bottom tab bar.
  static const Color pulse = Color(0xFF9747FF);
  static const Color pulseGlow = Color(0x669747FF);
  static const Color pulseDeep = Color(0xFF6B2BD9);

  /// Magenta accent reserved for the Half-Heart mode and the gradient on
  /// the subscription CTA. Distinct from [pulse] so the heart visually
  /// pops against the violet field.
  static const Color heart = Color(0xFFFF4D8B);
  static const Color heartGlow = Color(0x66FF4D8B);

  /// Transport quality indicator colors.
  static const Color transportDirect = Color(0xFF4ADE80);
  static const Color transportLocal = Color(0xFF60A5FA);
  static const Color transportRelay = Color(0xFFFBBF24);
  static const Color transportSearching = Color(0xFF8A8F9A);

  /// Destructive actions ("delete connection", error states).
  static const Color danger = Color(0xFFFF5C6E);

  /// Curated palette for connection avatars — all pass on a dark background.
  static const List<Color> avatarPalette = [
    Color(0xFFFFB05C), // Sun  🌞
    Color(0xFFB39CFF), // Moon 🌙
    Color(0xFFFFD86A), // Star ✨
    Color(0xFFFF7CC8), // Comet ☄️
    Color(0xFF7CE0A1),
    Color(0xFF6BD3FF),
    Color(0xFF8A7CFF),
    Color(0xFFE07CFF),
  ];
}
