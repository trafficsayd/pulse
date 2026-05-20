import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../capabilities/domain/device_capability.dart';
import '../domain/pulse_mode.dart';
import '../presentation/modes/bell_mode_screen.dart';
import '../presentation/modes/constellation_mode_screen.dart';
import '../presentation/modes/half_heart_mode_screen.dart';
import '../presentation/modes/placeholder_mode_screen.dart';
import '../presentation/modes/ray_sketch_mode_screen.dart';
import '../presentation/modes/tap_tap_mode_screen.dart';
import '../presentation/modes/whisper_mode_screen.dart';

/// Tints used for mode tiles. Each starter mode owns a distinct hue so the
/// carousel/grid reads as a colored chord rather than a wall of violet.
const Color _candleOrange = Color(0xFFFFB05C);
const Color _whisperBlue = Color(0xFF6BD3FF);
const Color _bellYellow = Color(0xFFFFD86A);
const Color _rayCyan = Color(0xFF7CE0A1);
const Color _constellationLavender = Color(0xFFB39CFF);

/// The full ordered set of modes. The first 7 are the trial starter set;
/// the remaining 8 unlock with the subscription. Order is stable on
/// purpose — the carousel index is what `last-used mode` is keyed by.
final List<PulseModeDescriptor> kAllModes = [
  PulseModeDescriptor(
    id: PulseModeId.tapTap,
    icon: Icons.touch_app_rounded,
    titleKey: 'modeTapTap',
    isStarter: true,
    tint: AppColors.pulse,
    glyph: '👆',
    builder: (context) => const TapTapModeScreen(),
  ),
  PulseModeDescriptor(
    id: PulseModeId.halfHeart,
    icon: Icons.favorite_rounded,
    titleKey: 'modeHalfHeart',
    isStarter: true,
    tint: AppColors.heart,
    glyph: '❤️',
    builder: (context) => const HalfHeartModeScreen(),
  ),
  PulseModeDescriptor(
    id: PulseModeId.candle,
    icon: Icons.local_fire_department_rounded,
    titleKey: 'modeCandle',
    isStarter: true,
    tint: _candleOrange,
    glyph: '🕯️',
    builder: (context) => const PlaceholderModeScreen(titleKey: 'modeCandle'),
  ),
  PulseModeDescriptor(
    id: PulseModeId.whisper,
    icon: Icons.graphic_eq_rounded,
    titleKey: 'modeWhisper',
    isStarter: true,
    tint: _whisperBlue,
    glyph: '🌬️',
    requiredCapabilities: const {
      DeviceCapability.microphone,
      DeviceCapability.vibration,
    },
    builder: (context) => const WhisperModeScreen(),
  ),
  PulseModeDescriptor(
    id: PulseModeId.bell,
    icon: Icons.notifications_rounded,
    titleKey: 'modeBell',
    isStarter: true,
    tint: _bellYellow,
    glyph: '🔔',
    requiredCapabilities: const {DeviceCapability.accelerometer},
    builder: (context) => const BellModeScreen(),
  ),
  PulseModeDescriptor(
    id: PulseModeId.ray,
    icon: Icons.brush_rounded,
    titleKey: 'modeRay',
    isStarter: true,
    tint: _rayCyan,
    glyph: '✨',
    builder: (context) => const RaySketchModeScreen(),
  ),
  PulseModeDescriptor(
    id: PulseModeId.constellation,
    icon: Icons.star_outline_rounded,
    titleKey: 'modeConstellation',
    isStarter: true,
    tint: _constellationLavender,
    glyph: '⭐',
    builder: (context) => const ConstellationModeScreen(),
  ),
  // Subscription-only modes — placeholders for now, but they appear in the
  // catalog grid and the locked Hub tile so the design lands fully.
  PulseModeDescriptor(
    id: PulseModeId.goosebumps,
    icon: Icons.waves_rounded,
    titleKey: 'modeGoosebumps',
    isStarter: false,
    tint: AppColors.textSecondary,
    glyph: '💫',
    requiredCapabilities: const {
      DeviceCapability.vibration,
      DeviceCapability.vibrationAmplitude,
    },
    builder: (context) =>
        const PlaceholderModeScreen(titleKey: 'modeGoosebumps'),
  ),
  PulseModeDescriptor(
    id: PulseModeId.thread,
    icon: Icons.timeline_rounded,
    titleKey: 'modeThread',
    isStarter: false,
    tint: AppColors.textSecondary,
    glyph: '🧵',
    builder: (context) => const PlaceholderModeScreen(titleKey: 'modeThread'),
  ),
  PulseModeDescriptor(
    id: PulseModeId.thunder,
    icon: Icons.bolt_rounded,
    titleKey: 'modeThunder',
    isStarter: false,
    tint: AppColors.textSecondary,
    glyph: '⚡',
    requiredCapabilities: const {
      DeviceCapability.microphone,
      DeviceCapability.flashlight,
    },
    builder: (context) => const PlaceholderModeScreen(titleKey: 'modeThunder'),
  ),
  PulseModeDescriptor(
    id: PulseModeId.fireworks,
    icon: Icons.celebration_rounded,
    titleKey: 'modeFireworks',
    isStarter: false,
    tint: AppColors.textSecondary,
    glyph: '🎆',
    builder: (context) =>
        const PlaceholderModeScreen(titleKey: 'modeFireworks'),
  ),
  PulseModeDescriptor(
    id: PulseModeId.balance,
    icon: Icons.balance_rounded,
    titleKey: 'modeBalance',
    isStarter: false,
    tint: AppColors.textSecondary,
    glyph: '⚖️',
    requiredCapabilities: const {DeviceCapability.accelerometer},
    builder: (context) => const PlaceholderModeScreen(titleKey: 'modeBalance'),
  ),
  PulseModeDescriptor(
    id: PulseModeId.sandbox,
    icon: Icons.grain_rounded,
    titleKey: 'modeSandbox',
    isStarter: false,
    tint: AppColors.textSecondary,
    glyph: '⏳',
    builder: (context) => const PlaceholderModeScreen(titleKey: 'modeSandbox'),
  ),
  PulseModeDescriptor(
    id: PulseModeId.breath,
    icon: Icons.air_rounded,
    titleKey: 'modeBreath',
    isStarter: false,
    tint: AppColors.textSecondary,
    glyph: '🌀',
    requiredCapabilities: const {DeviceCapability.microphone},
    builder: (context) => const PlaceholderModeScreen(titleKey: 'modeBreath'),
  ),
  PulseModeDescriptor(
    id: PulseModeId.sync,
    icon: Icons.sync_rounded,
    titleKey: 'modeSync',
    isStarter: false,
    tint: AppColors.textSecondary,
    glyph: '🔄',
    builder: (context) => const PlaceholderModeScreen(titleKey: 'modeSync'),
  ),
];

/// Just the 7 starter modes — used by the Hub circular layout, where only
/// the trial set is rendered alongside a single locked "more" tile.
List<PulseModeDescriptor> get kStarterModes =>
    kAllModes.where((m) => m.isStarter).toList(growable: false);

/// Just the paid modes — used by the catalog grid's bottom section.
List<PulseModeDescriptor> get kPaidModes =>
    kAllModes.where((m) => !m.isStarter).toList(growable: false);

PulseModeDescriptor? findMode(PulseModeId id) {
  for (final m in kAllModes) {
    if (m.id == id) return m;
  }
  return null;
}

/// Resolve the localized title for [m] from the supplied l10n object.
String localizedModeTitle(PulseModeDescriptor m, AppLocalizations l10n) {
  switch (m.id) {
    case PulseModeId.tapTap:
      return l10n.modeTapTap;
    case PulseModeId.halfHeart:
      return l10n.modeHalfHeart;
    case PulseModeId.candle:
      return l10n.modeCandle;
    case PulseModeId.whisper:
      return l10n.modeWhisper;
    case PulseModeId.bell:
      return l10n.modeBell;
    case PulseModeId.ray:
      return l10n.modeRay;
    case PulseModeId.constellation:
      return l10n.modeConstellation;
    case PulseModeId.goosebumps:
      return l10n.modeGoosebumps;
    case PulseModeId.thread:
      return l10n.modeThread;
    case PulseModeId.thunder:
      return l10n.modeThunder;
    case PulseModeId.fireworks:
      return l10n.modeFireworks;
    case PulseModeId.balance:
      return l10n.modeBalance;
    case PulseModeId.sandbox:
      return l10n.modeSandbox;
    case PulseModeId.breath:
      return l10n.modeBreath;
    case PulseModeId.sync:
      return l10n.modeSync;
  }
}
