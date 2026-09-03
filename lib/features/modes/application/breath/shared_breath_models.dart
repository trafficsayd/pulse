enum SharedBreathPhase { inhale, settle, exhale, rest }

class SharedBreathSample {
  const SharedBreathSample({
    required this.sequence,
    required this.sentAtMs,
    required this.phase,
    required this.phaseProgress,
    required this.intensity,
    required this.manual,
  });

  final int sequence;
  final int sentAtMs;
  final SharedBreathPhase phase;
  final double phaseProgress;
  final double intensity;
  final bool manual;

  SharedBreathSample normalized() => SharedBreathSample(
        sequence: sequence.clamp(0, 0x7fffffff),
        sentAtMs: sentAtMs,
        phase: phase,
        phaseProgress: phaseProgress.clamp(0.0, 1.0),
        intensity: intensity.clamp(0.0, 1.0),
        manual: manual,
      );
}

class SharedBreathState {
  const SharedBreathState({
    required this.local,
    this.remote,
    required this.coherence,
  });

  final SharedBreathSample local;
  final SharedBreathSample? remote;
  final double coherence;
}
