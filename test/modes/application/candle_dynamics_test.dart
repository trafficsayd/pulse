import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/candle_dynamics.dart';

void main() {
  test('calibration learns the room floor before exposing pressure', () {
    final analyzer = CandleBreathAnalyzer(
      calibrationDuration: const Duration(seconds: 1),
    );
    final start = DateTime(2026);
    for (var i = 0; i < 5; i++) {
      final reading = analyzer.add(
        level: .08,
        noiseLikeness: .4,
        at: start.add(Duration(milliseconds: i * 260)),
      );
      if (i < 4) expect(reading.pressure, 0);
    }
    expect(analyzer.calibrated, isTrue);
    expect(analyzer.noiseFloor, greaterThan(.08));
  });

  test('noise-like breath produces more pressure than voiced speech', () {
    final breath = CandleBreathAnalyzer(calibrationDuration: Duration.zero);
    final speech = CandleBreathAnalyzer(calibrationDuration: Duration.zero);
    final at = DateTime(2026);
    final breathReading = breath.add(
      level: .72,
      noiseLikeness: .9,
      at: at,
    );
    final speechReading = speech.add(
      level: .72,
      noiseLikeness: .08,
      at: at,
    );
    expect(breathReading.pressure, greaterThan(speechReading.pressure * 3));
  });

  test('opposite breaths cancel lean but increase turbulence', () {
    final oneSide = CandleForces.resolve(
      localPressure: .7,
      partnerPressure: 0,
      style: CandleStyle.classic,
    );
    final bothSides = CandleForces.resolve(
      localPressure: .7,
      partnerPressure: .7,
      style: CandleStyle.classic,
    );
    expect(bothSides.lean.abs(), lessThan(.01));
    expect(bothSides.turbulence, greaterThan(oneSide.turbulence));
    expect(bothSides.heightScale, lessThan(oneSide.heightScale));
  });

  test('violet candle is more resistant than classic', () {
    expect(
      CandleStyle.violet.character.extinguishResistance,
      greaterThan(CandleStyle.classic.character.extinguishResistance),
    );
  });

  test('a protecting palm strongly reduces shared wind forces', () {
    final open = CandleForces.resolve(
      localPressure: .8,
      partnerPressure: .6,
      style: CandleStyle.classic,
    );
    final protected = CandleForces.resolve(
      localPressure: .8,
      partnerPressure: .6,
      style: CandleStyle.classic,
      localShielded: true,
    );
    expect(protected.pressure, lessThan(open.pressure * .35));
    expect(protected.turbulence, lessThan(open.turbulence));
  });

  test('wax memory burns gradually and survives serialization', () {
    final fresh = CandleMemory.fresh(seed: 42).copyWith(
      sealedWish: 'Stay close',
    );
    final burned = fresh
        .burn(
          elapsed: const Duration(minutes: 10),
          style: CandleStyle.classic,
          localBreath: .5,
          partnerBreath: .4,
        )
        .finishSession();
    final restored = CandleMemory.fromJson(burned.toJson());
    expect(restored.waxRemaining, lessThan(1));
    expect(restored.sessions, 1);
    expect(restored.sealedWish, 'Stay close');
    expect(restored.smokeSignature, inInclusiveRange(0, 2));
  });

  test('Promise candle requires both people to ignite it', () {
    expect(CandleStyle.violet.character.requiresSharedIgnition, isTrue);
    expect(CandleStyle.classic.character.requiresSharedIgnition, isFalse);
  });
}
