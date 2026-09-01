import 'dart:math' as math;

import '../../primitives/mic_level_stream.dart';
import 'whisper_feeling.dart';

/// Converts transient microphone measurements into non-reversible feeling
/// parameters. All state is held in memory and can be discarded immediately
/// when the mode closes.
class AudioFeelingController {
  AudioFeelingController({
    this.minimumSendInterval = const Duration(milliseconds: 80),
    this.minimumChange = 0.025,
  });

  final Duration minimumSendInterval;
  final double minimumChange;

  double _noiseFloor = 0.025;
  double _intensity = 0;
  double _breathiness = 0.65;
  double _proximity = 0;
  int _sequence = 0;
  DateTime? _lastSentAt;
  WhisperFeeling? _lastSent;

  double get noiseFloor => _noiseFloor;

  /// Processes a local sample. The input is never retained.
  WhisperFeeling process(MicLevel sample) {
    final raw = sample.level01.clamp(0.0, 1.0);
    final noisiness = sample.noiseLikeness.clamp(0.0, 1.0);

    // Learn the room only from quiet samples; a whisper must not raise the
    // baseline and suppress itself. The slow coefficient avoids pumping.
    if (raw < math.max(0.12, _noiseFloor * 2.2)) {
      _noiseFloor = (_noiseFloor * 0.985 + raw * 0.015).clamp(0.008, 0.18);
    }
    final gated =
        ((raw - _noiseFloor - 0.012) / math.max(0.18, 1 - _noiseFloor - 0.012))
            .clamp(0.0, 1.0);
    final perceived = math.pow(gated, 0.58).toDouble();

    // Quick attack preserves immediacy; slow release feels like warm air
    // dissipating rather than a meter snapping back to zero.
    final intensityFactor = perceived > _intensity ? 0.58 : 0.14;
    _intensity += (perceived - _intensity) * intensityFactor;
    _breathiness += (noisiness - _breathiness) * 0.2;
    final targetProximity =
        math.sqrt(_intensity) * (0.72 + _breathiness * 0.28);
    _proximity += (targetProximity - _proximity) * 0.24;

    return WhisperFeeling(
      sequence: _sequence++,
      capturedAtMs: sample.timestamp.millisecondsSinceEpoch,
      intensity: _intensity,
      breathiness: _breathiness,
      proximity: _proximity,
    ).normalized();
  }

  /// Generates a privacy-safe manual breath when microphone access is absent
  /// or intentionally disabled. [phase] runs from 0 at touch-down to 1.
  WhisperFeeling fallback(double phase, DateTime at) {
    final t = phase.clamp(0.0, 1.0);
    final envelope = math.sin(t * math.pi).clamp(0.0, 1.0).toDouble();
    return WhisperFeeling(
      sequence: _sequence++,
      capturedAtMs: at.millisecondsSinceEpoch,
      intensity: 0.16 + envelope * 0.48,
      breathiness: 0.9,
      proximity: 0.24 + envelope * 0.58,
      isFallback: true,
    );
  }

  WhisperFeeling silence(DateTime at, {bool isFallback = false}) =>
      WhisperFeeling(
        sequence: _sequence++,
        capturedAtMs: at.millisecondsSinceEpoch,
        intensity: 0,
        breathiness: _breathiness,
        proximity: 0,
        isFallback: isFallback,
      );

  bool shouldSend(WhisperFeeling next, {bool force = false}) {
    final lastAt = _lastSentAt;
    if (!force &&
        lastAt != null &&
        DateTime.fromMillisecondsSinceEpoch(next.capturedAtMs)
                .difference(lastAt) <
            minimumSendInterval) {
      return false;
    }
    final last = _lastSent;
    final changed = last == null ||
        (next.intensity - last.intensity).abs() >= minimumChange ||
        (next.breathiness - last.breathiness).abs() >= minimumChange ||
        (next.proximity - last.proximity).abs() >= minimumChange ||
        next.isSilent != last.isSilent;
    if (!force && !changed) return false;
    _lastSentAt = DateTime.fromMillisecondsSinceEpoch(next.capturedAtMs);
    _lastSent = next;
    return true;
  }
}

/// Drops duplicated or re-ordered v2 frames while keeping v1 compatibility.
class WhisperReceiver {
  int _lastSequence = -1;

  bool accept(WhisperFeeling frame) {
    if (frame.capturedAtMs == 0 && frame.sequence == 0) return true;
    if (frame.sequence <= _lastSequence) return false;
    _lastSequence = frame.sequence;
    return true;
  }
}
