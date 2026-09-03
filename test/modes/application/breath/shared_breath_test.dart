import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/breath/shared_breath_controller.dart';
import 'package:pulse/features/modes/application/breath/shared_breath_models.dart';
import 'package:pulse/features/modes/application/breath/shared_breath_protocol.dart';
import 'package:pulse/features/session/application/mode_event.dart';

void main() {
  test('maps a shared wall-clock cycle into human breathing phases', () {
    final controller = SharedBreathController(cycleMs: 12000);
    expect(controller.sample(nowMs: 1000, intensity: 0, manual: false).phase,
        SharedBreathPhase.inhale);
    expect(controller.sample(nowMs: 4500, intensity: 0, manual: false).phase,
        SharedBreathPhase.settle);
    expect(controller.sample(nowMs: 7000, intensity: 0, manual: false).phase,
        SharedBreathPhase.exhale);
    expect(controller.sample(nowMs: 11500, intensity: 0, manual: false).phase,
        SharedBreathPhase.rest);
  });

  test('coherence rewards matching phase and intensity', () {
    final controller = SharedBreathController();
    const local = SharedBreathSample(
      sequence: 1,
      sentAtMs: 10,
      phase: SharedBreathPhase.exhale,
      phaseProgress: .5,
      intensity: .7,
      manual: false,
    );
    expect(controller.coherence(local, local), 1);
    expect(
      controller.coherence(
        local,
        const SharedBreathSample(
          sequence: 2,
          sentAtMs: 20,
          phase: SharedBreathPhase.inhale,
          phaseProgress: .2,
          intensity: .1,
          manual: true,
        ),
      ),
      lessThan(.6),
    );
  });

  test('v2 protocol round-trips without raw audio', () {
    const sample = SharedBreathSample(
      sequence: 7,
      sentAtMs: 42,
      phase: SharedBreathPhase.exhale,
      phaseProgress: .45,
      intensity: .73,
      manual: true,
    );
    final event = SharedBreathProtocol.encode(sample);
    expect(event.data.keys, isNot(contains('audio')));
    expect(SharedBreathProtocol.decode(event)?.intensity, .73);
  });

  test('legacy event remains compatible and malformed values are rejected', () {
    expect(
      SharedBreathProtocol.decode(
        const ModeEvent(type: 'breath_level', data: {'level': .4}),
      )?.intensity,
      .4,
    );
    expect(
      SharedBreathProtocol.decode(
        const ModeEvent(type: 'breath_level', data: {'level': 4}),
      ),
      isNull,
    );
  });

  test('order guard rejects duplicate and stale v2 samples', () {
    final guard = SharedBreathOrderGuard();
    SharedBreathSample sample(int sequence) => SharedBreathSample(
          sequence: sequence,
          sentAtMs: 50,
          phase: SharedBreathPhase.exhale,
          phaseProgress: .5,
          intensity: .5,
          manual: false,
        );
    expect(guard.accept(sample(2)), isTrue);
    expect(guard.accept(sample(2)), isFalse);
    expect(guard.accept(sample(1)), isFalse);
    expect(guard.accept(sample(3)), isTrue);
  });
}
