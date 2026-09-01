import 'dart:math' as math;

enum BellMaterial { brass, crystal, porcelain }

class BellMaterialProfile {
  const BellMaterialProfile({
    required this.material,
    required this.inertia,
    required this.bodyDamping,
    required this.clapperDamping,
    required this.clapperLimit,
    required this.pitch,
    required this.resonanceSeconds,
    required this.hapticHardness,
  });

  final BellMaterial material;
  final double inertia;
  final double bodyDamping;
  final double clapperDamping;
  final double clapperLimit;
  final double pitch;
  final double resonanceSeconds;
  final double hapticHardness;

  static BellMaterialProfile forMaterial(BellMaterial material) =>
      switch (material) {
        BellMaterial.brass => const BellMaterialProfile(
            material: BellMaterial.brass,
            inertia: 1.18,
            bodyDamping: 1.48,
            clapperDamping: 1.72,
            clapperLimit: .31,
            pitch: .48,
            resonanceSeconds: 2.8,
            hapticHardness: .76,
          ),
        BellMaterial.crystal => const BellMaterialProfile(
            material: BellMaterial.crystal,
            inertia: .84,
            bodyDamping: 1.15,
            clapperDamping: 1.2,
            clapperLimit: .27,
            pitch: .82,
            resonanceSeconds: 3.5,
            hapticHardness: .54,
          ),
        BellMaterial.porcelain => const BellMaterialProfile(
            material: BellMaterial.porcelain,
            inertia: .96,
            bodyDamping: 1.82,
            clapperDamping: 2.05,
            clapperLimit: .285,
            pitch: .68,
            resonanceSeconds: 1.9,
            hapticHardness: .63,
          ),
      };
}

class BellMotionInput {
  const BellMotionInput({
    this.tangentialAcceleration = 0,
    this.gestureImpulse = 0,
  });

  final double tangentialAcceleration;
  final double gestureImpulse;
}

class BellPhysicsState {
  const BellPhysicsState({
    this.angle = 0,
    this.angularVelocity = 0,
    this.clapperAngle = 0,
    this.clapperVelocity = 0,
    this.resonance = 0,
  });

  final double angle;
  final double angularVelocity;
  final double clapperAngle;
  final double clapperVelocity;
  final double resonance;

  BellPhysicsState copyWith({
    double? angle,
    double? angularVelocity,
    double? clapperAngle,
    double? clapperVelocity,
    double? resonance,
  }) {
    return BellPhysicsState(
      angle: angle ?? this.angle,
      angularVelocity: angularVelocity ?? this.angularVelocity,
      clapperAngle: clapperAngle ?? this.clapperAngle,
      clapperVelocity: clapperVelocity ?? this.clapperVelocity,
      resonance: resonance ?? this.resonance,
    );
  }

  bool approximatelyEquals(BellPhysicsState other, {double epsilon = 1e-9}) {
    return (angle - other.angle).abs() <= epsilon &&
        (angularVelocity - other.angularVelocity).abs() <= epsilon &&
        (clapperAngle - other.clapperAngle).abs() <= epsilon &&
        (clapperVelocity - other.clapperVelocity).abs() <= epsilon &&
        (resonance - other.resonance).abs() <= epsilon;
  }
}

class BellStrike {
  const BellStrike({
    required this.id,
    required this.occurredAtMs,
    required this.material,
    required this.strength,
    required this.direction,
    required this.pitch,
    required this.resonanceSeconds,
    this.remote = false,
  });

  final String id;
  final int occurredAtMs;
  final BellMaterial material;
  final double strength;
  final double direction;
  final double pitch;
  final double resonanceSeconds;
  final bool remote;

  BellStrike normalized() => BellStrike(
        id: id,
        occurredAtMs: occurredAtMs,
        material: material,
        strength: strength.clamp(0.0, 1.0).toDouble(),
        direction: direction.clamp(-1.0, 1.0).toDouble(),
        pitch: pitch.clamp(0.0, 1.0).toDouble(),
        resonanceSeconds: math.max(.1, resonanceSeconds),
        remote: remote,
      );
}

class BellStepResult {
  const BellStepResult(this.state, {this.strike});

  final BellPhysicsState state;
  final BellStrike? strike;
}
