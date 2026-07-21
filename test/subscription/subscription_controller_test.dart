import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:pulse/core/storage/secure_key_store.dart';
import 'package:pulse/features/subscription/application/iap_providers.dart';
import 'package:pulse/features/subscription/application/subscription_controller.dart';
import 'package:pulse/features/subscription/data/iap_diagnostics.dart';
import 'package:pulse/features/subscription/data/iap_product_ids.dart';
import 'package:pulse/features/subscription/data/iap_service.dart';
import 'package:pulse/features/subscription/domain/entitlements.dart';

/// In-memory [SecureKeyStore] used by the controller round-trip tests.
class _MemorySecureKeyStore extends SecureKeyStore {
  _MemorySecureKeyStore({Map<String, String>? seed})
      : _map = Map<String, String>.from(seed ?? const <String, String>{});

  final Map<String, String> _map;

  @override
  Future<void> writeString(String key, String value) async {
    _map[key] = value;
  }

  @override
  Future<String?> readString(String key) async => _map[key];

  @override
  Future<void> delete(String key) async {
    _map.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _map.clear();
  }
}

/// Adapter used by the controller's `IapService`. Lets each test push the
/// purchase events it wants while inspecting calls to `restorePurchases`
/// and `buyNonConsumable`.
class _FakeAdapter implements InAppPurchaseAdapter {
  // ignore: close_sinks
  final StreamController<List<PurchaseDetails>> controller =
      StreamController<List<PurchaseDetails>>.broadcast();

  ProductDetails? product;
  bool storeAvailable = true;
  int restoreCallCount = 0;
  PurchaseParam? lastBuyParam;
  final List<PurchaseDetails> completed = <PurchaseDetails>[];

  @override
  Future<bool> isAvailable() async => storeAvailable;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    final p = product;
    return ProductDetailsResponse(
      productDetails: p == null ? <ProductDetails>[] : <ProductDetails>[p],
      notFoundIDs: p == null ? identifiers.toList() : <String>[],
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    lastBuyParam = purchaseParam;
    return true;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreCallCount += 1;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase);
  }

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => controller.stream;
}

ProductDetails _premiumProduct() => ProductDetails(
      id: IapProductIds.premiumMonthly,
      title: 'Pulse Premium',
      description: 'Monthly',
      price: r'$1.99',
      rawPrice: 1.99,
      currencyCode: 'USD',
    );

PurchaseDetails _purchase({
  required PurchaseStatus status,
  String? purchaseId = 'tx-1',
  String? localData,
  IAPError? error,
}) {
  final blob = localData ?? _validAndroid();
  final details = PurchaseDetails(
    purchaseID: purchaseId,
    productID: IapProductIds.premiumMonthly,
    verificationData: PurchaseVerificationData(
      localVerificationData: blob,
      serverVerificationData: blob,
      source: 'play_store',
    ),
    transactionDate: '0',
    status: status,
  );
  details.pendingCompletePurchase = true;
  if (error != null) details.error = error;
  return details;
}

/// Synthesises a fresh Android-shaped local verification blob whose
/// `purchaseTime` is "now". Keeping it current means the controller's
/// expiry math (purchaseTime + 31d) is comfortably in the future and the
/// second-container reboot test cannot accidentally trip the
/// `rolledForward` lifecycle check.
String _validAndroid() {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  return '{"productId":"pulse_premium_monthly","purchaseToken":"abc",'
      '"purchaseTime":$now}';
}

ProviderContainer _container({
  required _MemorySecureKeyStore store,
  required _FakeAdapter adapter,
}) {
  final container = ProviderContainer(
    overrides: [
      secureKeyStoreProvider.overrideWithValue(store),
      iapServiceProvider.overrideWith((ref) {
        final service = IapService(adapter: adapter, overrideIsIOS: false);
        ref.onDispose(service.dispose);
        return service;
      }),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _flush() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SubscriptionController', () {
    test('boot path lands on a trial when no entitlement is persisted',
        () async {
      final store = _MemorySecureKeyStore();
      final adapter = _FakeAdapter()..product = _premiumProduct();
      final container = _container(store: store, adapter: adapter);

      // Reading the provider triggers `build()` which schedules bootstrap.
      final entitlements = container.read(subscriptionControllerProvider);
      expect(entitlements.tier, SubscriptionTier.trial);
      await _flush();

      final loaded = container.read(subscriptionControllerProvider);
      expect(loaded.tier, SubscriptionTier.trial);
      // Trial state is persisted.
      expect(await store.readString('entitlements.v1'), isNotNull);
    });

    test('restored purchase event upgrades trial → subscribed', () async {
      final store = _MemorySecureKeyStore();
      final adapter = _FakeAdapter()..product = _premiumProduct();
      final container = _container(store: store, adapter: adapter);
      container.read(subscriptionControllerProvider);
      await _flush();

      adapter.controller.add(<PurchaseDetails>[
        _purchase(status: PurchaseStatus.restored),
      ]);
      await _flush();

      final upgraded = container.read(subscriptionControllerProvider);
      expect(upgraded.tier, SubscriptionTier.subscribed);
      expect(upgraded.expiresAt, isNotNull);

      // Persisted to the same key so the next launch boots straight into
      // subscribed.
      final next = _container(
        store: _MemorySecureKeyStore(seed: {...store._map}),
        adapter: _FakeAdapter(),
      );
      next.read(subscriptionControllerProvider);
      await _flush();
      expect(
        next.read(subscriptionControllerProvider).tier,
        SubscriptionTier.subscribed,
      );
    });

    test('restore-failure leaves the trial state untouched', () async {
      final store = _MemorySecureKeyStore();
      final adapter = _FakeAdapter()..product = _premiumProduct();
      final container = _container(store: store, adapter: adapter);
      container.read(subscriptionControllerProvider);
      await _flush();

      final notifier = container.read(subscriptionControllerProvider.notifier);
      final result = await notifier.restorePurchases(
        timeout: const Duration(milliseconds: 200),
      );
      expect(result, SubscriptionFlowResult.nothingToRestore);
      expect(
        container.read(subscriptionControllerProvider).tier,
        SubscriptionTier.trial,
      );
    });

    test('buyPremium reports productUnavailable when the SKU is missing',
        () async {
      final store = _MemorySecureKeyStore();
      final adapter = _FakeAdapter(); // no product configured
      final container = _container(store: store, adapter: adapter);
      container.read(subscriptionControllerProvider);
      await _flush();

      final notifier = container.read(subscriptionControllerProvider.notifier);
      final result = await notifier.buyPremium(
        timeout: const Duration(milliseconds: 200),
      );
      expect(result, SubscriptionFlowResult.productUnavailable);
      expect(notifier.lastError, IapErrorCode.itemUnavailable);
    });

    test('buyPremium → purchased event sets tier=subscribed and persists',
        () async {
      final store = _MemorySecureKeyStore();
      final adapter = _FakeAdapter()..product = _premiumProduct();
      final container = _container(store: store, adapter: adapter);
      container.read(subscriptionControllerProvider);
      await _flush();

      final notifier = container.read(subscriptionControllerProvider.notifier);
      final flow = notifier.buyPremium(
        timeout: const Duration(seconds: 2),
      );
      // Allow the trigger to schedule, then push a successful event.
      await _flush();
      adapter.controller.add(<PurchaseDetails>[
        _purchase(status: PurchaseStatus.purchased),
      ]);
      final result = await flow;

      expect(result, SubscriptionFlowResult.success);
      expect(
        container.read(subscriptionControllerProvider).tier,
        SubscriptionTier.subscribed,
      );
      // Persisted before completePurchase ran, but completePurchase also
      // succeeded so it should be in `completed`.
      expect(adapter.completed, hasLength(1));
      expect(await store.readString('entitlements.v1'), isNotNull);
    });

    test('error event surfaces SubscriptionFlowResult.error + lastError',
        () async {
      final store = _MemorySecureKeyStore();
      final adapter = _FakeAdapter()..product = _premiumProduct();
      final container = _container(store: store, adapter: adapter);
      container.read(subscriptionControllerProvider);
      await _flush();

      final notifier = container.read(subscriptionControllerProvider.notifier);
      final flow = notifier.buyPremium(
        timeout: const Duration(seconds: 2),
      );
      await _flush();
      adapter.controller.add(<PurchaseDetails>[
        _purchase(
          status: PurchaseStatus.error,
          purchaseId: '',
          error: IAPError(
            source: 'play_store',
            code: 'BILLING_UNAVAILABLE',
            message: 'no play store',
          ),
        ),
      ]);
      final result = await flow;
      expect(result, SubscriptionFlowResult.error);
      expect(notifier.lastError, IapErrorCode.billingUnavailable);
    });

    test(
        'persisted subscription with elapsed expiresAt rolls forward '
        'to expired on boot', () async {
      // Seed the store with a subscription that ended yesterday.
      final yesterday =
          DateTime.now().toUtc().subtract(const Duration(days: 1));
      final seed = Entitlements(
        tier: SubscriptionTier.subscribed,
        trialStartedAt:
            DateTime.now().toUtc().subtract(const Duration(days: 60)),
        expiresAt: yesterday,
      );
      final store = _MemorySecureKeyStore();
      await store.writeJson('entitlements.v1', seed.toJson());

      final container = _container(
        store: store,
        adapter: _FakeAdapter()..product = _premiumProduct(),
      );
      container.read(subscriptionControllerProvider);
      await _flush();

      final loaded = container.read(subscriptionControllerProvider);
      expect(loaded.tier, SubscriptionTier.expired);
    });

    test('persistence round-trip through Entitlements JSON survives', () {
      final original = Entitlements(
        tier: SubscriptionTier.subscribed,
        trialStartedAt: DateTime.utc(2024, 6, 1, 12),
        expiresAt: DateTime.utc(2024, 7, 1, 12),
      );
      final restored = Entitlements.fromJson(original.toJson());
      expect(restored.tier, original.tier);
      expect(restored.trialStartedAt, original.trialStartedAt);
      expect(restored.expiresAt, original.expiresAt);
    });
  });
}
