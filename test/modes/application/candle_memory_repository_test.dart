import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/storage/secure_key_store.dart';
import 'package:pulse/features/modes/application/candle_dynamics.dart';
import 'package:pulse/features/modes/application/candle_memory_repository.dart';

void main() {
  test('candle memory is persisted separately for each pair and style',
      () async {
    final store = SecureKeyStore();
    final firstPair = CandleMemoryRepository(
      store: store,
      connectionId: 'pair-a',
    );
    final secondPair = CandleMemoryRepository(
      store: store,
      connectionId: 'pair-b',
    );
    final memory = CandleMemory.fresh(seed: 7).copyWith(
      waxRemaining: .63,
      sessions: 4,
      sealedWish: 'Only ours',
    );

    await firstPair.save(CandleStyle.violet, memory);

    final restored = await firstPair.load(CandleStyle.violet);
    final otherStyle = await firstPair.load(CandleStyle.classic);
    final otherPair = await secondPair.load(CandleStyle.violet);
    expect(restored.waxRemaining, .63);
    expect(restored.sealedWish, 'Only ours');
    expect(otherStyle.waxRemaining, 1);
    expect(otherPair.waxRemaining, 1);
  });
}
