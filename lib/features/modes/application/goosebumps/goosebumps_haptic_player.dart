import 'dart:async';

import '../../../haptics/application/pulse_haptic_engine.dart';
import '../tap_tap/knock_models.dart';
import 'goosebumps_wave.dart';

/// Converts a continuous cross-device wave into a short sequence understood by
/// the shared Touch/Haptic Engine. The platform bridge supplies system-haptic
/// fallback on devices without precise transient control.
class GoosebumpsHapticPlayer {
  GoosebumpsHapticPlayer(this._engine);

  final PulseHapticEngine _engine;
  int _generation = 0;
  Timer? _delayTimer;
  Completer<void>? _delayCompleter;

  Future<void> play(GoosebumpsWave wave) async {
    stop();
    final generation = _generation;
    final pulseCount = (5 + wave.intensity * 4).round();
    final interval = (wave.travelMs / (pulseCount + 1)).round();
    for (var index = 0; index < pulseCount; index++) {
      if (generation != _generation) return;
      final phase = pulseCount == 1 ? .5 : index / (pulseCount - 1);
      final envelope = 1 - (2 * phase - 1).abs() * .58;
      final intensity =
          (.16 + wave.intensity * .78 * envelope).clamp(0.0, 1.0).toDouble();
      await _engine.playKnock(KnockCharacter(
        intensity: intensity,
        sharpness: (.24 + wave.speed * .58 + envelope * .12)
            .clamp(0.0, 1.0)
            .toDouble(),
        durationMs: (34 + intensity * 58).round(),
        contactClass:
            intensity > .7 ? KnockContactClass.broad : KnockContactClass.soft,
        confidence: .9,
      ));
      if (index + 1 < pulseCount) {
        await _delay(Duration(milliseconds: interval));
      }
    }
  }

  Future<void> _delay(Duration duration) {
    final completer = Completer<void>();
    _delayCompleter = completer;
    _delayTimer = Timer(duration, () {
      _delayTimer = null;
      _delayCompleter = null;
      completer.complete();
    });
    return completer.future;
  }

  void stop() {
    _generation++;
    _delayTimer?.cancel();
    _delayTimer = null;
    final completer = _delayCompleter;
    _delayCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }
}
