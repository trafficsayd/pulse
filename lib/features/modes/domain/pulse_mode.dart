import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

/// Stable identifier for a built-in mode. The string value is what's stored
/// on disk (last-used mode, analytics if ever opted in, etc.) — do NOT
/// rename existing entries.
enum PulseModeId {
  tapTap,
  halfHeart,
  candle,
  whisper,
  bell,
  ray,
  constellation,
  // LoveSketch-inspired drawing canvas with a daily-stroke quota.
  sketch,
  // Paid modes (not yet implemented):
  goosebumps,
  thread,
  thunder,
  fireworks,
  balance,
  sandbox,
  breath,
  sync,
}

/// Metadata describing a mode in the carousel and lock state.
@immutable
class PulseModeDescriptor {
  const PulseModeDescriptor({
    required this.id,
    required this.icon,
    required this.titleKey,
    required this.isStarter,
    required this.builder,
  });

  final PulseModeId id;

  /// Icon shown in the hub carousel.
  final IconData icon;

  /// ARB key for the localized title (used when the carousel surfaces text;
  /// the carousel is icon-first by default).
  final String titleKey;

  /// True if the mode belongs to the 7-mode starter set unlocked during the
  /// trial. False means subscription-only.
  final bool isStarter;

  /// Builds the active-mode screen widget. Must be self-contained and avoid
  /// referencing any partner-bound state — the mode runner injects that.
  final WidgetBuilder builder;
}
