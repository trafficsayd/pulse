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
  });
}
