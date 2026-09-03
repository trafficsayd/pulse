import 'dart:math' as math;

double _unit(num value) => value.toDouble().clamp(0.0, 1.0);

class GoosebumpsGestureSample {
  const GoosebumpsGestureSample({
    required this.x,
    required this.y,
    required this.timeMs,
    this.pressure,
    this.pressureMin,
    this.pressureMax,
  });

  final double x;
  final double y;
  final int timeMs;
  final double? pressure;
  final double? pressureMin;
  final double? pressureMax;
}

/// A physical-feeling wave that first crosses the sender's screen and then
/// continues from the opposite edge of the partner's screen.
class GoosebumpsWave {
  const GoosebumpsWave({
    required this.id,
    required this.createdAtMs,
    required this.startX,
    required this.startY,
    required this.directionX,
    required this.directionY,
    required this.speed,
    required this.intensity,
    required this.travelMs,
    required this.handoffMs,
  });

  static const protocolVersion = 2;

  final String id;
  final int createdAtMs;
  final double startX;
  final double startY;
  final double directionX;
  final double directionY;
  final double speed;
  final double intensity;
  final int travelMs;
  final int handoffMs;

  Map<String, Object> toMap() => {
        'id': id,
        'sentAtMs': createdAtMs,
        'x': startX,
        'y': startY,
        'dx': directionX,
        'dy': directionY,
        'speed': speed,
        'intensity': intensity,
        'travelMs': travelMs,
        'handoffMs': handoffMs,
      };

  static GoosebumpsWave? tryFromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final sentAt = raw['sentAtMs'];
    final x = raw['x'];
    final y = raw['y'];
    final dx = raw['dx'];
    final dy = raw['dy'];
    final speed = raw['speed'];
    final intensity = raw['intensity'];
    final travelMs = raw['travelMs'];
    final handoffMs = raw['handoffMs'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 96 ||
        sentAt is! num ||
        x is! num ||
        y is! num ||
        dx is! num ||
        dy is! num ||
        speed is! num ||
        intensity is! num ||
        travelMs is! num ||
        handoffMs is! num ||
        x < 0 ||
        x > 1 ||
        y < 0 ||
        y > 1 ||
        speed < 0 ||
        speed > 1 ||
        intensity < 0 ||
        intensity > 1 ||
        travelMs < 240 ||
        travelMs > 1800 ||
        handoffMs < 0 ||
        handoffMs > 1800) {
      return null;
    }
    final length = math.sqrt(dx * dx + dy * dy);
    if (!length.isFinite || length < .8 || length > 1.2) return null;
    return GoosebumpsWave(
      id: id,
      createdAtMs: sentAt.toInt(),
      startX: _unit(x),
      startY: _unit(y),
      directionX: dx / length,
      directionY: dy / length,
      speed: _unit(speed),
      intensity: _unit(intensity),
      travelMs: travelMs.toInt(),
      handoffMs: handoffMs.toInt(),
    );
  }
}

class GoosebumpsVisualWave {
  const GoosebumpsVisualWave({
    required this.wave,
    required this.startedAt,
    required this.isLocal,
  });

  final GoosebumpsWave wave;
  final DateTime startedAt;
  final bool isLocal;

  double progress(DateTime now) =>
      (now.difference(startedAt).inMilliseconds / wave.travelMs)
          .clamp(0.0, 1.0);
}
