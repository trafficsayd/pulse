import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/candle_quality_controller.dart';

void main() {
  test('one slow frame never lowers quality', () {
    final controller = CandleQualityController();
    controller.record(const Duration(milliseconds: 80));
    for (var i = 0; i < 8; i++) {
      controller.record(const Duration(milliseconds: 16));
    }
    expect(controller.profile, CandleQualityProfile.high);
  });

  test('sustained slow rendering degrades one step at a time', () {
    final controller = CandleQualityController();
    for (var i = 0; i < 12; i++) {
      controller.record(const Duration(milliseconds: 34));
    }
    expect(controller.profile, CandleQualityProfile.balanced);
    for (var i = 0; i < 12; i++) {
      controller.record(const Duration(milliseconds: 34));
    }
    expect(controller.profile, CandleQualityProfile.economy);
  });

  test('a long healthy run cautiously restores quality', () {
    final controller = CandleQualityController(
      profile: CandleQualityProfile.economy,
    );
    for (var i = 0; i < 360; i++) {
      controller.record(const Duration(milliseconds: 15));
    }
    expect(controller.profile, CandleQualityProfile.balanced);
  });
}
