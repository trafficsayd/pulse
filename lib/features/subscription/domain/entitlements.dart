import 'package:meta/meta.dart';

/// What the user is currently allowed to do.
///
/// Pulse has three tiers driven entirely by local state:
///
/// - [SubscriptionTier.trial]      — first 7 days; 7 starter modes; up to 3
///                                   saved connections; 1 Sneak In per
///                                   contact per day.
/// - [SubscriptionTier.expired]    — trial ended without a subscription;
///                                   only Tap-Tap and Half-Heart;
///                                   up to 2 saved connections.
/// - [SubscriptionTier.subscribed] — paid; everything unlocked, up to 10
///                                   saved connections.
enum SubscriptionTier { trial, expired, subscribed }

@immutable
class Entitlements {
  const Entitlements({
    required this.tier,
    required this.trialStartedAt,
    this.expiresAt,
  });

  final SubscriptionTier tier;
  final DateTime trialStartedAt;

  /// Local approximation of the subscription expiry, in UTC.
  ///
  /// On Android this is derived from the receipt's `purchaseTime` plus the
  /// monthly billing window so the client can lock features back down
  /// without a network call. On iOS we leave this null until server-side
  /// receipt validation lands — Apple does not expose an expiry date on
  /// the local PKCS#7 receipt.
  final DateTime? expiresAt;

  static const trialDuration = Duration(days: 7);

  /// Initial entitlements for a brand-new install.
  factory Entitlements.freshTrial({DateTime? now}) {
    return Entitlements(
      tier: SubscriptionTier.trial,
      trialStartedAt: now ?? DateTime.now(),
    );
  }

  /// Whole days remaining in the trial. Returns 0 once the trial has expired.
  int trialDaysRemaining({DateTime? now}) {
    if (tier != SubscriptionTier.trial) return 0;
    final endsAt = trialStartedAt.add(trialDuration);
    final remaining = endsAt.difference(now ?? DateTime.now());
    if (remaining.isNegative) return 0;
    // Round up so "23h59m left" still shows as 1 day, not 0.
    return remaining.inHours ~/ 24 + (remaining.inHours % 24 == 0 ? 0 : 1);
  }

  /// Re-evaluate the tier based on elapsed time. Call this on app start and
  /// whenever the trial banner is shown.
  Entitlements rolledForward({DateTime? now}) {
    final at = now ?? DateTime.now();
    if (tier == SubscriptionTier.subscribed &&
        expiresAt != null &&
        !at.isBefore(expiresAt!)) {
      return Entitlements(
        tier: SubscriptionTier.expired,
        trialStartedAt: trialStartedAt,
      );
    }
    if (tier == SubscriptionTier.trial && trialDaysRemaining(now: at) <= 0) {
      return Entitlements(
        tier: SubscriptionTier.expired,
        trialStartedAt: trialStartedAt,
        expiresAt: expiresAt,
      );
    }
    return this;
  }

  /// Maximum number of saved connections this tier permits.
  int get maxConnections => switch (tier) {
        SubscriptionTier.subscribed => 10,
        SubscriptionTier.trial => 3,
        SubscriptionTier.expired => 2,
      };

  /// Per-day Sneak In quota per individual contact.
  int get sneakInPerDayPerContact => switch (tier) {
        SubscriptionTier.subscribed => 1000, // de-facto unlimited
        SubscriptionTier.trial || SubscriptionTier.expired => 1,
      };

  Map<String, Object?> toJson() => {
        'tier': tier.name,
        'trialStartedAt': trialStartedAt.toIso8601String(),
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
      };

  factory Entitlements.fromJson(Map<String, Object?> json) {
    final expiresRaw = json['expiresAt'];
    return Entitlements(
      tier: SubscriptionTier.values.firstWhere(
        (t) => t.name == json['tier'],
        orElse: () => SubscriptionTier.trial,
      ),
      trialStartedAt: DateTime.parse(json['trialStartedAt']! as String),
      expiresAt: expiresRaw is String ? DateTime.parse(expiresRaw) : null,
    );
  }

  Entitlements copyWith({
    SubscriptionTier? tier,
    DateTime? trialStartedAt,
    DateTime? expiresAt,
    bool clearExpiry = false,
  }) =>
      Entitlements(
        tier: tier ?? this.tier,
        trialStartedAt: trialStartedAt ?? this.trialStartedAt,
        expiresAt: clearExpiry ? null : (expiresAt ?? this.expiresAt),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Entitlements &&
          tier == other.tier &&
          trialStartedAt == other.trialStartedAt &&
          expiresAt == other.expiresAt);

  @override
  int get hashCode => Object.hash(tier, trialStartedAt, expiresAt);
}
