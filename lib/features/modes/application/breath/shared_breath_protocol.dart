import '../../../session/application/mode_event.dart';
import 'shared_breath_models.dart';

abstract final class SharedBreathProtocol {
  static const version = 2;

  static ModeEvent encode(SharedBreathSample value) {
    final sample = value.normalized();
    return ModeEvent(type: 'breath_level', data: {
      'v': version,
      'sequence': sample.sequence,
      'sentAtMs': sample.sentAtMs,
      'phase': sample.phase.name,
      'phaseProgress': _q(sample.phaseProgress),
      'intensity': _q(sample.intensity),
      'manual': sample.manual,
    });
  }

  static SharedBreathSample? decode(ModeEvent event) {
    if (event.type != 'breath_level') return null;
    if (event.data['v'] == null) {
      final level = _unit(event.data['level']);
      if (level == null) return null;
      return SharedBreathSample(
        sequence: 0,
        sentAtMs: 0,
        phase: SharedBreathPhase.exhale,
        phaseProgress: .5,
        intensity: level,
        manual: false,
      );
    }
    if (event.data['v'] != version) return null;
    final sequence = event.data['sequence'];
    final sentAtMs = event.data['sentAtMs'];
    final phaseName = event.data['phase'];
    final progress = _unit(event.data['phaseProgress']);
    final intensity = _unit(event.data['intensity']);
    final manual = event.data['manual'];
    if (sequence is! num ||
        sequence < 0 ||
        sentAtMs is! num ||
        phaseName is! String ||
        progress == null ||
        intensity == null ||
        manual is! bool) {
      return null;
    }
    SharedBreathPhase? phase;
    for (final candidate in SharedBreathPhase.values) {
      if (candidate.name == phaseName) phase = candidate;
    }
    if (phase == null) return null;
    return SharedBreathSample(
      sequence: sequence.toInt(),
      sentAtMs: sentAtMs.toInt(),
      phase: phase,
      phaseProgress: progress,
      intensity: intensity,
      manual: manual,
    );
  }

  static double _q(double value) =>
      (value.clamp(0.0, 1.0) * 1000).round() / 1000;

  static double? _unit(Object? value) {
    if (value is! num || !value.toDouble().isFinite || value < 0 || value > 1) {
      return null;
    }
    return value.toDouble();
  }
}

class SharedBreathOrderGuard {
  int _lastSequence = -1;

  bool accept(SharedBreathSample sample) {
    if (sample.sentAtMs == 0) return true;
    if (sample.sequence <= _lastSequence) return false;
    _lastSequence = sample.sequence;
    return true;
  }
}
