import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_key_store.dart';
import '../../modes/domain/pulse_mode.dart';
import '../domain/entitlements.dart';

/// Persists [Entitlements] to secure storage and exposes feature-flag style
/// helpers for the rest of the UI to ask "is this allowed?".
///
/// The controller treats secure storage as the source of truth for the
/// trial start date — that anchors the 7-day window across reinstalls of
/// the same vendor binary.
class SubscriptionController extends Notifier<Entitlements> {
  static const _storageKey = 'entitlements.v1';

  @override
  Entitlements build() {
    _bootstrap();
    return Entitlements.freshTrial();
  }

  Future<void> _bootstrap() async {
    final store = ref.read(secureKeyStoreProvider);
    final json = await store.readJson(_storageKey);
    if (json == null) {
      final fresh = Entitlements.freshTrial();
      await store.writeJson(_storageKey, fresh.toJson());
      state = fresh;
      return;
    }
    final loaded = Entitlements.fromJson(json).rolledForward();
    state = loaded;
    // Persist any tier roll-forward so the next launch is consistent.
    await store.writeJson(_storageKey, loaded.toJson());
  }

  Future<void> markSubscribed() async {
    final next = state.copyWith(tier: SubscriptionTier.subscribed);
    state = next;
    await ref
        .read(secureKeyStoreProvider)
        .writeJson(_storageKey, next.toJson());
  }

  /// True if [mode] is reachable on the current tier.
  bool isModeUnlocked(PulseModeId mode) {
    return switch (state.tier) {
      SubscriptionTier.subscribed => true,
      SubscriptionTier.trial => _isStarter(mode),
      SubscriptionTier.expired => _isPostTrialFree(mode),
    };
  }

  /// Hard cap on saved connections for the current tier.
  int get maxConnections => state.maxConnections;

  /// Per-day-per-contact Sneak In quota.
  int get sneakInPerDayPerContact => state.sneakInPerDayPerContact;

  bool _isStarter(PulseModeId mode) => switch (mode) {
        PulseModeId.tapTap ||
        PulseModeId.halfHeart ||
        PulseModeId.candle ||
        PulseModeId.whisper ||
        PulseModeId.bell ||
        PulseModeId.ray ||
        PulseModeId.constellation =>
          true,
        _ => false,
      };

  /// After the trial expires without a subscription, only Tap-Tap and
  /// Half-Heart remain unlocked, per spec section 9.
  bool _isPostTrialFree(PulseModeId mode) =>
      mode == PulseModeId.tapTap || mode == PulseModeId.halfHeart;
}

final subscriptionControllerProvider =
    NotifierProvider<SubscriptionController, Entitlements>(
        SubscriptionController.new);
