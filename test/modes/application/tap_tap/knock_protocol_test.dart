import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/tap_tap/knock_models.dart';
import 'package:pulse/features/modes/application/tap_tap/knock_protocol.dart';
import 'package:pulse/features/session/application/mode_event.dart';

void main() {
  const hit = KnockHit(
    id: 'hit-1',
    seriesId: 'series-1',
    sequence: 2,
    x: .25,
    y: .75,
    relativeOffsetMs: 410,
    character: KnockCharacter(
      intensity: .7,
      sharpness: .4,
      durationMs: 120,
      contactClass: KnockContactClass.soft,
      confidence: .68,
    ),
  );

  test('round-trips a versioned knock hit', () {
    final event = KnockProtocol.hit(hit);
    final parsed = KnockProtocol.tryParseHit(event);
    expect(parsed, isNotNull);
    expect(parsed!.id, hit.id);
    expect(parsed.sequence, 2);
    expect(parsed.character.depth, KnockDepth.deep);
  });

  test('converts a valid legacy tap', () {
    const event = ModeEvent(type: 'tap', data: {'x': .2, 'y': .8});
    final parsed = KnockProtocol.tryParseHit(event);
    expect(parsed, isNotNull);
    expect(parsed!.seriesId, 'legacy');
    expect(parsed.character.confidence, lessThan(.5));
  });

  test('rejects invalid coordinates and unknown versions', () {
    expect(
      KnockProtocol.tryParseHit(
        const ModeEvent(type: 'tap', data: {'x': 2, 'y': 0}),
      ),
      isNull,
    );
    final data = {...KnockProtocol.hit(hit).data, 'v': 99};
    expect(
      KnockProtocol.tryParseHit(ModeEvent(type: 'knock_hit', data: data)),
      isNull,
    );
  });

  test('deduplicator is bounded and suppresses repeats', () {
    final dedupe = KnockDeduplicator(capacity: 2);
    expect(dedupe.accept('a'), isTrue);
    expect(dedupe.accept('a'), isFalse);
    expect(dedupe.accept('b'), isTrue);
    expect(dedupe.accept('c'), isTrue);
    expect(dedupe.accept('a'), isTrue);
  });
}
