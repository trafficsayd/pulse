import 'dart:math' as math;

double _unit(num value) => value.toDouble().clamp(0.0, 1.0);

class ThunderGestureSample {
  const ThunderGestureSample({
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

class ThunderStrike {
  const ThunderStrike({
    required this.id,
    required this.createdAtMs,
    required this.originX,
    required this.originY,
    required this.directionX,
    required this.directionY,
    required this.intensity,
    required this.velocity,
    required this.seed,
    required this.handoffMs,
  });

  static const protocolVersion = 2;

  final String id;
  final int createdAtMs;
  final double originX;
  final double originY;
  final double directionX;
  final double directionY;
  final double intensity;
  final double velocity;
  final int seed;
  final int handoffMs;

  Map<String, Object> toMap() => {
        'id': id,
        'sentAtMs': createdAtMs,
        'x': originX,
        'y': originY,
        'dx': directionX,
        'dy': directionY,
        'intensity': intensity,
        'velocity': velocity,
        'seed': seed,
        'handoffMs': handoffMs,
      };

  static ThunderStrike? tryFromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final sentAt = raw['sentAtMs'];
    final x = raw['x'];
    final y = raw['y'];
    final dx = raw['dx'];
    final dy = raw['dy'];
    final intensity = raw['intensity'];
    final velocity = raw['velocity'];
    final seed = raw['seed'];
    final handoff = raw['handoffMs'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 96 ||
        sentAt is! num ||
        x is! num ||
        y is! num ||
        dx is! num ||
        dy is! num ||
        intensity is! num ||
        velocity is! num ||
        seed is! num ||
        handoff is! num ||
        x < 0 ||
        x > 1 ||
        y < 0 ||
        y > 1 ||
        intensity < 0 ||
        intensity > 1 ||
        velocity < 0 ||
        velocity > 1 ||
        seed < 0 ||
        seed > 0x7fffffff ||
        handoff < 0 ||
        handoff > 2000) {
      return null;
    }
    final length = math.sqrt(dx * dx + dy * dy);
    if (!length.isFinite || length < .8 || length > 1.2) return null;
    return ThunderStrike(
      id: id,
      createdAtMs: sentAt.toInt(),
      originX: _unit(x),
      originY: _unit(y),
      directionX: dx / length,
      directionY: dy / length,
      intensity: _unit(intensity),
      velocity: _unit(velocity),
      seed: seed.toInt(),
      handoffMs: handoff.toInt(),
    );
  }
}

class ThunderPoint {
  const ThunderPoint(this.x, this.y);
  final double x;
  final double y;
}

class ThunderBranch {
  const ThunderBranch(this.points, {required this.opacity});
  final List<ThunderPoint> points;
  final double opacity;
}

class ThunderGeometry {
  const ThunderGeometry({required this.trunk, required this.branches});
  final List<ThunderPoint> trunk;
  final List<ThunderBranch> branches;
}

class ThunderVisualStrike {
  const ThunderVisualStrike({
    required this.strike,
    required this.geometry,
    required this.startedAt,
    required this.isLocal,
  });

  final ThunderStrike strike;
  final ThunderGeometry geometry;
  final DateTime startedAt;
  final bool isLocal;
}
