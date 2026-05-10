import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/sketch_usage_controller.dart';

void main() {
  group('SketchUsageState', () {
    final day1 = DateTime(2025, 1, 1, 10);
    final day1Late = DateTime(2025, 1, 1, 23, 50);
    final day2 = DateTime(2025, 1, 2, 0, 1);

    test('rolling forward without a bucket day adopts today', () {
      const initial = SketchUsageState(strokesUsed: 5);
      final rolled = initial.rolledForward(day1);
      // No bucketDay was set, so the rolled state owns today's bucket fresh.
      expect(rolled.strokesUsed, 0);
      expect(rolled.bucketDay, DateTime(2025, 1, 1));
    });

    test('rolling forward within the same day keeps the count', () {
      final state = SketchUsageState(
        strokesUsed: 3,
        bucketDay: DateTime(2025, 1, 1),
      );
      expect(state.rolledForward(day1Late).strokesUsed, 3);
    });

    test('rolling forward across midnight resets the count', () {
      final state = SketchUsageState(
        strokesUsed: 17,
        bucketDay: DateTime(2025, 1, 1),
      );
      final next = state.rolledForward(day2);
      expect(next.strokesUsed, 0);
      expect(next.bucketDay, DateTime(2025, 1, 2));
    });

    test('withIncrement bumps strokesUsed by one', () {
      final base = SketchUsageState(
        strokesUsed: 10,
        bucketDay: DateTime(2025, 1, 1),
      );
      final next = base.withIncrement();
      expect(next.strokesUsed, 11);
      expect(next.bucketDay, base.bucketDay);
    });

    test('JSON round-trip preserves bucket day and count', () {
      final state = SketchUsageState(
        strokesUsed: 7,
        bucketDay: DateTime(2025, 1, 1),
      );
      final restored = SketchUsageState.fromJson(state.toJson());
      expect(restored.strokesUsed, state.strokesUsed);
      expect(restored.bucketDay, state.bucketDay);
    });
  });
}
