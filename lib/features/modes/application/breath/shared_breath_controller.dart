import 'dart:math' as math;

import 'shared_breath_models.dart';

class SharedBreathController {
  SharedBreathController({this.cycleMs = 12000});

  final int cycleMs;
  int _sequence = 0;

  SharedBreathSample sample({
    required int nowMs,
    required double intensity,
    required bool manual,
    bool advanceSequence = true,
  }) {
    final unit = (nowMs % cycleMs) / cycleMs;
    final phase = switch (unit) {
      < .34 => SharedBreathPhase.inhale,
      < .42 => SharedBreathPhase.settle,
      < .92 => SharedBreathPhase.exhale,
      _ => SharedBreathPhase.rest,
    };
    final (start, length) = switch (phase) {
      SharedBreathPhase.inhale => (0.0, .34),
      SharedBreathPhase.settle => (.34, .08),
      SharedBreathPhase.exhale => (.42, .50),
      SharedBreathPhase.rest => (.92, .08),
    };
    final sequence = _sequence;
    if (advanceSequence) _sequence++;
    return SharedBreathSample(
      sequence: sequence,
      sentAtMs: nowMs,
      phase: phase,
      phaseProgress: ((unit - start) / length).clamp(0.0, 1.0),
      intensity: intensity.clamp(0.0, 1.0),
      manual: manual,
    );
  }

  double coherence(SharedBreathSample local, SharedBreathSample? remote) {
    if (remote == null) return 0;
    final localAngle = _cyclePosition(local) * math.pi * 2;
    final remoteAngle = _cyclePosition(remote) * math.pi * 2;
    final phaseDistance = (math
                .atan2(math.sin(localAngle - remoteAngle),
                    math.cos(localAngle - remoteAngle))
                .abs() /
            math.pi)
        .clamp(0.0, 1.0);
    final intensityDistance = (local.intensity - remote.intensity).abs();
    return (1 - phaseDistance * .72 - intensityDistance * .28).clamp(0.0, 1.0);
  }

  double _cyclePosition(SharedBreathSample value) {
    final (start, length) = switch (value.phase) {
      SharedBreathPhase.inhale => (0.0, .34),
      SharedBreathPhase.settle => (.34, .08),
      SharedBreathPhase.exhale => (.42, .50),
      SharedBreathPhase.rest => (.92, .08),
    };
    return start + value.phaseProgress * length;
  }
}
