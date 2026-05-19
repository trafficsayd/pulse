import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/primitives/haptic_pattern_player.dart';

void main() {
  group('HapticPatternPlayer', () {
    test('plays every beat in order against the engine', () async {
      final engine = RecordingHapticEngine();
      final player = HapticPatternPlayer(engine);
      const pattern = HapticPattern([
        HapticBeat(duration: Duration(milliseconds: 1), amplitude: 100),
        HapticBeat(duration: Duration(milliseconds: 1), amplitude: 200),
      ]);

      await player.play(pattern);

      expect(engine.played.length, 2);
      expect(engine.played[0].amplitude, 100);
      expect(engine.played[1].amplitude, 200);
    });

    test('stop() cancels in-flight playback', () async {
      final engine = RecordingHapticEngine();
      final player = HapticPatternPlayer(engine);
      const pattern = HapticPattern([
        HapticBeat(duration: Duration(milliseconds: 100)),
        HapticBeat(duration: Duration(milliseconds: 100)),
        HapticBeat(duration: Duration(milliseconds: 100)),
      ]);

      final future = player.play(pattern);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await player.stop();
      await future;

      expect(engine.played.length, lessThan(3));
      expect(player.isPlaying, isFalse);
    });

    test('NullHapticEngine is callable as a no-op', () async {
      const engine = NullHapticEngine();
      expect(engine.hasVibrator, isFalse);
      expect(engine.hasAmplitudeControl, isFalse);
      await engine.playBeat(
        const HapticBeat(duration: Duration(milliseconds: 1)),
      );
      await engine.cancel();
    });

    test('built-in patterns are non-empty and have positive duration', () {
      for (final p in [
        HapticPatterns.tap,
        HapticPatterns.heartbeat,
        HapticPatterns.whisper,
        HapticPatterns.triple,
      ]) {
        expect(p.beats, isNotEmpty);
        expect(p.totalDuration, greaterThan(Duration.zero));
      }
    });
  });
}
