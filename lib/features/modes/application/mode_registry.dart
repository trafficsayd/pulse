import 'package:flutter/material.dart';

import '../domain/pulse_mode.dart';
import '../presentation/modes/bell_mode_screen.dart';
import '../presentation/modes/candle_mode_screen.dart';
import '../presentation/modes/constellation_mode_screen.dart';
import '../presentation/modes/half_heart_mode_screen.dart';
import '../presentation/modes/ray_mode_screen.dart';
import '../presentation/modes/sketch_mode_screen.dart';
import '../presentation/modes/tap_tap_mode_screen.dart';
import '../presentation/modes/whisper_mode_screen.dart';

/// The full ordered set of modes available in the carousel.
///
/// Order is stable on purpose — the carousel index is what `last-used mode`
/// is keyed by, so re-ordering would change muscle memory for users who
/// relied on a particular swipe distance.
final List<PulseModeDescriptor> kAllModes = [
  PulseModeDescriptor(
    id: PulseModeId.tapTap,
    icon: Icons.touch_app_rounded,
    titleKey: 'modeTapTap',
    isStarter: true,
    builder: (context) => const TapTapModeScreen(),
  ),
  PulseModeDescriptor(
    id: PulseModeId.halfHeart,
    icon: Icons.favorite_rounded,
    titleKey: 'modeHalfHeart',
    isStarter: true,
    builder: (context) => const HalfHeartModeScreen(),
  ),
  PulseModeDescriptor(
    id: PulseModeId.candle,
    icon: Icons.local_fire_department_rounded,
    titleKey: 'modeCandle',
    isStarter: true,
    builder: (context) => const CandleModeScreen(),
  ),
  PulseModeDescriptor(
    id: PulseModeId.whisper,
    icon: Icons.graphic_eq_rounded,
    titleKey: 'modeWhisper',
    isStarter: true,
    builder: (context) => const WhisperModeScreen(),
  ),
  PulseModeDescriptor(
    id: PulseModeId.bell,
    icon: Icons.notifications_rounded,
    titleKey: 'modeBell',
    isStarter: true,
    builder: (context) => const BellModeScreen(),
  ),
  PulseModeDescriptor(
    id: PulseModeId.ray,
    icon: Icons.auto_fix_high_rounded,
    titleKey: 'modeRay',
    isStarter: true,
    builder: (context) => const RayModeScreen(),
  ),
  PulseModeDescriptor(
    id: PulseModeId.constellation,
    icon: Icons.star_outline_rounded,
    titleKey: 'modeConstellation',
    isStarter: true,
    builder: (context) => const ConstellationModeScreen(),
  ),
  PulseModeDescriptor(
    id: PulseModeId.sketch,
    icon: Icons.brush_rounded,
    titleKey: 'modeSketch',
    isStarter: true,
    builder: (context) => const SketchModeScreen(),
  ),
];

PulseModeDescriptor? findMode(PulseModeId id) {
  for (final m in kAllModes) {
    if (m.id == id) return m;
  }
  return null;
}
