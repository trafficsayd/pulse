import 'dart:math' as math;

/// Privacy-safe description of a whisper.
///
/// A frame contains only a few perceptual values. It deliberately cannot
/// reconstruct speech, identify words, or be played back as audio.
class WhisperFeeling {
  const WhisperFeeling({
    required this.sequence,
    required this.capturedAtMs,
    required this.intensity,
    required this.breathiness,
    required this.proximity,
    this.isFallback = false,
  });

  final int sequence;
  final int capturedAtMs;
  final double intensity;
  final double breathiness;
  final double proximity;
  final bool isFallback;

  bool get isSilent => intensity <= 0.01;

  WhisperFeeling normalized() => WhisperFeeling(
        sequence: math.max(0, sequence),
        capturedAtMs: math.max(0, capturedAtMs),
        intensity: intensity.clamp(0.0, 1.0),
        breathiness: breathiness.clamp(0.0, 1.0),
        proximity: proximity.clamp(0.0, 1.0),
        isFallback: isFallback,
      );
}
