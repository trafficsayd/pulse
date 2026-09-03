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

  test('congested outlier does not drag an acquired clock', () {
    final clock = SyncClockEstimator();
    for (var i = 0; i < 5; i++) {
      clock.observeExchange(
        localSentUs: 1_000_000 + i * 200_000,
        partnerReceivedUs: 1_520_000 + i * 200_000,
        partnerSentUs: 1_521_000 + i * 200_000,
        localReceivedUs: 1_041_000 + i * 200_000,
      );
    }
    final before = clock.partnerOffset.inMilliseconds;
    clock.observeExchange(
      localSentUs: 3_000_000,
      partnerReceivedUs: 4_100_000,
      partnerSentUs: 4_101_000,
      localReceivedUs: 3_901_000,
    );

    expect(clock.partnerOffset.inMilliseconds, closeTo(before, 3));
    expect(clock.sampleCount, 5);
  });

  test('two tempos glide toward a shared interval and keep a local fallback',
      () {
    final rhythm = SharedRhythmReconciler(
      initialInterval: const Duration(milliseconds: 1600),
    );
    rhythm.observeLocalTap(1_000_000);
    rhythm.observePartnerTap(1_080_000);
    for (var i = 1; i <= 8; i++) {
      rhythm.observeLocalTap(1_000_000 + i * 1_200_000);
      rhythm.observePartnerTap(1_080_000 + i * 1_400_000);
    }

    expect(rhythm.interval.inMilliseconds, inInclusiveRange(1250, 1450));
    final next = rhythm.nextBeatAfterUs(20_000_000);
    expect(next, greaterThan(20_000_000));
    expect(
        next - 20_000_000, lessThanOrEqualTo(rhythm.interval.inMicroseconds));
  });

  test('versioned sync events are idempotent while legacy remains readable',
      () {
    final deduplicator = SyncEventDeduplicator(capacity: 2);
    final event = SyncProtocol.envelope(
      epoch: 10,
      sequence: 4,
      sentAtUs: 100,
    );

    expect(deduplicator.accept(event), isTrue);
    expect(deduplicator.accept(event), isFalse);
    expect(deduplicator.accept(<String, dynamic>{'sentAtUs': 100}), isTrue);
  });

  test('older sequence cannot restore stale sync state', () {
    final deduplicator = SyncEventDeduplicator();
    final released = SyncProtocol.envelope(
      epoch: 90,
      sequence: 12,
      sentAtUs: 120,
      data: const {'active': false},
    );
    final staleHold = SyncProtocol.envelope(
      epoch: 90,
      sequence: 11,
      sentAtUs: 110,
      data: const {'active': true},
    );

    expect(deduplicator.accept(released), isTrue);
    expect(deduplicator.accept(staleHold), isFalse);
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
