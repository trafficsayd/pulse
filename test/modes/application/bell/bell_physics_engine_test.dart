import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/bell/bell_models.dart';
import 'package:pulse/features/modes/application/bell/bell_physics_engine.dart';

void main() {
  test('same input timeline produces identical physical state', () {
    final first = BellPhysicsEngine(idFactory: () => 'same');
    final second = BellPhysicsEngine(idFactory: () => 'same');
    final inputs = <BellMotionInput>[
      const BellMotionInput(gestureImpulse: 3.8),
      ...List.generate(
        80,
        (index) => BellMotionInput(
          tangentialAcceleration: index < 18 ? .42 : 0,
        ),
      ),
    ];

    for (var i = 0; i < inputs.length; i++) {
      final a = first.step(inputs[i], 1 / 60, nowMs: i * 16);
      final b = second.step(inputs[i], 1 / 60, nowMs: i * 16);
      expect(a.state.approximatelyEquals(b.state), isTrue);
      expect(a.strike?.strength, b.strike?.strength);
      expect(a.strike?.direction, b.strike?.direction);
    }
  });

  test('strong impulse makes the clapper strike and resonance then decays', () {
    final engine = BellPhysicsEngine(idFactory: () => 'strike-1');
    engine.applyImpulse(4.6);
    BellStrike? strike;
    var peakResonance = 0.0;
    for (var i = 0; i < 180; i++) {
      final result = engine.step(
        const BellMotionInput(),
        1 / 120,
        nowMs: i * 8,
      );
      strike ??= result.strike;
      if (result.state.resonance > peakResonance) {
        peakResonance = result.state.resonance;
      }
    }

    expect(strike, isNotNull);
    expect(strike!.strength, inInclusiveRange(.08, 1));
    expect(peakResonance, greaterThan(.3));
    expect(engine.state.resonance, lessThan(peakResonance));
  });

  test('tiny motion does not create a false strike', () {
    final engine = BellPhysicsEngine();
    for (var i = 0; i < 240; i++) {
      final result = engine.step(
        BellMotionInput(tangentialAcceleration: i.isEven ? .025 : -.025),
        1 / 60,
        nowMs: i * 16,
      );
      expect(result.strike, isNull);
    }
  });

  test('material profiles have distinct physical and tactile character', () {
    final brass = BellMaterialProfile.forMaterial(BellMaterial.brass);
    final crystal = BellMaterialProfile.forMaterial(BellMaterial.crystal);
    final porcelain = BellMaterialProfile.forMaterial(BellMaterial.porcelain);

    expect(brass.inertia, greaterThan(crystal.inertia));
    expect(crystal.resonanceSeconds, greaterThan(brass.resonanceSeconds));
    expect(porcelain.bodyDamping, greaterThan(crystal.bodyDamping));
    expect({brass.pitch, crystal.pitch, porcelain.pitch}.length, 3);
  });
}
