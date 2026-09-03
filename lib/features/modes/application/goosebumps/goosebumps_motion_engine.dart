import 'dart:math' as math;

import 'goosebumps_wave.dart';

abstract final class GoosebumpsMotionEngine {
  static GoosebumpsWave? fromGesture({
    required String id,
    required List<GoosebumpsGestureSample> samples,
  }) {
    if (samples.length < 2) return null;
    final first = samples.first;
    final last = samples.last;
    final rawDx = last.x - first.x;
    final rawDy = last.y - first.y;
    final distance = math.sqrt(rawDx * rawDx + rawDy * rawDy);
    if (!distance.isFinite || distance < .035) return null;

    final durationMs = math.max(24, last.timeMs - first.timeMs);
    final unitsPerSecond = distance * 1000 / durationMs;
    final speed = ((unitsPerSecond - .12) / 1.65).clamp(0.0, 1.0);
    final dx = rawDx / distance;
    final dy = rawDy / distance;
    final pressure = _normalizedPressure(samples);
    final geometricForce =
        (.58 * (distance / .72).clamp(0.0, 1.0) + .42 * speed).clamp(0.0, 1.0);
    final intensity = pressure == null
        ? (.22 + geometricForce * .72).clamp(0.0, 1.0)
        : (.18 + pressure * .68 + geometricForce * .14).clamp(0.0, 1.0);
    final travelMs = (1120 - speed * 710).round().clamp(360, 1120);
    final distanceToExit = _distanceToBoundary(first.x, first.y, dx, dy);
    final handoffMs = (travelMs * distanceToExit.clamp(.28, 1.0)).round();

    return GoosebumpsWave(
      id: id,
      createdAtMs: last.timeMs,
      startX: first.x.clamp(0.0, 1.0),
      startY: first.y.clamp(0.0, 1.0),
      directionX: dx,
      directionY: dy,
      speed: speed,
      intensity: intensity,
      travelMs: travelMs,
      handoffMs: handoffMs,
    );
  }

  static double? _normalizedPressure(List<GoosebumpsGestureSample> samples) {
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

  static double _distanceToBoundary(double x, double y, double dx, double dy) {
    final distances = <double>[];
    if (dx > .0001) distances.add((1 - x) / dx);
    if (dx < -.0001) distances.add(-x / dx);
    if (dy > .0001) distances.add((1 - y) / dy);
    if (dy < -.0001) distances.add(-y / dy);
    return distances.where((value) => value >= 0).fold<double>(
          double.infinity,
          math.min,
        );
  }
}

class GoosebumpsWaveDeduplicator {
  GoosebumpsWaveDeduplicator({this.capacity = 96});

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
