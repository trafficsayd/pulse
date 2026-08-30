import 'dart:math' as math;

import 'candle_dynamics.dart';
import 'candle_material_profile.dart';
import 'candle_world_state.dart';

/// Deterministic, frame-rate independent candle simulation.
class CandlePhysicsEngine {
  const CandlePhysicsEngine();

  CandleWorldState step(
    CandleWorldState previous,
    CandlePhysicsInput input,
    Duration elapsed,
  ) {
    final dt = (elapsed.inMicroseconds / Duration.microsecondsPerSecond)
        .clamp(0.0, .1)
        .toDouble();
    if (dt == 0) return previous;

    final style = previous.style;
    final character = style.character;
    final material = style.material;
    var phase = previous.wickPhase;

    if (input.extinguish && previous.isLit) {
      phase = CandleWickPhase.smoldering;
    } else if (input.ignite &&
        (phase == CandleWickPhase.cold ||
            phase == CandleWickPhase.smoldering)) {
      phase = CandleWickPhase.igniting;
    }

    final shelteredLocal = _shelter(
      input.localBreath,
      input.localShielded,
      character.shieldEfficiency,
      material.airflowShelter,
    );
    final shelteredPartner = _shelter(
      input.partnerBreath,
      input.partnerShielded,
      character.shieldEfficiency,
      material.airflowShelter,
    );
    final forces = CandleForces.resolve(
      localPressure: shelteredLocal,
      partnerPressure: shelteredPartner,
      style: style,
    );
    final sharedHeatTarget = math.min(
      input.localTouchHeat.clamp(0.0, 1.0),
      input.partnerTouchHeat.clamp(0.0, 1.0),
    );
    final sharedHeat = _follow(
      previous.sharedHeat,
      sharedHeatTarget,
      sharedHeatTarget > previous.sharedHeat ? 3.2 : 1.8,
      dt,
    );
    final sharedStillnessTarget = sharedHeatTarget > .98 &&
            forces.pressure < .09 &&
            input.motionImpulse.abs() < .08
        ? 1.0
        : 0.0;
    final sharedStillness = _follow(
      previous.sharedStillness,
      sharedStillnessTarget,
      sharedStillnessTarget > previous.sharedStillness ? .42 : 2.8,
      dt,
    );
    final tilt = input.tilt.clamp(-1.0, 1.0).toDouble();
    final motion = input.motionImpulse.clamp(-1.0, 1.0).toDouble();
    final targetLean =
        (forces.lean + tilt * .34 + motion * .16).clamp(-1.0, 1.0).toDouble();
    final lean = _follow(previous.lean, targetLean, 7.5, dt);
    final targetTurbulence =
        (forces.turbulence + motion.abs() * .28).clamp(0.0, 1.0).toDouble();
    final turbulence = _follow(
      previous.turbulence,
      targetTurbulence,
      targetTurbulence > previous.turbulence ? 8.5 : 3.1,
      dt,
    );
    final shieldCount =
        (input.localShielded ? 1 : 0) + (input.partnerShielded ? 1 : 0);
    final oxygenTarget = (1 - shieldCount * .08).clamp(.78, 1.0).toDouble();
    final oxygen = _follow(previous.oxygen, oxygenTarget, 2.4, dt);

    var exposure = previous.extinguishExposure;
    final extinguishThreshold =
        (.58 * character.extinguishResistance + material.airflowShelter * .22)
            .clamp(.48, .92);
    final excess = math.max(0.0, forces.pressure - extinguishThreshold);
    if (phase == CandleWickPhase.burning && excess > 0) {
      exposure += excess * dt * (1.72 / material.thermalInertia);
    } else {
      exposure = math.max(0, exposure - dt * .72 * material.thermalInertia);
    }
    if (phase == CandleWickPhase.burning && exposure >= .54) {
      phase = CandleWickPhase.smoldering;
    }

    var wickTarget = 0.0;
    var energyTarget = 0.0;
    var smokeTarget = 0.0;
    var emberTarget = 0.0;
    switch (phase) {
      case CandleWickPhase.cold:
        break;
      case CandleWickPhase.igniting:
        wickTarget = 1;
        energyTarget = .68 + sharedHeat * .16;
        if (previous.wickTemperature >= .72) {
          phase = CandleWickPhase.burning;
          energyTarget = 1;
        }
      case CandleWickPhase.burning:
        wickTarget = 1;
        energyTarget = (1 -
                forces.pressure * .19 -
                turbulence * .10 +
                sharedHeat * .09 +
                sharedStillness * .08)
            .clamp(.42, 1.12)
            .toDouble();
      case CandleWickPhase.smoldering:
        emberTarget = 1;
        smokeTarget = (.52 + exposure * .42) * material.sootRate;
        if (previous.wickTemperature <= .16 && previous.ember <= .12) {
          phase = CandleWickPhase.cold;
          exposure = 0;
        }
      case CandleWickPhase.spent:
        break;
    }

    final heatRate = 3.6 / material.thermalInertia;
    final coolRate = 1.15 / material.emberPersistence;
    final wickTemperature = _follow(
      previous.wickTemperature,
      wickTarget,
      wickTarget > previous.wickTemperature ? heatRate : coolRate,
      dt,
    );
    final flameEnergy = _follow(
      previous.flameEnergy,
      energyTarget,
      energyTarget > previous.flameEnergy ? 6.4 : 9.2,
      dt,
    );
    final coreTemperature = _follow(
      previous.coreTemperature,
      flameEnergy * oxygen,
      5.4 / material.thermalInertia,
      dt,
    );
    final shellTemperature = _follow(
      previous.shellTemperature,
      coreTemperature * (.68 + turbulence * .08),
      3.8 / material.thermalInertia,
      dt,
    );
    final flameHeight = _follow(
      previous.flameHeight,
      flameEnergy * forces.heightScale * material.baseFlameHeight,
      7.0,
      dt,
    );
    final moltenTarget = previous.isLit
        ? (.18 + wickTemperature * .72).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final moltenWax = _follow(
      previous.moltenWax,
      moltenTarget,
      moltenTarget > previous.moltenWax
          ? .18 / material.thermalInertia
          : .045 * material.thermalInertia,
      dt,
    );
    final waxTarget =
        (tilt * moltenWax / material.moltenViscosity).clamp(-1.0, 1.0);
    final waxSurfaceOffset = _follow(
      previous.waxSurfaceOffset,
      waxTarget,
      1.9 / material.moltenViscosity,
      dt,
    );
    final ember = _follow(
      previous.ember,
      emberTarget,
      emberTarget > previous.ember ? 8 : .8 / material.emberPersistence,
      dt,
    );
    final smokeDensity = _follow(
      previous.smokeDensity,
      smokeTarget,
      smokeTarget > previous.smokeDensity ? 5.5 : 1.35,
      dt,
    );

    return previous.copyWith(
      wickPhase: phase,
      simulationSeconds: previous.simulationSeconds + dt,
      flameEnergy: flameEnergy.clamp(0.0, 1.2),
      wickTemperature: wickTemperature.clamp(0.0, 1.0),
      coreTemperature: coreTemperature.clamp(0.0, 1.1),
      shellTemperature: shellTemperature.clamp(0.0, 1.0),
      flameHeight: flameHeight.clamp(0.0, 1.1),
      lean: lean,
      turbulence: turbulence,
      oxygen: oxygen,
      moltenWax: moltenWax,
      waxSurfaceOffset: waxSurfaceOffset,
      smokeDensity: smokeDensity.clamp(0.0, 1.0),
      ember: ember.clamp(0.0, 1.0),
      sharedHeat: sharedHeat.clamp(0.0, 1.0),
      sharedStillness: sharedStillness.clamp(0.0, 1.0),
      extinguishExposure: exposure.clamp(0.0, 1.0),
    );
  }

  static double _shelter(
    double pressure,
    bool shielded,
    double shieldEfficiency,
    double vesselShelter,
  ) {
    final vessel = 1 - vesselShelter.clamp(0.0, .92);
    final palm = shielded ? 1 - shieldEfficiency.clamp(0.0, .96) : 1.0;
    return (pressure.clamp(0.0, 1.0) * vessel * palm)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  static double _follow(
    double current,
    double target,
    double response,
    double dt,
  ) {
    final blend = 1 - math.exp(-math.max(.001, response) * dt);
    return current + (target - current) * blend;
  }
}
