import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/constellation/constellation_engine.dart';
import 'package:pulse/features/modes/application/constellation/constellation_models.dart';

void main() {
  const records = [
    ConstellationStar(
      id: 'a-0',
      authorId: 'a',
      x: .12,
      y: .18,
      authoredAtMs: 900,
      sequence: 0,
    ),
    ConstellationStar(
      id: 'b-0',
      authorId: 'b',
      x: .72,
      y: .74,
      authoredAtMs: 10000,
      sequence: 0,
    ),
    ConstellationStar(
      id: 'a-1',
      authorId: 'a',
      x: .7,
      y: .2,
      authoredAtMs: 11000,
      sequence: 1,
    ),
  ];

  test('packet order and duplicate delivery converge to one fingerprint', () {
    final first = ConstellationEngine(localAuthorId: 'a');
    final second = ConstellationEngine(localAuthorId: 'b');

    first.merge([records[2], records[0], records[1], records[2]]);
    second.merge([records[1], records[2], records[0], records[0]]);

    expect(first.snapshot.stars.map((star) => star.id), ['a-0', 'b-0', 'a-1']);
    expect(
      second.snapshot.stars.map((star) => star.id),
      first.snapshot.stars.map((star) => star.id),
    );
    expect(second.snapshot.fingerprint, first.snapshot.fingerprint);
    expect(second.snapshot.edges.length, first.snapshot.edges.length);
  });

  test('same ID is idempotent and conflict resolution is deterministic', () {
    final first = ConstellationEngine(localAuthorId: 'a');
    final second = ConstellationEngine(localAuthorId: 'b');
    final conflict = ConstellationStar(
      id: records.first.id,
      authorId: records.first.authorId,
      x: .99,
      y: .99,
      authoredAtMs: records.first.authoredAtMs,
      sequence: records.first.sequence,
    );

    expect(first.merge([records.first, records.first]), 1);
    first.merge([conflict]);
    second.merge([conflict, records.first]);

    expect(first.snapshot.stars, hasLength(1));
    expect(first.snapshot.fingerprint, second.snapshot.fingerprint);
  });

  test('distance, pause and intersections become deterministic story edges',
      () {
    final engine = ConstellationEngine(localAuthorId: 'a');
    engine.merge(const [
      ConstellationStar(
        id: 'one',
        authorId: 'a',
        x: 0,
        y: 0,
        authoredAtMs: 0,
        sequence: 0,
      ),
      ConstellationStar(
        id: 'two',
        authorId: 'a',
        x: 1,
        y: 1,
        authoredAtMs: 5000,
        sequence: 1,
      ),
      ConstellationStar(
        id: 'three',
        authorId: 'b',
        x: 0,
        y: 1,
        authoredAtMs: 6000,
        sequence: 0,
      ),
      ConstellationStar(
        id: 'four',
        authorId: 'b',
        x: 1,
        y: 0,
        authoredAtMs: 7000,
        sequence: 1,
      ),
    ]);

    expect(engine.snapshot.edges.first.pauseMs, 5000);
    expect(engine.snapshot.edges.last.crossesStory, isTrue);
    expect(
      engine.snapshot.edges.any((edge) => edge.bridgesPeople),
      isTrue,
    );
  });

  test('bounded history is pruned by shared chronological order', () {
    final first = ConstellationEngine(localAuthorId: 'a', maxStars: 2);
    final second = ConstellationEngine(localAuthorId: 'b', maxStars: 2);
    first.merge(records);
    second.merge(records.reversed);

    expect(first.snapshot.stars.map((star) => star.id), ['b-0', 'a-1']);
    expect(first.snapshot.fingerprint, second.snapshot.fingerprint);
  });
}
