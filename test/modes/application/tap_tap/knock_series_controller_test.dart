import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/tap_tap/knock_models.dart';
import 'package:pulse/features/modes/application/tap_tap/knock_series_controller.dart';

void main() {
  const character = KnockCharacter.legacy();

  test('keeps taps inside idle window in one ordered series', () {
    var id = 0;
    final controller = KnockSeriesController(idFactory: () => 'id-${id++}');
    final first = controller.add(
      nowMs: 1000,
      x: .2,
      y: .3,
      character: character,
    );
    final second = controller.add(
      nowMs: 1420,
      x: .4,
      y: .5,
      character: character,
    );

    expect(second.seriesId, first.seriesId);
    expect(first.sequence, 0);
    expect(second.sequence, 1);
    expect(second.relativeOffsetMs, 420);
  });

  test('starts a new series after idle window', () {
    var id = 0;
    final controller = KnockSeriesController(idFactory: () => 'id-${id++}');
    final first = controller.add(
      nowMs: 1000,
      x: .2,
      y: .3,
      character: character,
    );
    final second = controller.add(
      nowMs: 2001,
      x: .2,
      y: .3,
      character: character,
    );
    expect(second.seriesId, isNot(first.seriesId));
    expect(second.sequence, 0);
  });

  test('starts a new series at configured hit limit', () {
    var id = 0;
    final controller = KnockSeriesController(
      idFactory: () => 'id-${id++}',
      maxHits: 2,
    );
    final first = controller.add(
      nowMs: 1000,
      x: 0,
      y: 0,
      character: character,
    );
    controller.add(
      nowMs: 1100,
      x: 0,
      y: 0,
      character: character,
    );
    final third = controller.add(
      nowMs: 1200,
      x: 0,
      y: 0,
      character: character,
    );
    expect(third.seriesId, isNot(first.seriesId));
  });
}
