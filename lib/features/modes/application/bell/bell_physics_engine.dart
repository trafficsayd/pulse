import 'dart:math' as math;

import 'bell_models.dart';

typedef BellIdFactory = String Function();

/// Fixed-equation bell simulation. Supplying the same state, inputs and time
/// steps always produces the same output, so local and remote presentations
/// can replay a strike without transferring animation frames.
class BellPhysicsEngine {
  BellPhysicsEngine({
    BellMaterial material = BellMaterial.brass,
    BellIdFactory? idFactory,
  })  : _material = material,
        _idFactory = idFactory ?? _sequentialId;

  static var _nextId = 0;
  static String _sequentialId() => 'bell-${_nextId++}';

  BellMaterial _material;
  final BellIdFactory _idFactory;
  BellPhysicsState _state = const BellPhysicsState();
  double _contactCooldown = 0;

  BellMaterial get material => _material;
  BellMaterialProfile get profile => BellMaterialProfile.forMaterial(_material);
  BellPhysicsState get state => _state;

  void setMaterial(BellMaterial value) {
    _material = value;
    _state = const BellPhysicsState();
    _contactCooldown = 0;
  }

  void applyImpulse(double impulse) {
    final safe = impulse.clamp(-5.5, 5.5).toDouble();
    _state = _state.copyWith(
      angularVelocity: _state.angularVelocity + safe / profile.inertia,
      clapperVelocity: _state.clapperVelocity - safe * 1.72,
    );
  }

  BellStepResult step(
    BellMotionInput input,
    double deltaSeconds, {
    required int nowMs,
  }) {
    final dt = deltaSeconds.clamp(1 / 240, 1 / 24).toDouble();
    if (input.gestureImpulse != 0) applyImpulse(input.gestureImpulse);
    final p = profile;

    var angle = _state.angle;
    var velocity = _state.angularVelocity;
    final drive = input.tangentialAcceleration.clamp(-3.0, 3.0) * 4.1;
    final torque = drive - 7.1 * math.sin(angle) - p.bodyDamping * velocity;
    velocity += torque / p.inertia * dt;
    angle += velocity * dt;
    if (angle.abs() > .66) {
      angle = angle.sign * .66;
      velocity *= -.28;
    }

    var clapper = _state.clapperAngle;
    var clapperVelocity = _state.clapperVelocity;
    final relativeDrive = -torque * .43 - velocity * .82;
    final clapperTorque = relativeDrive -
        13.4 * math.sin(clapper) -
        p.clapperDamping * clapperVelocity;
    clapperVelocity += clapperTorque * dt;
    clapper += clapperVelocity * dt;

    _contactCooldown = math.max(0, _contactCooldown - dt);
    BellStrike? strike;
    final exceeded = clapper.abs() >= p.clapperLimit;
    if (exceeded) {
      final impactSpeed = clapperVelocity.abs();
      final direction = clapper.sign;
      clapper = direction * p.clapperLimit;
      clapperVelocity *= -.31;
      if (_contactCooldown <= 0 && impactSpeed >= 1.18) {
        final strength = ((impactSpeed - .65) / 5.4).clamp(.08, 1.0);
        strike = BellStrike(
          id: _idFactory(),
          occurredAtMs: nowMs,
          material: _material,
          strength: strength.toDouble(),
          direction: direction,
          pitch: p.pitch,
          resonanceSeconds: p.resonanceSeconds,
        );
        _contactCooldown = .115;
      }
    }

    final resonanceDecay = math.exp(-dt * (3.6 / p.resonanceSeconds));
    final resonance = strike == null
        ? _state.resonance * resonanceDecay
        : math.max(_state.resonance, .34 + strike.strength * .66);
    _state = BellPhysicsState(
      angle: angle,
      angularVelocity: velocity,
      clapperAngle: clapper,
      clapperVelocity: clapperVelocity,
      resonance: resonance.clamp(0.0, 1.0).toDouble(),
    );
    return BellStepResult(_state, strike: strike);
  }

  /// Replays a partner strike as an impulse, while preserving local material
  /// physics. The partner's material is still retained by the strike itself
  /// for rendering and audio timbre.
  void applyRemoteStrike(BellStrike strike) {
    final direction = strike.direction == 0 ? 1.0 : strike.direction.sign;
    applyImpulse(direction * (1.25 + strike.strength * 3.45));
    _state = _state.copyWith(
      resonance: math.max(_state.resonance, strike.strength),
    );
  }
}
