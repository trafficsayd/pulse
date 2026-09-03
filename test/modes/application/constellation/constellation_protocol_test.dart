import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/constellation/constellation_models.dart';
import 'package:pulse/features/modes/application/constellation/constellation_protocol.dart';
import 'package:pulse/features/session/application/mode_event.dart';

void main() {
  const first = ConstellationStar(
    id: 'a-1',
    authorId: 'a',
    x: .2,
    y: .3,
    authoredAtMs: 100,
    sequence: 0,
    energy: .6,
  );
  const second = ConstellationStar(
    id: 'b-1',
    authorId: 'b',
    x: .7,
    y: .8,
    authoredAtMs: 240,
    sequence: 0,
    energy: .8,
  );

  test('v2 round-trip includes reconciliation history without duplication', () {
    final event = ConstellationProtocol.encode(
      second,
      history: const [first, second],
    );
    final packet = ConstellationProtocol.tryDecode(
      event,
      receivedAtMs: 999,
    );

    expect(event.type, 'star');
    expect(event.data['v'], 2);
    expect(packet, isNotNull);
    expect(packet!.records.map((star) => star.id), ['a-1', 'b-1']);
    expect(packet.records.last.energy, closeTo(.8, .0001));
  });

  test('legacy coordinate packet remains readable and normalized', () {
    final packet = ConstellationProtocol.tryDecode(
      const ModeEvent(type: 'star', data: {'x': 1.4, 'y': -.2}),
      receivedAtMs: 123,
    );

    expect(packet, isNotNull);
    expect(packet!.records.single.x, 1);
    expect(packet.records.single.y, 0);
    expect(packet.records.single.authorId, 'partner-legacy');
  });

  test('malformed and unrelated events are ignored', () {
    expect(
      ConstellationProtocol.tryDecode(
        const ModeEvent(type: 'tap'),
        receivedAtMs: 0,
      ),
      isNull,
    );
    expect(
      ConstellationProtocol.tryDecode(
        const ModeEvent(type: 'star', data: {'records': 'broken'}),
        receivedAtMs: 0,
      ),
      isNull,
    );
  });
}
