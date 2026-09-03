import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/fireworks/firework_engine.dart';
import 'package:pulse/features/modes/application/fireworks/firework_models.dart';

void main() {
  const a = FireworkContribution(
    id: 'a-1',
    authorId: 'a',
    x: .2,
    y: .4,
    authoredAtMs: 1000,
    sequence: 0,
    seed: 11,
    palette: 1,
  );
  const b = FireworkContribution(
    id: 'b-1',
    authorId: 'b',
    x: .8,
    y: .3,
    authoredAtMs: 2100,
    sequence: 0,
    seed: 29,
    palette: 4,
  );

  test('reordered and duplicate delivery converges', () {
    final first = FireworkEngine(localAuthorId: 'a');
    final second = FireworkEngine(localAuthorId: 'b');
    first.merge(const [b, a, b]);
    second.merge(const [a, b, a]);

    expect(first.snapshot.contributions.map((item) => item.id), ['a-1', 'b-1']);
    expect(first.snapshot.fingerprint, second.snapshot.fingerprint);
    expect(first.snapshot.culminations.single.id,
        second.snapshot.culminations.single.id);
    expect(first.snapshot.culminations.single.seed,
        second.snapshot.culminations.single.seed);
  });

  test('one participant cannot create joint culmination', () {
    final engine = FireworkEngine(localAuthorId: 'a');
    engine.merge(const [
      a,
      FireworkContribution(
        id: 'a-2',
        authorId: 'a',
        x: .6,
        y: .2,
        authoredAtMs: 1200,
        sequence: 1,
        seed: 2,
        palette: 2,
      ),
    ]);

    expect(engine.snapshot.culminations, isEmpty);
  });

  test('causal reply creates joint result outside clock window', () {
    final engine = FireworkEngine(localAuthorId: 'a');
    engine.merge(const [
      a,
      FireworkContribution(
        id: 'b-late',
        authorId: 'b',
        x: .7,
        y: .2,
        authoredAtMs: 25000,
        sequence: 1,
        seed: 7,
        palette: 3,
        replyToId: 'a-1',
      ),
    ]);

    final joint = engine.snapshot.culminations.single;
    expect(joint.firstId, 'a-1');
    expect(joint.secondId, 'b-late');
    expect(joint.paletteA, 1);
    expect(joint.paletteB, 3);
  });

  test('old unrelated contributions do not create a culmination', () {
    final engine = FireworkEngine(localAuthorId: 'a');
    engine.merge(const [
      a,
      FireworkContribution(
        id: 'b-old',
        authorId: 'b',
        x: .4,
        y: .4,
        authoredAtMs: 10000,
        sequence: 0,
        seed: 9,
        palette: 0,
      ),
    ]);
    expect(engine.snapshot.culminations, isEmpty);
  });

  test('bounded history prunes identically', () {
    final first = FireworkEngine(localAuthorId: 'a', maxContributions: 1);
    final second = FireworkEngine(localAuthorId: 'b', maxContributions: 1);
    first.merge(const [a, b]);
    second.merge(const [b, a]);

    expect(first.snapshot.contributions.single.id, 'b-1');
    expect(first.snapshot.fingerprint, second.snapshot.fingerprint);
  });
}
