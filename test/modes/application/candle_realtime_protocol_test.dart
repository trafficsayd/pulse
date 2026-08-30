import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/candle_realtime_protocol.dart';

void main() {
  group('CandleRealtimeGuard', () {
    test('accepts increasing samples and rejects duplicates or late samples',
        () {
      final guard = CandleRealtimeGuard();

      expect(guard.accept('breath', {'sequence': 4}), isTrue);
      expect(guard.accept('breath', {'sequence': 4}), isFalse);
      expect(guard.accept('breath', {'sequence': 2}), isFalse);
      expect(guard.accept('breath', {'sequence': 5}), isTrue);
    });

    test('tracks breath and motion independently', () {
      final guard = CandleRealtimeGuard();

      expect(guard.accept('breath', {'sequence': 9}), isTrue);
      expect(guard.accept('motion', {'sequence': 1}), isTrue);
    });

    test('accepts legacy packets but rejects malformed sequence values', () {
      final guard = CandleRealtimeGuard();

      expect(guard.accept('breath', {'level': .5}), isTrue);
      expect(guard.accept('breath', {'sequence': '3'}), isFalse);
      expect(guard.accept('breath', {'sequence': -1}), isFalse);
    });
  });

  test('payload includes ordering metadata without changing values', () {
    final payload = candleRealtimePayload(
      sequence: 12,
      elapsed: const Duration(milliseconds: 25),
      values: const {'level': .7},
    );

    expect(payload, containsPair('sequence', 12));
    expect(payload, containsPair('elapsedMicros', 25000));
    expect(payload, containsPair('level', .7));
  });
}
