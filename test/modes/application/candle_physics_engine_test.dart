import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/candle_dynamics.dart';
import 'package:pulse/features/modes/application/candle_material_profile.dart';
import 'package:pulse/features/modes/application/candle_physics_engine.dart';
import 'package:pulse/features/modes/application/candle_world_state.dart';

void main() {
  const engine = CandlePhysicsEngine();
  const frame = Duration(milliseconds: 16);

  CandleWorldState run(
    CandleWorldState state,
    CandlePhysicsInput input,
    int frames,
  ) {
    for (var i = 0; i < frames; i++) {
      state = engine.step(state, input, frame);
    }
    return state;
  }

  test('calm flame converges without freezing into a perfect still shape', () {
    final state = run(
      CandleWorldState.resting(lit: true),
      const CandlePhysicsInput(),
      120,
    );
    expect(state.wickPhase, CandleWickPhase.burning);
    expect(state.flameEnergy, closeTo(1, .04));
    expect(state.turbulence, greaterThanOrEqualTo(0));
    expect(state.flameHeight, greaterThan(.9));
  });

  test('weak breath bends the flame but cannot extinguish it', () {
    final state = run(
      CandleWorldState.resting(lit: true),
      const CandlePhysicsInput(localBreath: .32),
      180,
    );
    expect(state.wickPhase, CandleWickPhase.burning);
    expect(state.lean, greaterThan(.15));
    expect(state.extinguishExposure, lessThan(.1));
  });

  test('sustained strong breath produces a smoldering ember and smoke', () {
    final state = run(
      CandleWorldState.resting(lit: true),
      const CandlePhysicsInput(localBreath: 1),
      180,
    );
    expect(
      state.wickPhase,
      anyOf(CandleWickPhase.smoldering, CandleWickPhase.cold),
    );
    expect(state.flameEnergy, lessThan(.05));
    expect(state.smokeDensity + state.ember, greaterThan(.2));
  });

  test('a protecting palm keeps the same strong breath from putting it out',
      () {
    final state = run(
      CandleWorldState.resting(lit: true),
      const CandlePhysicsInput(localBreath: 1, localShielded: true),
      240,
    );
    expect(state.wickPhase, CandleWickPhase.burning);
    expect(state.extinguishExposure, lessThan(.12));
  });

  test('opposite breaths cancel lean and create more turbulence', () {
    final oneSide = engine.step(
      CandleWorldState.resting(lit: true),
      const CandlePhysicsInput(localBreath: .55),
      const Duration(milliseconds: 100),
    );
    final bothSides = engine.step(
      CandleWorldState.resting(lit: true),
      const CandlePhysicsInput(localBreath: .55, partnerBreath: .55),
      const Duration(milliseconds: 100),
    );
    expect(bothSides.lean.abs(), lessThan(oneSide.lean.abs() * .1));
    expect(bothSides.turbulence, greaterThan(oneSide.turbulence));
  });

  test('two touches build shared heat while one touch does not', () {
    final one = run(
      CandleWorldState.resting(lit: true),
      const CandlePhysicsInput(localTouchHeat: 1),
      120,
    );
    final together = run(
      CandleWorldState.resting(lit: true),
      const CandlePhysicsInput(localTouchHeat: 1, partnerTouchHeat: 1),
      120,
    );
    expect(one.sharedHeat, 0);
    expect(together.sharedHeat, greaterThan(.9));
    expect(together.flameEnergy, greaterThan(one.flameEnergy));
  });

  test('quiet dual touch slowly becomes a shared stillness ritual', () {
    final state = run(
      CandleWorldState.resting(lit: true),
      const CandlePhysicsInput(
        localShielded: true,
        partnerShielded: true,
        localTouchHeat: 1,
        partnerTouchHeat: 1,
      ),
      360,
    );

    expect(state.sharedHeat, greaterThan(.9));
    expect(state.sharedStillness, greaterThan(.8));
    expect(state.flameEnergy, greaterThan(.95));
  });

  test('tilting the phone moves flame and molten surface together', () {
    final state = run(
      CandleWorldState.resting(lit: true),
      const CandlePhysicsInput(tilt: .8),
      240,
    );
    expect(state.lean, greaterThan(.2));
    expect(state.waxSurfaceOffset, greaterThan(.1));
  });

  test('glass shelters airflow more than open hand-poured wax', () {
    expect(
      CandleStyle.glass.material.airflowShelter,
      greaterThan(CandleStyle.classic.material.airflowShelter),
    );
    final classic = run(
      CandleWorldState.resting(style: CandleStyle.classic, lit: true),
      const CandlePhysicsInput(localBreath: .8),
      90,
    );
    final glass = run(
      CandleWorldState.resting(style: CandleStyle.glass, lit: true),
      const CandlePhysicsInput(localBreath: .8),
      90,
    );
    expect(glass.extinguishExposure, lessThan(classic.extinguishExposure));
  });

  test('the fixed-step engine is deterministic for identical inputs', () {
    CandleWorldState simulate() => run(
          CandleWorldState.resting(style: CandleStyle.violet, lit: true),
          const CandlePhysicsInput(
            localBreath: .42,
            partnerBreath: .24,
            tilt: -.18,
            localTouchHeat: .7,
            partnerTouchHeat: .8,
          ),
          160,
        );

    final first = simulate();
    final second = simulate();
    expect(first.simulationSeconds, second.simulationSeconds);
    expect(first.flameEnergy, second.flameEnergy);
    expect(first.lean, second.lean);
    expect(first.moltenWax, second.moltenWax);
    expect(first.sharedHeat, second.sharedHeat);
  });
}
