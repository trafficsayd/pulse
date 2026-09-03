import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/goosebumps/goosebumps_motion_engine.dart';
import 'package:pulse/features/modes/application/goosebumps/goosebumps_wave.dart';

void main() {
  test('gesture controls direction, speed and pressure-based intensity', () {
    final wave = GoosebumpsMotionEngine.fromGesture(
      id: 'wave-1',
      samples: const [
        GoosebumpsGestureSample(
          x: .2,
          y: .6,
          timeMs: 1000,
          pressure: .72,
          pressureMin: 0,
          pressureMax: 1,
        ),
        GoosebumpsGestureSample(
          x: .8,
          y: .3,
          timeMs: 1300,
          pressure: .78,
          pressureMin: 0,
          pressureMax: 1,
        ),
      ],
    );

    expect(wave, isNotNull);
    expect(wave!.directionX, greaterThan(.8));
    expect(wave.directionY, lessThan(-.4));
    expect(wave.speed, greaterThan(.7));
    expect(wave.intensity, greaterThan(.65));
    expect(wave.handoffMs, inInclusiveRange(0, wave.travelMs));
  });

  test('geometry provides intensity fallback when pressure is unavailable', () {
    final shortSlow = GoosebumpsMotionEngine.fromGesture(
      id: 'slow',
      samples: const [
        GoosebumpsGestureSample(x: .2, y: .5, timeMs: 1000),
        GoosebumpsGestureSample(x: .32, y: .5, timeMs: 1800),
      ],
    )!;
    final longFast = GoosebumpsMotionEngine.fromGesture(
      id: 'fast',
      samples: const [
        GoosebumpsGestureSample(x: .1, y: .5, timeMs: 1000),
        GoosebumpsGestureSample(x: .9, y: .5, timeMs: 1250),
      ],
    )!;

    expect(longFast.speed, greaterThan(shortSlow.speed));
    expect(longFast.intensity, greaterThan(shortSlow.intensity));
    expect(longFast.travelMs, lessThan(shortSlow.travelMs));
  });

  test('tiny movement is ignored instead of becoming a false wave', () {
    expect(
      GoosebumpsMotionEngine.fromGesture(
        id: 'tiny',
        samples: const [
          GoosebumpsGestureSample(x: .5, y: .5, timeMs: 1000),
          GoosebumpsGestureSample(x: .51, y: .51, timeMs: 1100),
        ],
      ),
      isNull,
    );
  });

  test('deduplicator rejects replay and keeps accepting new ids', () {
    final dedupe = GoosebumpsWaveDeduplicator(capacity: 2);
    expect(dedupe.accept('a'), isTrue);
    expect(dedupe.accept('a'), isFalse);
    expect(dedupe.accept('b'), isTrue);
    expect(dedupe.accept('c'), isTrue);
    expect(dedupe.accept('a'), isTrue);
  });
}
