import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/half_heart/heart_presence_models.dart';
import 'package:pulse/features/modes/application/half_heart/heart_presence_protocol.dart';
import 'package:pulse/features/session/application/mode_event.dart';

void main() {
  const signal = HeartHoldSignal(
    eventId: 'event-1',
    holdId: 'hold-1',
    sequence: 3,
    sentAtMs: 1000,
    held: true,
    strength: .72,
    x: .31,
    y: .64,
  );

  test('round-trips a versioned presence heartbeat', () {
    final event = HeartPresenceProtocol.encode(signal);
    final parsed = HeartPresenceProtocol.tryParse(
      event,
      receivedAtMs: 1010,
    );

    expect(event.type, 'hold_start');
    expect(event.data['v'], HeartPresenceProtocol.version);
    expect(parsed?.holdId, signal.holdId);
    expect(parsed?.sequence, signal.sequence);
    expect(parsed?.strength, closeTo(.72, .001));
  });

  test('keeps legacy hold events compatible', () {
    final start = HeartPresenceProtocol.tryParse(
      const ModeEvent(type: 'hold_start'),
      receivedAtMs: 1200,
    );
    final end = HeartPresenceProtocol.tryParse(
      const ModeEvent(type: 'hold_end'),
      receivedAtMs: 1300,
    );

    expect(start?.held, isTrue);
    expect(start?.isLegacy, isTrue);
    expect(end?.held, isFalse);
  });

  test('rejects unknown versions and contradictory outer type', () {
    expect(
      HeartPresenceProtocol.tryParse(
        ModeEvent(
          type: 'hold_start',
          data: {...HeartPresenceProtocol.encode(signal).data, 'v': 99},
        ),
        receivedAtMs: 1000,
      ),
      isNull,
    );
    expect(
      HeartPresenceProtocol.tryParse(
        ModeEvent(
          type: 'hold_end',
          data: HeartPresenceProtocol.encode(signal).data,
        ),
        receivedAtMs: 1000,
      ),
      isNull,
    );
  });
}
