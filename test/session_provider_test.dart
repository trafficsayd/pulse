import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/session/application/mode_event.dart';
import 'package:pulse/features/session/application/mode_event_bus.dart';

void main() {
  group('ModeEventBus', () {
    test('inert bus is not connected', () {
      final bus = ModeEventBus.inert();
      expect(bus.isConnected, isFalse);
    });

    test('inert bus send is a no-op', () async {
      final bus = ModeEventBus.inert();
      // Should not throw.
      await bus.send(const ModeEvent(type: 'tap'));
    });

    test('inert bus incoming is an empty stream', () async {
      final bus = ModeEventBus.inert();
      final events = <ModeEvent>[];
      final sub = bus.incoming.listen(events.add);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(events, isEmpty);
      await sub.cancel();
    });

    test('replay waits for the first frame window and preserves event order',
        () async {
      final source = StreamController<ModeEvent>.broadcast(sync: true);
      final bus = ModeEventBus.testing(source.stream);
      const first = ModeEvent(type: 'ray_point', data: {'x': 0.1});
      const second = ModeEvent(type: 'ray_end');
      source.add(first);
      source.add(second);

      final received = <ModeEvent>[];
      final sub = bus.incoming.listen(received.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received, isEmpty,
          reason: 'the mode canvas must be allowed to finish its first frame');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(received, [first, second]);

      await sub.cancel();
      await bus.dispose();
      await source.close();
    });

    test('a replay snapshot is consumed after the first mode opens', () async {
      final source = StreamController<ModeEvent>.broadcast(sync: true);
      final bus = ModeEventBus.testing(source.stream);
      const tap = ModeEvent(type: 'tap');
      source.add(tap);

      final first = await bus.incoming.first;
      expect(first, same(tap));

      final replayedAgain = <ModeEvent>[];
      final secondSub = bus.incoming.listen(replayedAgain.add);
      await Future<void>.delayed(const Duration(milliseconds: 130));
      expect(replayedAgain, isEmpty);

      await secondSub.cancel();
      await bus.dispose();
      await source.close();
    });
  });
}
