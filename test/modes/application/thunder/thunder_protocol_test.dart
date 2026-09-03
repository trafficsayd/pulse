import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/thunder/thunder_models.dart';
import 'package:pulse/features/modes/application/thunder/thunder_protocol.dart';
import 'package:pulse/features/session/application/mode_event.dart';

void main() {
  const strike = ThunderStrike(
    id: 'strike-v2',
    createdAtMs: 1700000000000,
    originX: .2,
    originY: .8,
    directionX: .6,
    directionY: -.8,
    intensity: .9,
    velocity: .72,
    seed: 418,
    handoffMs: 390,
  );

  test('versioned strike survives encrypted-event wire shape', () {
    final event = ModeEvent.decode(ThunderProtocol.strike(strike).encode());
    final decoded = ThunderProtocol.tryParse(event);
    expect(event.data['v'], ThunderStrike.protocolVersion);
    expect(decoded?.id, strike.id);
    expect(decoded?.seed, strike.seed);
    expect(decoded?.directionX, closeTo(.6, .0001));
    expect(decoded?.directionY, closeTo(-.8, .0001));
  });

  test('legacy horizontal coordinate gets a safe deterministic strike', () {
    final decoded = ThunderProtocol.tryParse(
      const ModeEvent(type: ThunderProtocol.eventType, data: {'x': .4}),
      nowMs: 123,
    );
    expect(decoded, isNotNull);
    expect(decoded!.originX, .4);
    expect(decoded.handoffMs, 0);
  });

  test('unknown and malformed payloads are rejected', () {
    expect(
      ThunderProtocol.tryParse(const ModeEvent(
        type: ThunderProtocol.eventType,
        data: {'v': 99, 'x': .2},
      )),
      isNull,
    );
    expect(
      ThunderProtocol.tryParse(const ModeEvent(
        type: ThunderProtocol.eventType,
        data: {'v': 2, 'id': 'broken'},
      )),
      isNull,
    );
  });
}
