import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/sync_dynamics.dart';

void main() {
  test('clock estimator removes partner clock offset from tap time', () {
    final clock = SyncClockEstimator();
    // Partner clock is 500 ms ahead. Network takes 40 ms each way and the
    // partner spends 2 ms preparing the response.
    clock.observeExchange(
      localSentUs: 1_000_000,
      partnerReceivedUs: 1_540_000,
      partnerSentUs: 1_542_000,
      localReceivedUs: 1_082_000,
    );

    expect(clock.partnerOffset.inMilliseconds, 500);
    expect(clock.roundTrip.inMilliseconds, 80);
    expect(clock.partnerToLocalUs(2_500_000), 2_000_000);
  });

  test('bad clock exchange is ignored', () {
    final clock = SyncClockEstimator();
    clock.observeExchange(
      localSentUs: 200,
      partnerReceivedUs: 400,
      partnerSentUs: 300,
      localReceivedUs: 500,
    );
    expect(clock.hasSample, isFalse);
  });

  test('matching taps build progress and tighten tolerance', () {
    final tracker = SyncProgressTracker();
    final initialTolerance = tracker.toleranceMs;
    SyncProgressUpdate? update;
    var completed = false;
    for (var i = 0; i < 8; i++) {
      update = tracker.scoreDifference(35);
      completed = completed || update.completedNow;
    }

    expect(update!.matched, isTrue);
    expect(tracker.progress, 1);
    expect(tracker.toleranceMs, lessThan(initialTolerance));
    expect(completed, isTrue);
  });

  test('one miss reduces progress gently instead of resetting it', () {
    final tracker = SyncProgressTracker();
    tracker.scoreDifference(40);
    tracker.scoreDifference(40);
    final before = tracker.progress;
    final update = tracker.scoreDifference(900);

    expect(update.matched, isFalse);
    expect(update.progress, greaterThan(0));
    expect(before - update.progress, lessThan(.06));
    expect(update.streak, 0);
  });
}
