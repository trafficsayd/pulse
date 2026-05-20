import 'package:flutter/foundation.dart';

/// How many people a mode is designed for.
///
/// Almost every starter mode is strictly two-player ([pair]). A few
/// upcoming concepts in the spec are single-player surfaces (Сверчок /
/// Sandbox shake-to-clear / breath warmup), and some group experiences
/// (Хор / Salon) admit 3+ partners. Modes declare a range so the catalog
/// can show "for {min}–{max}" next to the tile and so the runner can
/// short-circuit when a single device tries to launch a pair-only mode.
///
/// Stored on disk as `(min, max)` — values are stable; do NOT rename.
@immutable
class ModeParticipantRange {
  const ModeParticipantRange({required this.min, this.max})
      : assert(min >= 1, 'min must be >= 1'),
        assert(
          max == null || max >= min,
          'max must be >= min when bounded',
        );

  /// Solo experience (1..1) — e.g. Сверчок ambient, Sandbox doodle,
  /// breathing warmup before pairing.
  static const ModeParticipantRange solo = ModeParticipantRange(min: 1, max: 1);

  /// Standard pair (2..2) — the default for every starter mode in Pulse.
  static const ModeParticipantRange pair = ModeParticipantRange(min: 2, max: 2);

  /// Pair-or-group (2..∞) — modes that scale up if more partners join
  /// (Хор / Constellation / Salon).
  static const ModeParticipantRange pairOrGroup = ModeParticipantRange(min: 2);

  final int min;

  /// Inclusive upper bound; `null` means unbounded (e.g. group chat).
  final int? max;

  /// True if [count] participants is within this range.
  bool admits(int count) {
    if (count < min) return false;
    final upper = max;
    if (upper != null && count > upper) return false;
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ModeParticipantRange && other.min == min && other.max == max);

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() {
    final upper = max;
    if (upper == null) return 'ModeParticipantRange($min..∞)';
    if (upper == min) return 'ModeParticipantRange($min)';
    return 'ModeParticipantRange($min..$upper)';
  }
}
