import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/whisper/audio_feeling_controller.dart';
import 'package:pulse/features/modes/primitives/mic_level_stream.dart';

void main() {
  group('AudioFeelingController', () {
    test('gates room noise and responds smoothly to a close whisper', () {
      final controller = AudioFeelingController();
      final start = DateTime(2026, 9, 1, 12);

      for (var i = 0; i < 40; i++) {
        controller.process(MicLevel(
          level01: 0.025,
          noiseLikeness: 0.8,
          timestamp: start.add(Duration(milliseconds: i * 20)),
        ));
      }
      final quiet = controller.process(MicLevel(
        level01: 0.03,
        noiseLikeness: 0.8,
        timestamp: start.add(const Duration(seconds: 1)),
      ));
      final whisper = controller.process(MicLevel(
        level01: 0.52,
        noiseLikeness: 0.92,
        timestamp: start.add(const Duration(milliseconds: 1020)),
      ));

      expect(quiet.intensity, lessThan(0.03));
      expect(whisper.intensity, greaterThan(quiet.intensity));
      expect(whisper.breathiness, greaterThan(0.65));
      expect(whisper.proximity, inInclusiveRange(0.0, 1.0));
    });

    test('fallback contains only feeling parameters and ends in silence', () {
      final controller = AudioFeelingController();
      final now = DateTime(2026, 9, 1, 12);
      final feeling = controller.fallback(0.5, now);
      final silence = controller.silence(now.add(const Duration(seconds: 1)));

      expect(feeling.isFallback, isTrue);
      expect(feeling.intensity, greaterThan(0.5));
      expect(feeling.breathiness, 0.9);
      expect(silence.isSilent, isTrue);
    });

    test('rate limits network frames', () {
      final controller = AudioFeelingController();
      final start = DateTime(2026, 9, 1, 12);
      final first = controller.fallback(0.1, start);
      final tooSoon = controller.fallback(
        0.5,
        start.add(const Duration(milliseconds: 40)),
      );
      final later = controller.fallback(
        0.5,
        start.add(const Duration(milliseconds: 100)),
      );

      expect(controller.shouldSend(first), isTrue);
      expect(controller.shouldSend(tooSoon), isFalse);
      expect(controller.shouldSend(later), isTrue);
    });
  });
}
