import 'dart:math' as math;

import 'thunder_models.dart';

class ThunderCueSheet {
  const ThunderCueSheet({
    required this.flashDelayMs,
    required this.impactDelayMs,
    required this.rumbleDelayMs,
    required this.rumbleDurationMs,
    required this.flashOnMs,
    required this.flashGapMs,
    required this.flashCount,
    required this.hapticAmplitude,
  });

  final int flashDelayMs;
  final int impactDelayMs;
  final int rumbleDelayMs;
  final int rumbleDurationMs;
  final int flashOnMs;
  final int flashGapMs;
  final int flashCount;
  final int hapticAmplitude;

  int get totalDurationMs => rumbleDelayMs + rumbleDurationMs;
}

abstract final class ThunderChoreography {
  static ThunderStrike? fromGesture({
    required String id,
    required int seed,
    required List<ThunderGestureSample> samples,
  }) {
    if (samples.length < 2) return null;
    final first = samples.first;
    final last = samples.last;
    final rawDx = last.x - first.x;
    final rawDy = last.y - first.y;
    final distance = math.sqrt(rawDx * rawDx + rawDy * rawDy);
    if (!distance.isFinite || distance < .045) return null;
    final durationMs = math.max(24, last.timeMs - first.timeMs);
    final unitsPerSecond = distance * 1000 / durationMs;
    final velocity = ((unitsPerSecond - .12) / 1.8).clamp(0.0, 1.0);
    final pressure = _pressure(samples);
    final fallbackForce =
        (.5 * (distance / .68).clamp(0.0, 1.0) + .5 * velocity).clamp(0.0, 1.0);
    final intensity = pressure == null
        ? (.24 + fallbackForce * .7).clamp(0.0, 1.0)
        : (.2 + pressure * .64 + fallbackForce * .16).clamp(0.0, 1.0);
    final directionX = rawDx / distance;
    final directionY = rawDy / distance;
    final crossing = (760 - velocity * 420).round();
    return ThunderStrike(
      id: id,
      createdAtMs: last.timeMs,
      originX: first.x.clamp(0.0, 1.0),
      originY: first.y.clamp(0.0, 1.0),
      directionX: directionX,
      directionY: directionY,
      intensity: intensity,
      velocity: velocity,
      seed: seed & 0x7fffffff,
      handoffMs: crossing.clamp(300, 760),
    );
  }

  static ThunderCueSheet cues(ThunderStrike strike,
      {required bool reduceMotion}) {
    final intensity = strike.intensity;
    return ThunderCueSheet(
      flashDelayMs: reduceMotion ? 40 : 24,
      impactDelayMs: (108 - strike.velocity * 42).round(),
      rumbleDelayMs: (160 - strike.velocity * 48).round(),
      rumbleDurationMs: reduceMotion ? 640 : (1250 + intensity * 1250).round(),
      flashOnMs: reduceMotion ? 36 : (42 + intensity * 34).round(),
      flashGapMs: 72,
      flashCount: reduceMotion ? 1 : (intensity > .78 ? 2 : 1),
      hapticAmplitude: (80 + intensity * 165).round().clamp(1, 255),
    );
  }

  static ThunderGeometry geometry(ThunderStrike strike,
      {required bool remote}) {
    final random = math.Random(strike.seed);
    final directionX = strike.directionX;
    final directionY = strike.directionY.abs() < .12
        ? (strike.directionY.isNegative ? -.12 : .12)
        : strike.directionY;
    final startX = remote
        ? (directionX >= 0 ? -.04 : 1.04)
        : strike.originX.clamp(0.0, 1.0);
    final startY =
        remote ? (directionY >= 0 ? .08 : .92) : strike.originY.clamp(0.0, 1.0);
    final steps = 10 + (strike.intensity * 8).round();
    final trunk = <ThunderPoint>[ThunderPoint(startX, startY)];
    var x = startX;
    var y = startY;
    final stepLength = 1.34 / steps;
    for (var index = 0; index < steps; index++) {
      final jitter =
          (.028 + strike.intensity * .035) * (random.nextDouble() * 2 - 1);
      x += directionX * stepLength - directionY * jitter;
      y += directionY * stepLength + directionX * jitter;
      trunk.add(ThunderPoint(x, y));
    }
    final branches = <ThunderBranch>[];
    final branchCount = 2 + (strike.intensity * 4).round();
    for (var branch = 0; branch < branchCount; branch++) {
      final rootIndex = 2 + random.nextInt(math.max(1, trunk.length - 4));
      final root = trunk[rootIndex];
      final side = random.nextBool() ? 1.0 : -1.0;
      final points = <ThunderPoint>[root];
      var bx = root.x;
      var by = root.y;
      final length = 2 + random.nextInt(3);
      for (var segment = 0; segment < length; segment++) {
        bx += directionX * .045 - directionY * side * (.045 + segment * .009);
        by += directionY * .045 + directionX * side * (.045 + segment * .009);
        points.add(ThunderPoint(bx, by));
      }
      branches.add(ThunderBranch(
        points,
        opacity: .34 + random.nextDouble() * .32,
      ));
    }
    return ThunderGeometry(trunk: trunk, branches: branches);
  }

  static double? _pressure(List<ThunderGestureSample> samples) {
    var sum = 0.0;
    var count = 0;
    for (final sample in samples) {
      final pressure = sample.pressure;
      final min = sample.pressureMin;
      final max = sample.pressureMax;
      if (pressure == null || min == null || max == null || max - min < .05) {
        continue;
      }
      sum += ((pressure - min) / (max - min)).clamp(0.0, 1.0);
      count++;
    }
    return count == 0 ? null : sum / count;
  }
}

class ThunderStrikeDeduplicator {
  ThunderStrikeDeduplicator({this.capacity = 64});

  final int capacity;
  final Set<String> _ids = <String>{};
  final List<String> _order = <String>[];

  bool accept(String id) {
    if (!_ids.add(id)) return false;
    _order.add(id);
    while (_order.length > capacity) {
      _ids.remove(_order.removeAt(0));
    }
    return true;
  }
}
