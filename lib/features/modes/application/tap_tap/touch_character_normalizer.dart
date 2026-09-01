import 'knock_models.dart';

class TouchCharacterSample {
  const TouchCharacterSample({
    required this.durationMs,
    this.contactSize,
    this.pressure,
    this.pressureMin,
    this.pressureMax,
  });

  final int durationMs;
  final double? contactSize;
  final double? pressure;
  final double? pressureMin;
  final double? pressureMax;
}

abstract final class TouchCharacterNormalizer {
  static KnockCharacter normalize(TouchCharacterSample sample) {
    final duration = sample.durationMs.clamp(20, 700).toInt();
    final durationFactor = ((duration - 35) / 365).clamp(0.0, 1.0);
    final size = sample.contactSize?.clamp(0.0, 1.0).toDouble();
    final range = (sample.pressureMax ?? 0) - (sample.pressureMin ?? 0);
    final pressureIsUseful = sample.pressure != null && range >= 0.15;
    final normalizedPressure = pressureIsUseful
        ? ((sample.pressure! - sample.pressureMin!) / range)
            .clamp(0.0, 1.0)
            .toDouble()
        : null;

    final inputs = <(double value, double weight)>[
      (durationFactor, 0.46),
      if (size != null) (size, 0.34),
      if (normalizedPressure != null) (normalizedPressure, 0.20),
    ];
    final totalWeight = inputs.fold<double>(0, (sum, input) => sum + input.$2);
    final weighted = inputs.fold<double>(
      0,
      (sum, input) => sum + input.$1 * input.$2,
    );
    final intensity = totalWeight == 0 ? 0.45 : weighted / totalWeight;
    final sharpness = (1 - durationFactor * 0.62 - (size ?? 0.25) * 0.24)
        .clamp(0.08, 0.95)
        .toDouble();
    final contactClass = switch (size ?? 0.22) {
      >= 0.64 => KnockContactClass.broad,
      >= 0.36 => KnockContactClass.soft,
      _ => KnockContactClass.tip,
    };
    final confidence = pressureIsUseful
        ? 0.92
        : size != null
            ? 0.68
            : 0.46;

    return KnockCharacter(
      intensity: intensity.clamp(0.08, 1.0).toDouble(),
      sharpness: sharpness,
      durationMs: duration,
      contactClass: contactClass,
      confidence: confidence,
    );
  }
}
