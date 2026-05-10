import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/subscription/domain/entitlements.dart';

void main() {
  group('Entitlements', () {
    final start = DateTime.utc(2025, 1, 1);

    test('fresh trial reports 7 days remaining', () {
      final e = Entitlements(
        tier: SubscriptionTier.trial,
        trialStartedAt: start,
      );
      expect(e.trialDaysRemaining(now: start), 7);
    });

    test('mid-trial counts down', () {
      final e = Entitlements(
        tier: SubscriptionTier.trial,
        trialStartedAt: start,
      );
      expect(e.trialDaysRemaining(now: start.add(const Duration(days: 3))), 4);
    });

    test('trial rolls forward to expired after 7 days', () {
      final e = Entitlements(
        tier: SubscriptionTier.trial,
        trialStartedAt: start,
      );
      final past = e.rolledForward(now: start.add(const Duration(days: 8)));
      expect(past.tier, SubscriptionTier.expired);
    });

    test('subscribed tier exposes high caps and ignores trial countdown', () {
      final e = Entitlements(
        tier: SubscriptionTier.subscribed,
        trialStartedAt: start,
      );
      expect(e.maxConnections, 10);
      expect(e.sneakInPerDayPerContact, greaterThanOrEqualTo(100));
      expect(e.trialDaysRemaining(now: start), 0);
    });

    test('expired tier caps connections to 2 and Sneak In to 1/day', () {
      final e = Entitlements(
        tier: SubscriptionTier.expired,
        trialStartedAt: start,
      );
      expect(e.maxConnections, 2);
      expect(e.sneakInPerDayPerContact, 1);
    });

    test('dailyStrokes tracks tier (trial=50, expired=20, subscribed huge)',
        () {
      final trial = Entitlements(
        tier: SubscriptionTier.trial,
        trialStartedAt: start,
      );
      final expired = Entitlements(
        tier: SubscriptionTier.expired,
        trialStartedAt: start,
      );
      final paid = Entitlements(
        tier: SubscriptionTier.subscribed,
        trialStartedAt: start,
      );
      expect(trial.dailyStrokesPerDay, 50);
      expect(expired.dailyStrokesPerDay, 20);
      expect(paid.dailyStrokesPerDay, greaterThanOrEqualTo(10000));
    });

    test('round-trips through JSON', () {
      final e = Entitlements(
        tier: SubscriptionTier.subscribed,
        trialStartedAt: start,
      );
      final restored = Entitlements.fromJson(e.toJson());
      expect(restored, e);
    });
  });
}
