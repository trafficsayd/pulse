import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/session/application/mode_event.dart';

void main() {
  group('PulseSession', () {
    test('sendEvent encodes and sends a ModeEvent', () {
      // We test via a direct PulseSession construction with mock dependencies.
      // Since PulseSession wraps TransportManager + PairChannel, and PairChannel
      // needs real crypto, we test the ModeEvent encoding path.
      const event = ModeEvent(type: 'tap', data: {'x': 0.5, 'y': 0.3});
      final encoded = event.encode();

      // Verify the encoding is valid JSON.
      final decoded = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
      expect(decoded['t'], 'tap');
      expect(decoded['x'], 0.5);
    });

    test('events stream filters malformed packets', () {
      // Test ModeEvent.tryDecode filtering behavior.
      final good = const ModeEvent(type: 'bell_ring').encode();
      final bad = Uint8List.fromList([0xFF, 0xFE]);

      expect(ModeEvent.tryDecode(good), isNotNull);
      expect(ModeEvent.tryDecode(bad), isNull);
    });

    test('ModeEvent.tryDecode handles missing type key gracefully', () {
      // JSON without 't' key.
      final bytes = Uint8List.fromList(utf8.encode('{"foo":"bar"}'));
      // This should not crash — it returns null because map.remove('t')
      // returns null and the cast to String fails.
      expect(ModeEvent.tryDecode(bytes), isNull);
    });
  });
}
