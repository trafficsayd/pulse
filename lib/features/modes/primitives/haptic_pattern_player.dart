import 'dart:async';

import '../../capabilities/domain/device_capability.dart';

/// A single beat in a haptic pattern.
///
/// [duration] is the on-time of the pulse; [amplitude] in `[0,255]` is the
/// strength on devices that support amplitude control (see
/// [DeviceCapability.vibrationAmplitude]). On devices without amplitude
/// control we collapse to a binary on/off.
class HapticBeat {
  const HapticBeat({
    required this.duration,
    this.amplitude = 255,
    this.gapAfter = Duration.zero,
  });

  final Duration duration;
  final int amplitude;
  final Duration gapAfter;
}

/// Concrete pattern that a mode wants to play. Patterns are values —
/// callers re-use them, e.g. `HapticPatterns.heartbeat`.
class HapticPattern {
  const HapticPattern(this.beats);

  final List<HapticBeat> beats;

  Duration get totalDuration {
    var total = Duration.zero;
    for (final b in beats) {
      total += b.duration;
      total += b.gapAfter;
    }
    return total;
  }
}

/// Library of named patterns used across modes. Keeping them in one place
/// keeps the "Pulse vocabulary" consistent — e.g. every "ack" feels the
/// same regardless of which mode triggered it.
abstract final class HapticPatterns {
  /// Single quick tap. Used for taps, button confirmations.
  static const HapticPattern tap = HapticPattern([
    HapticBeat(duration: Duration(milliseconds: 30)),
  ]);

  /// "Heart-beat" lub-dub. Used for Half-Heart, Pulse-Thread.
  static const HapticPattern heartbeat = HapticPattern([
    HapticBeat(duration: Duration(milliseconds: 70), amplitude: 200),
    HapticBeat(
      duration: Duration(milliseconds: 50),
      amplitude: 128,
      gapAfter: Duration(milliseconds: 280),
    ),
  ]);

  /// Long sustained pulse (~0.5s). Used for Whisper / Echo arrival.
  static const HapticPattern whisper = HapticPattern([
    HapticBeat(
      duration: Duration(milliseconds: 500),
      amplitude: 64,
    ),
  ]);

  /// Triple-tap ack. Used for sneak-in acknowledged.
  static const HapticPattern triple = HapticPattern([
    HapticBeat(
      duration: Duration(milliseconds: 30),
      gapAfter: Duration(milliseconds: 90),
    ),
    HapticBeat(
      duration: Duration(milliseconds: 30),
      gapAfter: Duration(milliseconds: 90),
    ),
    HapticBeat(duration: Duration(milliseconds: 30)),
  ]);
}

/// Interface for whoever actually rings the vibrator. The Riverpod
/// provider injects a real implementation backed by `package:vibration`
/// on device, and tests swap in [RecordingHapticEngine] or
/// [NullHapticEngine].
abstract class HapticEngine {
  /// True if the device has any vibrator at all.
  bool get hasVibrator;

  /// True if the engine can vary [HapticBeat.amplitude] per pulse.
  bool get hasAmplitudeControl;

  Future<void> playBeat(HapticBeat beat);

  /// Stop any in-flight buzz right now. Called when a mode exits or the
  /// app is backgrounded.
  Future<void> cancel();
}

/// Records every beat it's asked to play. Used in widget tests to assert
/// "this gesture produced *exactly* this pattern".
class RecordingHapticEngine implements HapticEngine {
  RecordingHapticEngine({
    this.hasVibrator = true,
    this.hasAmplitudeControl = true,
  });

  @override
  final bool hasVibrator;

  @override
  final bool hasAmplitudeControl;

  final List<HapticBeat> played = [];

  @override
  Future<void> playBeat(HapticBeat beat) async {
    played.add(beat);
  }

  @override
  Future<void> cancel() async {}
}

/// No-op engine for platforms / devices with no vibrator. Modes call it
/// the same way they would the real engine — the absence of feedback is
/// silent, never a crash.
class NullHapticEngine implements HapticEngine {
  const NullHapticEngine();

  @override
  bool get hasVibrator => false;

  @override
  bool get hasAmplitudeControl => false;

  @override
  Future<void> playBeat(HapticBeat beat) async {}

  @override
  Future<void> cancel() async {}
}

/// Orchestrates a [HapticPattern] over a [HapticEngine].
///
/// Why this isn't just `await for (final beat in pattern.beats) engine.play(beat)`:
///   * We need *cancellable* playback — if the user exits the mode mid-pulse
///     the next beat must not fire.
///   * On devices without amplitude control we still want the rhythm to
///     come through, so we play each beat at full strength instead of
///     skipping it.
///   * Energy: pattern playback grabs no exclusive lock and yields after
///     each beat, so background isolates can run between pulses.
class HapticPatternPlayer {
  HapticPatternPlayer(this._engine);

  final HapticEngine _engine;

  Completer<void>? _activeCompleter;
  bool _cancelled = false;

  /// True if a pattern is currently being played.
  bool get isPlaying =>
      _activeCompleter != null && !_activeCompleter!.isCompleted;

  /// Plays [pattern] beat-by-beat. Returns when the last beat has
  /// finished (or [stop] was called).
  Future<void> play(HapticPattern pattern) async {
    await stop();
    _cancelled = false;
    final completer = Completer<void>();
    _activeCompleter = completer;
    try {
      for (final beat in pattern.beats) {
        if (_cancelled) break;
        await _engine.playBeat(beat);
        await Future<void>.delayed(beat.duration);
        if (beat.gapAfter > Duration.zero) {
          await Future<void>.delayed(beat.gapAfter);
        }
      }
    } finally {
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// Cancels any in-flight pattern. Safe to call when nothing's playing.
  Future<void> stop() async {
    _cancelled = true;
    await _engine.cancel();
    final c = _activeCompleter;
    if (c != null && !c.isCompleted) {
      await c.future;
    }
    _activeCompleter = null;
  }
}
