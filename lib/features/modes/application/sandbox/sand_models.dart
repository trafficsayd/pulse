enum SandTool { paint, pour, erase }

enum SandMaterial { amethyst, rose, moonlight }

class SandPoint {
  const SandPoint(this.x, this.y);

  final double x;
  final double y;

  List<double> toList() => [x, y];

  static SandPoint? tryFrom(Object? raw) {
    if (raw is! List || raw.length != 2) return null;
    final x = raw[0];
    final y = raw[1];
    if (x is! num || y is! num || x < 0 || x > 1 || y < 0 || y > 1) {
      return null;
    }
    return SandPoint(x.toDouble(), y.toDouble());
  }
}

class SandCommand {
  const SandCommand({
    required this.id,
    required this.createdAtMs,
    required this.tool,
    required this.material,
    required this.points,
    required this.intensity,
    required this.seed,
  });

  static const protocolVersion = 2;
  static const maxPoints = 24;

  final String id;
  final int createdAtMs;
  final SandTool tool;
  final SandMaterial material;
  final List<SandPoint> points;
  final double intensity;
  final int seed;

  int get settleSteps => switch (tool) {
        SandTool.paint => 7,
        SandTool.pour => 18,
        SandTool.erase => 3,
      };

  Map<String, Object> toMap() => {
        'id': id,
        'sentAtMs': createdAtMs,
        'tool': tool.name,
        'material': material.name,
        'points': points.map((point) => point.toList()).toList(growable: false),
        'intensity': intensity,
        'seed': seed,
      };

  static SandCommand? tryFromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final sentAt = raw['sentAtMs'];
    final toolName = raw['tool'];
    final materialName = raw['material'];
    final rawPoints = raw['points'];
    final intensity = raw['intensity'];
    final seed = raw['seed'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 96 ||
        sentAt is! num ||
        toolName is! String ||
        materialName is! String ||
        rawPoints is! List ||
        rawPoints.isEmpty ||
        rawPoints.length > maxPoints ||
        intensity is! num ||
        intensity < 0 ||
        intensity > 1 ||
        seed is! num ||
        seed < 0 ||
        seed > 0x7fffffff) {
      return null;
    }
    SandTool? tool;
    SandMaterial? material;
    for (final value in SandTool.values) {
      if (value.name == toolName) tool = value;
    }
    for (final value in SandMaterial.values) {
      if (value.name == materialName) material = value;
    }
    if (tool == null || material == null) return null;
    final points = <SandPoint>[];
    for (final rawPoint in rawPoints) {
      final point = SandPoint.tryFrom(rawPoint);
      if (point == null) return null;
      points.add(point);
    }
    return SandCommand(
      id: id,
      createdAtMs: sentAt.toInt(),
      tool: tool,
      material: material,
      points: List.unmodifiable(points),
      intensity: intensity.toDouble().clamp(0.0, 1.0),
      seed: seed.toInt(),
    );
  }
}

class SandRemoteTrace {
  const SandRemoteTrace({required this.command, required this.createdAt});
  final SandCommand command;
  final DateTime createdAt;
}
