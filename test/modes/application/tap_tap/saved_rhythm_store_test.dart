import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/storage/secure_key_store.dart';
import 'package:pulse/features/modes/application/tap_tap/saved_rhythm_store.dart';

void main() {
  SavedKnockRhythm rhythm(String id) => SavedKnockRhythm(
        id: id,
        name: 'Наш ритм $id',
        intervalsMs: const [0, 220, 180],
        intensities: const [.4, .8, .55],
      );

  test('round-trips only normalized rhythm fields', () async {
    final store = SavedRhythmStore(SecureKeyStore());
    await store.save(rhythm('one'));
    final values = await store.readAll();
    expect(values, hasLength(1));
    expect(values.single.name, 'Наш ритм one');
    expect(values.single.intervalsMs, [0, 220, 180]);
    expect(values.single.intensities, [.4, .8, .55]);
  });

  test('bounds history and replaces an existing id', () async {
    final store = SavedRhythmStore(SecureKeyStore(), capacity: 2);
    await store.save(rhythm('one'));
    await store.save(rhythm('two'));
    await store.save(rhythm('three'));
    await store.save(rhythm('two'));
    expect((await store.readAll()).map((item) => item.id), ['two', 'three']);
  });

  test('deletes a selected rhythm', () async {
    final store = SavedRhythmStore(SecureKeyStore());
    await store.save(rhythm('one'));
    await store.delete('one');
    expect(await store.readAll(), isEmpty);
  });

  test('rejects hardware-like or malformed values', () {
    expect(
      SavedKnockRhythm.tryParse({
        'id': 'bad',
        'name': 'bad',
        'intervalsMs': [0],
        'intensities': [5.0],
      }),
      isNull,
    );
  });
}
