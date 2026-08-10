import 'package:flutter/material.dart';

/// One short, deliberately silly signal that the user can fling at a paused
/// partner. Sound assets live under `assets/sounds/sneak/` as mono AAC
/// (`.m4a`) — raw `.opus` is not decodable by the iOS system players.
class SneakSignal {
  const SneakSignal({
    required this.id,
    required this.icon,
    required this.assetPath,
    required this.emoji,
    required this.titleKey,
  });

  /// Stable id persisted in the protocol — never rename.
  final String id;

  /// Icon shown in the wheel.
  final IconData icon;

  /// Path inside `assets/sounds/`.
  final String assetPath;

  /// Emoji glyph rendered on the wheel tile.
  final String emoji;

  /// Key of the localized display label (see `AppLocalizations`). Metadata
  /// only — kept stable so the wheel and future surfaces can name a signal.
  final String titleKey;
}

/// Curated set rendered in the Sneak In wheel. The order is intentional —
/// it determines the angular position on the dial.
const List<SneakSignal> kSneakSignals = [
  SneakSignal(
    id: 'knock',
    icon: Icons.touch_app_rounded,
    assetPath: 'assets/sounds/sneak/knock.m4a',
    emoji: '🤭',
    titleKey: 'sneakSignalHiccup',
  ),
  SneakSignal(
    id: 'whistle',
    icon: Icons.air_rounded,
    assetPath: 'assets/sounds/sneak/whistle.m4a',
    emoji: '💨',
    titleKey: 'sneakSignalToot',
  ),
  SneakSignal(
    id: 'bell',
    icon: Icons.notifications_rounded,
    assetPath: 'assets/sounds/sneak/bell.m4a',
    emoji: '🔔',
    titleKey: 'sneakSignalBell',
  ),
  SneakSignal(
    id: 'kiss',
    icon: Icons.favorite_rounded,
    assetPath: 'assets/sounds/sneak/kiss.m4a',
    emoji: '👻',
    titleKey: 'sneakSignalKnock',
  ),
  SneakSignal(
    id: 'pop',
    icon: Icons.bubble_chart_rounded,
    assetPath: 'assets/sounds/sneak/pop.m4a',
    emoji: '🤫',
    titleKey: 'sneakSignalWhisper',
  ),
  SneakSignal(
    id: 'giggle',
    icon: Icons.sentiment_very_satisfied_rounded,
    assetPath: 'assets/sounds/sneak/giggle.m4a',
    emoji: '👏',
    titleKey: 'sneakSignalClap',
  ),
  SneakSignal(
    id: 'meow',
    icon: Icons.pets_rounded,
    assetPath: 'assets/sounds/sneak/meow.m4a',
    emoji: '💥',
    titleKey: 'sneakSignalBoom',
  ),
  SneakSignal(
    id: 'hiccup',
    icon: Icons.water_drop_rounded,
    assetPath: 'assets/sounds/sneak/hiccup.m4a',
    emoji: '🐭',
    titleKey: 'sneakSignalSqueak',
  ),
];

/// Look up a signal by its stable wire [id]; `null` for unknown ids (the
/// caller treats that as a silent no-op — forward compatibility with newer
/// peers that may send ids this build does not know yet).
SneakSignal? findSneakSignal(String id) {
  for (final signal in kSneakSignals) {
    if (signal.id == id) return signal;
  }
  return null;
}
