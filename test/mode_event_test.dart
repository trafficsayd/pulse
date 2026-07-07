import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/session/application/mode_event.dart';

void main() {
  group('ModeEvent', () {
    test('encode produces compact JSON with "t" key', () {
      const event = ModeEvent(type: 'tap', data: {'x': 0.5, 'y': 0.3});
      final bytes = event.encode();
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(decoded['t'], 'tap');
      expect(decoded['x'], 0.5);
      expect(decoded['y'], 0.3);
    });

    test('decode round-trips an encoded event', () {
      const original = ModeEvent(
        type: 'candle_light',
        data: {'intensity': 1},
      );
      final bytes = original.encode();
      final restored = ModeEvent.decode(bytes);
      expect(restored.type, 'candle_light');
      expect(restored.data['intensity'], 1);
    });

    test('encode with empty data produces just the type key', () {
      const event = ModeEvent(type: 'hold_start');
      final bytes = event.encode();
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(decoded.length, 1);
      expect(decoded['t'], 'hold_start');
    });

    test('tryDecode returns null on malformed bytes', () {
      final garbage = Uint8List.fromList([0xFF, 0xFE, 0xFD]);
      expect(ModeEvent.tryDecode(garbage), isNull);
    });

    test('tryDecode returns null on valid JSON without "t" key', () {
      final noType = Uint8List.fromList(utf8.encode('{"x":1}'));
      // jsonDecode will parse it but removing 't' yields null, and cast fails.
      expect(ModeEvent.tryDecode(noType), isNull);
    });

    test('tryDecode returns event for well-formed payload', () {
      const event = ModeEvent(type: 'bell_ring', data: {'intensity': 0.8});
      final bytes = event.encode();
      final result = ModeEvent.tryDecode(bytes);
      expect(result, isNotNull);
      expect(result!.type, 'bell_ring');
      expect(result.data['intensity'], 0.8);
    });

    test('toString includes type and data', () {
      const event = ModeEvent(type: 'star', data: {'x': 1, 'y': 2});
      expect(event.toString(), contains('star'));
      expect(event.toString(), contains('x'));
    });
  });
}
