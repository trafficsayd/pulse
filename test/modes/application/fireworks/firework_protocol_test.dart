import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/fireworks/firework_models.dart';
import 'package:pulse/features/modes/application/fireworks/firework_protocol.dart';
import 'package:pulse/features/session/application/mode_event.dart';

void main() {
  const first = FireworkContribution(
    id: 'first',
    authorId: 'a',
    x: .2,
    y: .3,
    authoredAtMs: 100,
    sequence: 0,
    seed: 17,
    palette: 2,
  );
  const second = FireworkContribution(
    id: 'second',
    authorId: 'b',
    x: .8,
    y: .4,
    authoredAtMs: 200,
    sequence: 0,
    seed: 19,
    palette: 4,
    replyToId: 'first',
  );

  test('v2 round-trip preserves seeds, time, reply and history', () {
    final event = FireworkProtocol.encode(
      second,
      history: const [first, second],
    );
    final packet = FireworkProtocol.tryDecode(event, receivedAtMs: 500);

    expect(event.type, 'firework');
    expect(event.data['v'], 2);
    expect(packet!.records.map((item) => item.id), ['first', 'second']);
    expect(event.data['newestId'], 'second');
    expect(packet.newestId, 'second');
    expect(packet.newest.id, second.id);
    expect(packet.newest.canonicalSignature, second.canonicalSignature);
    expect(packet.records.last.seed, 19);
    expect(packet.records.last.replyToId, 'first');
  });

  test('explicit newest id survives a reordered history packet', () {
    final packet = FireworkProtocol.tryDecode(
      const ModeEvent(
        type: 'firework',
        data: {
          'v': 2,
          'newestId': 'first',
          'records': [
            {
              'id': 'first',
              'a': 'a',
              'x': .2,
              'y': .3,
              'at': 100,
              's': 0,
              'seed': 17,
              'p': 2,
            },
            {
              'id': 'second',
              'a': 'b',
              'x': .8,
              'y': .4,
              'at': 200,
              's': 0,
              'seed': 19,
              'p': 4,
            },
          ],
        },
      ),
      receivedAtMs: 500,
    );

    expect(packet!.newestId, 'first');
    expect(packet.newest.id, 'first');
  });

  test('legacy firework remains visible after rolling upgrade', () {
    final packet = FireworkProtocol.tryDecode(
      const ModeEvent(
        type: 'firework',
        data: {'x': 1.2, 'y': -.3, 'color': 1234},
      ),
      receivedAtMs: 900,
    );

    expect(packet, isNotNull);
    expect(packet!.records.single.x, 1);
    expect(packet.records.single.y, .08);
    expect(packet.records.single.authorId, 'partner-legacy');
  });

  test('malformed payloads are ignored safely', () {
    expect(
      FireworkProtocol.tryDecode(
        const ModeEvent(type: 'tap'),
        receivedAtMs: 0,
      ),
      isNull,
    );
    expect(
      FireworkProtocol.tryDecode(
        const ModeEvent(type: 'firework', data: {'records': 'bad'}),
        receivedAtMs: 0,
      ),
      isNull,
    );
  });
}
