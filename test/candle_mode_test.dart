import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/session/application/mode_event.dart';

void main() {
  group('Candle mode events', () {
    test('candle_light event encodes correctly', () {
      const event = ModeEvent(type: 'candle_light');
      final bytes = event.encode();
      final restored = ModeEvent.decode(bytes);
      expect(restored.type, 'candle_light');
      expect(restored.data, isEmpty);
    });

    test('candle_blow event includes level data', () {
      const event = ModeEvent(type: 'candle_blow', data: {'level': 0.85});
      final bytes = event.encode();
      final restored = ModeEvent.decode(bytes);
      expect(restored.type, 'candle_blow');
      expect(restored.data['level'], 0.85);
    });

    test('candle events round-trip through encode/decode', () {
      const events = [
        ModeEvent(type: 'candle_light'),
        ModeEvent(type: 'candle_blow', data: {'level': 0.7}),
      ];

      for (final original in events) {
        final bytes = original.encode();
        final restored = ModeEvent.decode(bytes);
        expect(restored.type, original.type);
        expect(restored.data.keys, original.data.keys);
      }
    });
  });
}
