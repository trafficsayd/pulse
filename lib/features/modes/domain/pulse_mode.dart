import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import '../../capabilities/domain/device_capability.dart';
import 'mode_participant_range.dart';

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
  // Paid modes (visual placeholders for now):
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
    required this.tint,
    required this.glyph,
    this.requiredCapabilities = const <DeviceCapability>{},
    this.participants = ModeParticipantRange.pair,
  });

  final PulseModeId id;

  /// Icon shown when a Material glyph reads better than the emoji ([glyph]).
  /// Used as a fallback in tests and on the modes-catalog tile.
  final IconData icon;

  /// ARB key for the localized title.
  final String titleKey;

  /// True if the mode belongs to the 7-mode starter set unlocked during the
  /// trial. False means subscription-only.
  final bool isStarter;

  /// Builds the active-mode screen widget. Must be self-contained and avoid
  /// referencing any partner-bound state — the mode runner injects that.
  final WidgetBuilder builder;

  /// Brand tint shown on the carousel tile and the catalog grid. Each
  /// starter mode owns a distinct color so the carousel reads as a chord
  /// of accents rather than a wall of violet.
  final Color tint;

  /// Single emoji shown inside the carousel disc. Pulse is icon-first so
  /// every mode also gets a glyph that reads at small sizes.
  final String glyph;

  /// Hardware/OS capabilities this mode requires to run. The catalog grid
  /// and Hub carousel grey out tiles whose requirements aren't met on
  /// this device, and the diagnostics screen explains *why*.
  final Set<DeviceCapability> requiredCapabilities;

  /// Allowed participant count for this mode. Defaults to a strict pair
  /// ([ModeParticipantRange.pair]); solo modes and group experiences set
  /// this explicitly so the runner can refuse to launch with the wrong
  /// number of partners.
  final ModeParticipantRange participants;
}
