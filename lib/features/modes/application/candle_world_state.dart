import 'candle_dynamics.dart';

enum CandleWickPhase { cold, igniting, burning, smoldering, spent }

/// Inputs collected during one fixed physics step.
///
/// All fields are derived, privacy-safe forces. Raw audio, motion samples and
/// pointer coordinates never enter the shared state or the network protocol.
class CandlePhysicsInput {
  const CandlePhysicsInput({
    this.localBreath = 0,
    this.partnerBreath = 0,
    this.tilt = 0,
    this.motionImpulse = 0,
    this.localShielded = false,
    this.partnerShielded = false,
    this.localTouchHeat = 0,
    this.partnerTouchHeat = 0,
    this.ignite = false,
    this.extinguish = false,
  });

  final double localBreath;
  final double partnerBreath;
  final double tilt;
  final double motionImpulse;
  final bool localShielded;
  final bool partnerShielded;
  final double localTouchHeat;
  final double partnerTouchHeat;
  final bool ignite;
  final bool extinguish;
}

/// One authoritative physical snapshot of the shared candle.
///
/// Rendering, sound and haptics consume this value. They never maintain their
/// own competing flame simulations, which keeps every sensory layer aligned.
class CandleWorldState {
  const CandleWorldState({
    required this.style,
    required this.wickPhase,
    required this.simulationSeconds,
    required this.flameEnergy,
    required this.wickTemperature,
    required this.coreTemperature,
    required this.shellTemperature,
    required this.flameHeight,
    required this.lean,
    required this.turbulence,
    required this.oxygen,
    required this.moltenWax,
    required this.waxSurfaceOffset,
    required this.smokeDensity,
    required this.ember,
    required this.sharedHeat,
    required this.sharedStillness,
    required this.extinguishExposure,
  });

  factory CandleWorldState.resting({
    CandleStyle style = CandleStyle.classic,
    bool lit = false,
  }) =>
      CandleWorldState(
        style: style,
        wickPhase: lit ? CandleWickPhase.burning : CandleWickPhase.cold,
        simulationSeconds: 0,
        flameEnergy: lit ? 1 : 0,
        wickTemperature: lit ? .92 : 0,
        coreTemperature: lit ? 1 : 0,
        shellTemperature: lit ? .72 : 0,
        flameHeight: lit ? 1 : 0,
        lean: 0,
        turbulence: lit ? .08 : 0,
        oxygen: 1,
        moltenWax: lit ? .12 : 0,
        waxSurfaceOffset: 0,
        smokeDensity: 0,
        ember: 0,
        sharedHeat: 0,
        sharedStillness: 0,
        extinguishExposure: 0,
      );

  final CandleStyle style;
  final CandleWickPhase wickPhase;
  final double simulationSeconds;
  final double flameEnergy;
  final double wickTemperature;
  final double coreTemperature;
  final double shellTemperature;
  final double flameHeight;
  final double lean;
  final double turbulence;
  final double oxygen;
  final double moltenWax;
  final double waxSurfaceOffset;
  final double smokeDensity;
  final double ember;
  final double sharedHeat;
  final double sharedStillness;
  final double extinguishExposure;

  bool get isLit =>
      wickPhase == CandleWickPhase.igniting ||
      wickPhase == CandleWickPhase.burning;

  bool get isAlive => isLit || wickPhase == CandleWickPhase.smoldering;

  CandleWorldState copyWith({
    CandleStyle? style,
    CandleWickPhase? wickPhase,
    double? simulationSeconds,
    double? flameEnergy,
    double? wickTemperature,
    double? coreTemperature,
    double? shellTemperature,
    double? flameHeight,
    double? lean,
    double? turbulence,
    double? oxygen,
    double? moltenWax,
    double? waxSurfaceOffset,
    double? smokeDensity,
    double? ember,
    double? sharedHeat,
    double? sharedStillness,
    double? extinguishExposure,
  }) =>
      CandleWorldState(
        style: style ?? this.style,
        wickPhase: wickPhase ?? this.wickPhase,
        simulationSeconds: simulationSeconds ?? this.simulationSeconds,
        flameEnergy: flameEnergy ?? this.flameEnergy,
        wickTemperature: wickTemperature ?? this.wickTemperature,
        coreTemperature: coreTemperature ?? this.coreTemperature,
        shellTemperature: shellTemperature ?? this.shellTemperature,
        flameHeight: flameHeight ?? this.flameHeight,
        lean: lean ?? this.lean,
        turbulence: turbulence ?? this.turbulence,
        oxygen: oxygen ?? this.oxygen,
        moltenWax: moltenWax ?? this.moltenWax,
        waxSurfaceOffset: waxSurfaceOffset ?? this.waxSurfaceOffset,
        smokeDensity: smokeDensity ?? this.smokeDensity,
        ember: ember ?? this.ember,
        sharedHeat: sharedHeat ?? this.sharedHeat,
        sharedStillness: sharedStillness ?? this.sharedStillness,
        extinguishExposure: extinguishExposure ?? this.extinguishExposure,
      );
}
