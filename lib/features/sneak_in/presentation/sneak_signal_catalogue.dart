import 'package:flutter/material.dart';

/// One short, deliberately silly signal that the user can fling at a paused
/// partner. Sound assets live under `assets/sounds/sneak/` (not yet shipped
/// in this PR — the bytes will land alongside a real audio pipeline).
class SneakSignal {
  const SneakSignal({
    required this.id,
    required this.icon,
    required this.assetPath,
  });

  /// Stable id persisted in the protocol — never rename.
  final String id;

  /// Icon shown in the wheel.
  final IconData icon;

  /// Path inside `assets/sounds/`.
  final String assetPath;
}

/// Curated set rendered in the Sneak In wheel. The order is intentional —
/// it determines the angular position on the dial.
const List<SneakSignal> kSneakSignals = [
  SneakSignal(
    id: 'knock',
    icon: Icons.touch_app_rounded,
    assetPath: 'assets/sounds/sneak/knock.opus',
  ),
  SneakSignal(
    id: 'whistle',
    icon: Icons.air_rounded,
    assetPath: 'assets/sounds/sneak/whistle.opus',
  ),
  SneakSignal(
    id: 'bell',
    icon: Icons.notifications_rounded,
    assetPath: 'assets/sounds/sneak/bell.opus',
  ),
  SneakSignal(
    id: 'kiss',
    icon: Icons.favorite_rounded,
    assetPath: 'assets/sounds/sneak/kiss.opus',
  ),
  SneakSignal(
    id: 'pop',
    icon: Icons.bubble_chart_rounded,
    assetPath: 'assets/sounds/sneak/pop.opus',
  ),
  SneakSignal(
    id: 'giggle',
    icon: Icons.sentiment_very_satisfied_rounded,
    assetPath: 'assets/sounds/sneak/giggle.opus',
  ),
  SneakSignal(
    id: 'meow',
    icon: Icons.pets_rounded,
    assetPath: 'assets/sounds/sneak/meow.opus',
  ),
  SneakSignal(
    id: 'hiccup',
    icon: Icons.water_drop_rounded,
    assetPath: 'assets/sounds/sneak/hiccup.opus',
  ),
];
