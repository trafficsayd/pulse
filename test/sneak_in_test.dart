import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/sneak_in/application/sneak_in_controller.dart';

void main() {
  group('SneakInUsageState', () {
    final day1 = DateTime(2025, 1, 1, 10);
    final day1Late = DateTime(2025, 1, 1, 23, 50);
    final day2 = DateTime(2025, 1, 2, 0, 1);

    test('rolling forward within the same day keeps usage', () {
      const initial = SneakInUsageState(usage: {'a': 1});
      final rolled = initial.rolledForward(day1);
      // No bucketDay set, so the rolled state owns today's bucket fresh.
      expect(rolled.usage, isEmpty);
      expect(rolled.bucketDay, DateTime(2025, 1, 1));
    });

    test('rolling forward across midnight resets usage', () {
      final yesterday = SneakInUsageState(
        usage: const {'a': 1},
        bucketDay: DateTime(2025, 1, 1),
      ).withIncrement('a');
      // Same day, rolledForward returns same state.
      expect(yesterday.rolledForward(day1Late).usage['a'], 2);
      // Next day, usage resets.
      expect(yesterday.rolledForward(day2).usage, isEmpty);
    });

    test('JSON round-trip preserves bucket day and counts', () {
      final state = SneakInUsageState(
        usage: const {'a': 2, 'b': 1},
        bucketDay: DateTime(2025, 1, 1),
      );
      final restored = SneakInUsageState.fromJson(state.toJson());
      expect(restored.usage, state.usage);
      expect(restored.bucketDay, state.bucketDay);
    });
  });
}
