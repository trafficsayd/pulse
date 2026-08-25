import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/mode_registry.dart';
import 'package:pulse/features/modes/domain/pulse_mode.dart';

void main() {
  test('every built-in mode owns at least one incoming wire event', () {
    const events = <String>[
      'tap',
      'hold_start',
      'candle_blow',
      'whisper_level',
      'bell_ring',
      'ray_point',
      'star',
      'goosebumps_wave',
      'thread_point',
      'thunder_strike',
      'firework',
      'balance_ball',
      'sandbox_particle',
      'breath_level',
      'sync_tap',
    ];

    final mapped =
        events.map(modeForEventType).whereType<PulseModeId>().toSet();
    expect(mapped, PulseModeId.values.toSet());
    expect(modeForEventType('unknown'), isNull);
  });
}
