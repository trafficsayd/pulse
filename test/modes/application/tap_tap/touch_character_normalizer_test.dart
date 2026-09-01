import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/tap_tap/knock_models.dart';
import 'package:pulse/features/modes/application/tap_tap/touch_character_normalizer.dart';

void main() {
  test('normalizes a quick fingertip tap without pressure', () {
    final result = TouchCharacterNormalizer.normalize(
      const TouchCharacterSample(durationMs: 55, contactSize: 0.18),
    );

    expect(result.depth, KnockDepth.soft);
    expect(result.contactClass, KnockContactClass.tip);
    expect(result.confidence, closeTo(0.68, 0.001));
    expect(result.sharpness, greaterThan(0.7));
  });

  test('uses useful pressure range and reports high confidence', () {
    final result = TouchCharacterNormalizer.normalize(
      const TouchCharacterSample(
        durationMs: 260,
        contactSize: 0.72,
        pressure: 0.9,
        pressureMin: 0.1,
        pressureMax: 1.0,
      ),
    );

    expect(result.depth, KnockDepth.deep);
    expect(result.contactClass, KnockContactClass.broad);
    expect(result.confidence, closeTo(0.92, 0.001));
  });

  test('ignores a pressure axis with no useful dynamic range', () {
    final result = TouchCharacterNormalizer.normalize(
      const TouchCharacterSample(
        durationMs: 90,
        contactSize: 0.4,
        pressure: 1,
        pressureMin: 0.98,
        pressureMax: 1,
      ),
    );

    expect(result.confidence, closeTo(0.68, 0.001));
    expect(result.contactClass, KnockContactClass.soft);
  });

  test('clamps pathological duration', () {
    final result = TouchCharacterNormalizer.normalize(
      const TouchCharacterSample(durationMs: 5000),
    );
    expect(result.durationMs, 700);
    expect(result.intensity, inInclusiveRange(0, 1));
  });
}
