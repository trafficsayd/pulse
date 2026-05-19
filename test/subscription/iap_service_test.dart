import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:pulse/features/subscription/data/iap_diagnostics.dart';
import 'package:pulse/features/subscription/data/iap_product_ids.dart';
import 'package:pulse/features/subscription/data/iap_service.dart';

/// Fake [InAppPurchaseAdapter] that records calls and replays canned
/// product / purchase data. Lets us exercise [IapService] end-to-end
/// without touching the real platform billing client.
class _FakeAdapter implements InAppPurchaseAdapter {
  _FakeAdapter({
    this.available = true,
    this.productDetails = const <ProductDetails>[],
  });

  final bool available;
  final List<ProductDetails> productDetails;

  // ignore: close_sinks
  final StreamController<List<PurchaseDetails>> controller =
      StreamController<List<PurchaseDetails>>.broadcast();

  Set<String>? lastQueriedIds;
  PurchaseParam? lastBuyParam;
  int restoreCallCount = 0;
  final List<PurchaseDetails> completed = <PurchaseDetails>[];
  bool completeShouldThrow = false;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    lastQueriedIds = identifiers;
    final ids = identifiers.toList();
    final foundIds = productDetails.map((p) => p.id).toSet();
    return ProductDetailsResponse(
      productDetails: productDetails,
      notFoundIDs: ids.where((id) => !foundIds.contains(id)).toList(),
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
    if (completeShouldThrow) {
      throw StateError('complete failed');
    }
    completed.add(purchase);
  }

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => controller.stream;
}

ProductDetails _premiumProduct({String? id}) => ProductDetails(
      id: id ?? IapProductIds.premiumMonthly,
      title: 'Pulse Premium',
      description: 'Monthly',
      price: r'$1.99',
      rawPrice: 1.99,
      currencyCode: 'USD',
    );

PurchaseDetails _purchase({
  required PurchaseStatus status,
  String? purchaseId = 'tx-1',
  String? productId,
  String localData = _validAndroidLocalData,
  bool pendingComplete = true,
  IAPError? error,
}) {
  final details = PurchaseDetails(
    purchaseID: purchaseId,
    productID: productId ?? IapProductIds.premiumMonthly,
    verificationData: PurchaseVerificationData(
      localVerificationData: localData,
      serverVerificationData: localData,
      source: 'app_store',
    ),
    transactionDate: '0',
    status: status,
  );
  details.pendingCompletePurchase = pendingComplete;
  if (error != null) details.error = error;
  return details;
}

const String _validAndroidLocalData =
    '{"productId":"pulse_premium_monthly","purchaseToken":"abc",'
    '"purchaseTime":1700000000000}';

const String _validIosLocalData =
    // base64 of 0x30 0x82 0x01 0x00 ... padded to be decodable: MIIBA…
    'MIIBAAECAwQF';

/// Drains every queued microtask plus a few event-loop turns so the
/// service has time to deliver async events back to the test.
Future<void> _flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('IapService', () {
    test('isAvailable returns the underlying availability', () async {
      final available = IapService(adapter: _FakeAdapter(available: true));
      final unavailable = IapService(adapter: _FakeAdapter(available: false));
      addTearDown(available.dispose);
      addTearDown(unavailable.dispose);

      expect(await available.isAvailable(), isTrue);
      expect(await unavailable.isAvailable(), isFalse);
    });

    test('fetchPremiumProduct returns null when the store has no product',
        () async {
      final adapter = _FakeAdapter();
      final service = IapService(adapter: adapter);
      addTearDown(service.dispose);

      final product = await service.fetchPremiumProduct();
      expect(product, isNull);
      expect(adapter.lastQueriedIds, equals({IapProductIds.premiumMonthly}));
    });

    test('fetchPremiumProduct returns the matching SKU when present', () async {
      final adapter = _FakeAdapter(productDetails: [_premiumProduct()]);
      final service = IapService(adapter: adapter);
      addTearDown(service.dispose);

      final product = await service.fetchPremiumProduct();
      expect(product?.id, IapProductIds.premiumMonthly);
    });

    test(
      'buyPremium calls buyNonConsumable with the correct PurchaseParam',
      () async {
        final product = _premiumProduct();
        final adapter = _FakeAdapter(productDetails: [product]);
        final service = IapService(adapter: adapter);
        addTearDown(service.dispose);

        final queued = await service.buyPremium();
        expect(queued, isTrue);
        expect(adapter.lastBuyParam?.productDetails.id, product.id);
      },
    );

    test('buyPremium returns false when the product is unavailable', () async {
      final adapter = _FakeAdapter();
      final service = IapService(adapter: adapter);
      addTearDown(service.dispose);

      expect(await service.buyPremium(), isFalse);
      expect(adapter.lastBuyParam, isNull);
    });

    test('restorePurchases triggers the underlying restore', () async {
      final adapter = _FakeAdapter();
      final service = IapService(adapter: adapter);
      addTearDown(service.dispose);

      await service.restorePurchases();
      expect(adapter.restoreCallCount, 1);
    });

    test(
      'Android receipt sanity: missing keys are rejected, valid JSON ok',
      () async {
        final service = IapService(
          adapter: _FakeAdapter(),
          overrideIsIOS: false,
        );
        addTearDown(service.dispose);

        final bad = service.verifyReceipt(
          _purchase(
            status: PurchaseStatus.purchased,
            localData: '{"productId":"x"}',
          ),
        );
        expect(bad.ok, isFalse);

        final ok = service.verifyReceipt(
          _purchase(status: PurchaseStatus.purchased),
        );
        expect(ok.ok, isTrue);
        expect(ok.expiresAt, isNotNull);
        expect(ok.purchaseDate, isNotNull);
      },
    );

    test('iOS receipt sanity rejects non-PKCS#7 base64', () async {
      final service = IapService(adapter: _FakeAdapter(), overrideIsIOS: true);
      addTearDown(service.dispose);

      final bad = service.verifyReceipt(
        _purchase(
          status: PurchaseStatus.purchased,
          localData: base64.encode([1, 2, 3, 4]),
        ),
      );
      expect(bad.ok, isFalse);

      final ok = service.verifyReceipt(
        _purchase(
          status: PurchaseStatus.purchased,
          localData: _validIosLocalData,
        ),
      );
      expect(ok.ok, isTrue);
      // iOS does not give us an expiry locally.
      expect(ok.expiresAt, isNull);
    });

    test('emits purchased event after a valid Android purchase', () async {
      final adapter = _FakeAdapter();
      final service = IapService(adapter: adapter, overrideIsIOS: false);
      addTearDown(service.dispose);

      final collected = <IapEvent>[];
      final sub = service.events().listen(collected.add);
      addTearDown(sub.cancel);

      adapter.controller.add([
        _purchase(status: PurchaseStatus.purchased),
      ]);
      await _flush();
      expect(collected, hasLength(1));
      final event = collected.single;
      expect(event, isA<IapPurchasedEvent>());
      expect((event as IapPurchasedEvent).restored, isFalse);
      expect(event.expiresAt, isNotNull);
      // completePurchase was invoked.
      expect(adapter.completed, hasLength(1));
    });

    test(
      'persists entitlement before completePurchase even if complete throws',
      () async {
        final adapter = _FakeAdapter()..completeShouldThrow = true;
        final persisted = <IapPurchasedEvent>[];
        final service = IapService(
          adapter: adapter,
          overrideIsIOS: false,
          onEntitlement: (e) async => persisted.add(e),
        );
        addTearDown(service.dispose);

        final collected = <IapEvent>[];
        final sub = service.events().listen(collected.add);
        addTearDown(sub.cancel);

        adapter.controller.add([
          _purchase(status: PurchaseStatus.purchased),
        ]);
        await _flush();
        // Persisted exactly once, before completePurchase blew up.
        expect(persisted, hasLength(1));
        // The success event still fired even though completePurchase threw.
        expect(collected.whereType<IapPurchasedEvent>(), hasLength(1));
      },
    );

    test('error event classifies platform error codes', () async {
      final adapter = _FakeAdapter();
      final service = IapService(adapter: adapter, overrideIsIOS: false);
      addTearDown(service.dispose);

      final collected = <IapEvent>[];
      final sub = service.events().listen(collected.add);
      addTearDown(sub.cancel);

      adapter.controller.add([
        _purchase(
          status: PurchaseStatus.error,
          purchaseId: '',
          error: IAPError(
            source: 'app_store',
            code: 'payment_not_allowed',
            message: 'parental controls',
          ),
        ),
      ]);
      await _flush();
      expect(collected, hasLength(1));
      final event = collected.single;
      expect(event, isA<IapErrorEvent>());
      expect((event as IapErrorEvent).code, IapErrorCode.paymentNotAllowed);
    });

    test('canceled status surfaces as IapCanceledEvent', () async {
      final adapter = _FakeAdapter();
      final service = IapService(adapter: adapter, overrideIsIOS: false);
      addTearDown(service.dispose);

      final collected = <IapEvent>[];
      final sub = service.events().listen(collected.add);
      addTearDown(sub.cancel);

      adapter.controller.add([
        _purchase(
          status: PurchaseStatus.canceled,
          purchaseId: null,
        ),
      ]);
      await _flush();
      expect(collected.single, isA<IapCanceledEvent>());
    });

    test('events for other SKUs are ignored', () async {
      final adapter = _FakeAdapter();
      final service = IapService(adapter: adapter, overrideIsIOS: false);
      addTearDown(service.dispose);

      final received = <IapEvent>[];
      service.events().listen(received.add);

      adapter.controller.add([
        _purchase(
          status: PurchaseStatus.purchased,
          productId: 'some_other_sku',
        ),
      ]);
      await _flush();
      expect(received, isEmpty);
    });

    test('purchaseUpdates view maps events to PurchaseStatus', () async {
      final adapter = _FakeAdapter();
      final service = IapService(adapter: adapter, overrideIsIOS: false);
      addTearDown(service.dispose);

      final statuses = <PurchaseStatus>[];
      final sub = service.purchaseUpdates().listen(statuses.add);
      addTearDown(sub.cancel);

      adapter.controller.add([
        _purchase(status: PurchaseStatus.pending, purchaseId: null),
      ]);
      await _flush();
      expect(statuses.last, PurchaseStatus.pending);

      adapter.controller.add([
        _purchase(status: PurchaseStatus.purchased),
      ]);
      await _flush();
      expect(statuses.last, PurchaseStatus.purchased);
    });
  });

  group('classifyIapError', () {
    test('maps known codes to enum buckets', () {
      expect(
        classifyIapError('payment_not_allowed'),
        IapErrorCode.paymentNotAllowed,
      );
      expect(
        classifyIapError('paymentInvalid'),
        IapErrorCode.paymentInvalid,
      );
      expect(
        classifyIapError('BILLING_UNAVAILABLE'),
        IapErrorCode.billingUnavailable,
      );
      expect(
        classifyIapError('item_unavailable'),
        IapErrorCode.itemUnavailable,
      );
      expect(classifyIapError(null), IapErrorCode.generic);
      expect(classifyIapError('???'), IapErrorCode.generic);
    });
  });
}
