import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_key_store.dart';
import '../../modes/domain/pulse_mode.dart';
import '../data/iap_diagnostics.dart';
import '../data/iap_service.dart';
import '../domain/entitlements.dart';
import 'iap_providers.dart';

/// Outcome of a user-initiated buy or restore flow, shaped for the paywall
/// to react with a single `switch` and no `default` branch.
enum SubscriptionFlowResult {
  /// The platform queued the operation and Premium is now active.
  success,

  /// The platform queued the operation, but the final state is still
  /// pending (parental approval, SCA, slow tunnel). UI should display a
  /// non-dismissable «processing» indicator until the next event arrives.
  pending,

  /// User dismissed the system sheet. UI stays silent — never snackbar.
  canceled,

  /// Store reports the product is not configured (e.g. App Store Connect
  /// hasn't propagated the SKU yet).
  productUnavailable,

  /// Restore returned nothing usable. UI shows «ничего не найдено».
  nothingToRestore,

  /// Anything else — UI surfaces the underlying [IapErrorCode] via
  /// [SubscriptionController.lastError].
  error,
}

/// Persists [Entitlements] to secure storage and exposes feature-flag style
/// helpers for the rest of the UI to ask "is this allowed?".
///
/// The controller treats secure storage as the source of truth for the
/// trial start date — that anchors the 7-day window across reinstalls of
/// the same vendor binary.
///
/// On top of the local trial it now drives the IAP flow:
///   * subscribes to [IapService.events] for the lifetime of the app;
///   * persists Premium **before** `completePurchase` runs so a crash in
///     the platform layer cannot leave a verified entitlement unrecorded;
///   * schedules a silent `restorePurchases` two seconds after boot to
///     refresh the entitlement against the store without blocking splash;
///   * downgrades the tier back to `expired` when the cached `expiresAt`
///     window has elapsed (spec §7 — locked modes immediately after
///     expiry).
class SubscriptionController extends Notifier<Entitlements> {
  static const _storageKey = 'entitlements.v1';
  static const _qaUnlockAllModes = bool.fromEnvironment(
    'PULSE_QA_UNLOCK_ALL_MODES',
  );

  /// Delay before the silent boot-time restore kicks in so the splash
  /// frame is not contested.
  static const Duration silentRestoreDelay = Duration(seconds: 2);

  /// Maximum time we wait for the store to answer a silent boot-time
  /// restore before falling back to the local cache.
  static const Duration silentRestoreWindow = Duration(seconds: 5);

  StreamSubscription<IapEvent>? _eventsSubscription;
  Timer? _silentRestoreTimer;
  IapErrorCode? _lastError;

  /// Last error code reported by the IAP layer; cleared on every fresh
  /// `buyPremium` / `restorePurchases` call.
  IapErrorCode? get lastError => _lastError;

  @override
  Entitlements build() {
    final fresh = Entitlements.freshTrial();
    unawaited(_bootstrap());
    ref.onDispose(() {
      _silentRestoreTimer?.cancel();
      unawaited(_eventsSubscription?.cancel());
    });
    return fresh;
  }

  Future<void> _bootstrap() async {
    final store = ref.read(secureKeyStoreProvider);
    final service = ref.read(iapServiceProvider);
    service.onEntitlement = _persistEntitlementFromEvent;
    _eventsSubscription = service.events().listen(_onIapEvent);

    final json = await store.readJson(_storageKey);
    if (json == null) {
      final freshState = Entitlements.freshTrial();
      await store.writeJson(_storageKey, freshState.toJson());
      state = freshState;
    } else {
      final loaded = Entitlements.fromJson(json).rolledForward();
      state = loaded;
      await store.writeJson(_storageKey, loaded.toJson());
    }

    _silentRestoreTimer = Timer(silentRestoreDelay, () {
      unawaited(_silentRestore());
    });
  }

  Future<void> _silentRestore() async {
    final service = ref.read(iapServiceProvider);
    try {
      await service.restorePurchases();
    } on Object {
      // Silent flow — boot path stays quiet on store errors and we keep
      // whatever the local cache already produced.
    }
  }

  Future<void> _onIapEvent(IapEvent event) async {
    switch (event) {
      case IapPendingEvent():
      case IapCanceledEvent():
        return;
      case IapErrorEvent(:final code):
        _lastError = code;
      case IapPurchasedEvent():
        // Persistence already ran via the persistor; mirror that into the
        // in-memory state so the UI updates immediately.
        final next = state.copyWith(
          tier: SubscriptionTier.subscribed,
          expiresAt: event.expiresAt,
        );
        state = next;
    }
  }

  Future<void> _persistEntitlementFromEvent(IapPurchasedEvent event) async {
    final store = ref.read(secureKeyStoreProvider);
    final next = state.copyWith(
      tier: SubscriptionTier.subscribed,
      expiresAt: event.expiresAt,
    );
    await store.writeJson(_storageKey, next.toJson());
    await ref.read(iapRepositoryProvider).save(next);
  }

  /// Initiates the paid Premium flow.
  ///
  /// Returns [SubscriptionFlowResult.success] only when the platform has
  /// emitted a verified `purchased` event within the wait window. Use
  /// [lastError] to disambiguate `error`.
  Future<SubscriptionFlowResult> buyPremium({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _lastError = null;
    return _runFlow(
      trigger: () => ref.read(iapServiceProvider).buyPremium(),
      onNotQueued: () {
        _lastError = IapErrorCode.itemUnavailable;
        return SubscriptionFlowResult.productUnavailable;
      },
      onCancel: () => SubscriptionFlowResult.canceled,
      onTimeout: () => SubscriptionFlowResult.pending,
      timeout: timeout,
    );
  }

  /// User-initiated restore flow. Distinguishes «nothing to restore»
  /// (no `purchased`/`restored` arrives before the window) from real
  /// errors so the UI can show the right snackbar.
  Future<SubscriptionFlowResult> restorePurchases({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    _lastError = null;
    return _runFlow(
      trigger: () async {
        await ref.read(iapServiceProvider).restorePurchases();
        return true;
      },
      onNotQueued: () {
        _lastError = IapErrorCode.generic;
        return SubscriptionFlowResult.error;
      },
      onCancel: () => SubscriptionFlowResult.nothingToRestore,
      onTimeout: () => SubscriptionFlowResult.nothingToRestore,
      timeout: timeout,
    );
  }

  /// Subscribes to [IapService.events] **before** invoking [trigger] so a
  /// fast event that arrives synchronously with the platform call cannot
  /// be missed.
  Future<SubscriptionFlowResult> _runFlow({
    required Future<bool> Function() trigger,
    required SubscriptionFlowResult Function() onNotQueued,
    required SubscriptionFlowResult Function() onCancel,
    required SubscriptionFlowResult Function() onTimeout,
    required Duration timeout,
  }) async {
    final service = ref.read(iapServiceProvider);
    final completer = Completer<SubscriptionFlowResult>();
    final sub = service.events().listen((event) {
      if (completer.isCompleted) return;
      switch (event) {
        case IapPendingEvent():
          return;
        case IapPurchasedEvent():
          completer.complete(SubscriptionFlowResult.success);
        case IapCanceledEvent():
          completer.complete(onCancel());
        case IapErrorEvent():
          completer.complete(SubscriptionFlowResult.error);
      }
    });
    try {
      bool queued;
      try {
        queued = await trigger();
      } on Object {
        return onNotQueued();
      }
      if (!queued) return onNotQueued();
      return await completer.future.timeout(timeout, onTimeout: onTimeout);
    } finally {
      await sub.cancel();
    }
  }

  /// True if [mode] is reachable on the current tier.
  bool isModeUnlocked(PulseModeId mode) {
    // Enables exhaustive emulator QA without touching persisted
    // entitlements or weakening release builds. `kDebugMode` stays false in
    // profile/release even if somebody accidentally passes the dart define.
    if (kDebugMode && _qaUnlockAllModes) return true;
    return switch (state.tier) {
      SubscriptionTier.subscribed => true,
      SubscriptionTier.trial => _isStarter(mode),
      SubscriptionTier.expired => _isPostTrialFree(mode),
    };
  }

  /// Hard cap on saved connections for the current tier.
  int get maxConnections => state.maxConnections;

  /// Per-day-per-contact Sneak In quota.
  int get sneakInPerDayPerContact =>
      kDebugMode && _qaUnlockAllModes ? 1000 : state.sneakInPerDayPerContact;

  /// Legacy debug helper used by the foundation PR before IAP wiring
  /// landed. Kept so the existing «Try free» button can still flip the
  /// state in non-store builds (e.g. desktop dev runs); production builds
  /// go through [buyPremium].
  Future<void> markSubscribed() async {
    final next = state.copyWith(tier: SubscriptionTier.subscribed);
    state = next;
    await ref
        .read(secureKeyStoreProvider)
        .writeJson(_storageKey, next.toJson());
  }

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
