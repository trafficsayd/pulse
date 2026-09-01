import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/bell/bell_models.dart';
import 'package:pulse/features/modes/application/bell/bell_protocol.dart';
import 'package:pulse/features/session/application/mode_event.dart';

void main() {
  test('version two strike round-trips all material semantics', () {
    const strike = BellStrike(
      id: 'ring-42',
      occurredAtMs: 123456,
      material: BellMaterial.crystal,
      strength: .73,
      direction: -1,
      pitch: .82,
      resonanceSeconds: 3.5,
    );

    final event = BellProtocol.encode(strike);
    final decoded = BellProtocol.decode(event);

    expect(event.type, BellProtocol.eventType);
    expect(event.data['v'], BellProtocol.version);
    expect(decoded?.id, strike.id);
    expect(decoded?.material, BellMaterial.crystal);
    expect(decoded?.strength, .73);
    expect(decoded?.direction, -1);
    expect(decoded?.remote, isTrue);
  });

  test('legacy intensity-only ring remains compatible', () {
    const event = ModeEvent(type: 'bell_ring', data: {'intensity': .45});
    final decoded = BellProtocol.decode(event);

    expect(decoded, isNotNull);
    expect(decoded!.material, BellMaterial.brass);
    expect(decoded.strength, .45);
  });

  test('malformed payload is rejected and strength is clamped', () {
    expect(
      BellProtocol.decode(const ModeEvent(type: 'bell_ring')),
      isNull,
    );
    final decoded = BellProtocol.decode(
      const ModeEvent(type: 'bell_ring', data: {'intensity': 9}),
    );
    expect(decoded?.strength, 1);
  });

  test('deduplicator accepts one copy and evicts bounded history', () {
    final dedupe = BellStrikeDeduplicator(capacity: 2);
    expect(dedupe.accept('a'), isTrue);
    expect(dedupe.accept('a'), isFalse);
    expect(dedupe.accept('b'), isTrue);
    expect(dedupe.accept('c'), isTrue);
    expect(dedupe.accept('a'), isTrue);
  });
}
