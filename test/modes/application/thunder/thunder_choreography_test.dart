import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/thunder/thunder_choreography.dart';
import 'package:pulse/features/modes/application/thunder/thunder_models.dart';

void main() {
  test('gesture controls direction velocity and pressure intensity', () {
    final strike = ThunderChoreography.fromGesture(
      id: 'strike',
      seed: 42,
      samples: const [
        ThunderGestureSample(
          x: .2,
          y: .7,
          timeMs: 1000,
          pressure: .8,
          pressureMin: 0,
          pressureMax: 1,
        ),
        ThunderGestureSample(
          x: .82,
          y: .24,
          timeMs: 1280,
          pressure: .84,
          pressureMin: 0,
          pressureMax: 1,
        ),
      ],
    );

    expect(strike, isNotNull);
    expect(strike!.directionX, greaterThan(.75));
    expect(strike.directionY, lessThan(-.5));
    expect(strike.velocity, greaterThan(.75));
    expect(strike.intensity, greaterThan(.72));
  });

  test('geometry is deterministic for the transmitted seed', () {
    const strike = ThunderStrike(
      id: 'same',
      createdAtMs: 1,
      originX: .3,
      originY: .6,
      directionX: .8,
      directionY: .6,
      intensity: .8,
      velocity: .7,
      seed: 717,
      handoffMs: 400,
    );
    final first = ThunderChoreography.geometry(strike, remote: true);
    final second = ThunderChoreography.geometry(strike, remote: true);

    expect(first.trunk.length, second.trunk.length);
    for (var i = 0; i < first.trunk.length; i++) {
      expect(first.trunk[i].x, second.trunk[i].x);
      expect(first.trunk[i].y, second.trunk[i].y);
    }
    expect(first.branches.length, second.branches.length);
  });

  test('reduced motion uses one subdued flash and shorter rumble', () {
    const strike = ThunderStrike(
      id: 'strong',
      createdAtMs: 1,
      originX: .5,
      originY: .5,
      directionX: 0,
      directionY: 1,
      intensity: 1,
      velocity: 1,
      seed: 1,
      handoffMs: 300,
    );
    final normal = ThunderChoreography.cues(strike, reduceMotion: false);
    final reduced = ThunderChoreography.cues(strike, reduceMotion: true);

    expect(normal.flashCount, 2);
    expect(reduced.flashCount, 1);
    expect(reduced.rumbleDurationMs, lessThan(normal.rumbleDurationMs));
    expect(reduced.flashOnMs, lessThanOrEqualTo(normal.flashOnMs));
  });

  test('tiny gesture is ignored and duplicate ids are rejected', () {
    expect(
      ThunderChoreography.fromGesture(
        id: 'tiny',
        seed: 1,
        samples: const [
          ThunderGestureSample(x: .5, y: .5, timeMs: 1),
          ThunderGestureSample(x: .51, y: .51, timeMs: 100),
        ],
      ),
      isNull,
    );
    final dedupe = ThunderStrikeDeduplicator();
    expect(dedupe.accept('id'), isTrue);
    expect(dedupe.accept('id'), isFalse);
  });
}
