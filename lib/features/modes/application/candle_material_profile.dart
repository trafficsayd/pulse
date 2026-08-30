import 'candle_dynamics.dart';

/// Slow-changing physical properties of the three candle bodies.
///
/// [CandleCharacter] describes the flame's personality. This profile describes
/// the material that surrounds it: wax, glass, heat storage and residue.
class CandleMaterialProfile {
  const CandleMaterialProfile({
    required this.airflowShelter,
    required this.thermalInertia,
    required this.moltenViscosity,
    required this.waxFlowRate,
    required this.subsurfaceScattering,
    required this.glassRefraction,
    required this.sootRate,
    required this.emberPersistence,
    required this.baseFlameHeight,
  });

  /// Fraction of exposed airflow absorbed by the vessel and rim.
  final double airflowShelter;

  /// Resistance to fast temperature changes. Higher values feel calmer.
  final double thermalInertia;

  /// Resistance of the molten pool to motion caused by device tilt.
  final double moltenViscosity;

  /// Relative speed at which hot wax can create a new runnel.
  final double waxFlowRate;

  /// Amount of warm light transported through the wax body.
  final double subsurfaceScattering;

  /// Strength of refractive highlights around a glass vessel.
  final double glassRefraction;

  /// Relative amount of soot left by an unstable flame.
  final double sootRate;

  /// Duration of visible glow after the flame goes out.
  final double emberPersistence;

  /// Neutral flame-height multiplier for this material.
  final double baseFlameHeight;
}

extension CandleStyleMaterialProfile on CandleStyle {
  CandleMaterialProfile get material => switch (this) {
        CandleStyle.classic => const CandleMaterialProfile(
            airflowShelter: .02,
            thermalInertia: .72,
            moltenViscosity: .56,
            waxFlowRate: 1,
            subsurfaceScattering: .88,
            glassRefraction: 0,
            sootRate: .82,
            emberPersistence: .86,
            baseFlameHeight: 1,
          ),
        CandleStyle.glass => const CandleMaterialProfile(
            airflowShelter: .26,
            thermalInertia: 1.18,
            moltenViscosity: .78,
            waxFlowRate: .28,
            subsurfaceScattering: .66,
            glassRefraction: 1,
            sootRate: .34,
            emberPersistence: .72,
            baseFlameHeight: .94,
          ),
        CandleStyle.violet => const CandleMaterialProfile(
            airflowShelter: .12,
            thermalInertia: 1.36,
            moltenViscosity: .92,
            waxFlowRate: .46,
            subsurfaceScattering: 1,
            glassRefraction: .08,
            sootRate: .46,
            emberPersistence: 1.12,
            baseFlameHeight: 1.03,
          ),
      };
}
