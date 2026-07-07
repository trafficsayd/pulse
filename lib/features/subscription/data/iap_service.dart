import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:meta/meta.dart';

import 'iap_diagnostics.dart';
import 'iap_product_ids.dart';

/// Thin adapter around [InAppPurchase] so the [IapService] can talk to a
/// concrete implementation in production and a fake in unit tests.
///
/// Only the surface area Pulse needs is exposed — by avoiding a wholesale
/// re-export of `InAppPurchase` we get a small, intention-revealing API and
/// keep `flutter_test` happy on hosts where the underlying plugin has no
/// platform binding.
abstract class InAppPurchaseAdapter {
  Future<bool> isAvailable();

  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers);

  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam});

  Future<void> restorePurchases({String? applicationUserName});

  Future<void> completePurchase(PurchaseDetails purchase);

  Stream<List<PurchaseDetails>> get purchaseStream;
}

/// Default adapter that forwards every call to `InAppPurchase.instance`. Kept
/// dead simple so the production path is essentially a pass-through.
///
/// On platforms where the billing plugin is not registered (e.g. web),
/// [_inner] will be `null` and every method will behave as if the store is
/// unavailable.
class DefaultInAppPurchaseAdapter implements InAppPurchaseAdapter {
  DefaultInAppPurchaseAdapter([InAppPurchase? inner])
      : _inner = _resolve(inner);

  static InAppPurchase? _resolve(InAppPurchase? explicit) {
    if (explicit != null) return explicit;
    if (kIsWeb) return null;
    try {
      return InAppPurchase.instance;
    } on Object {
      return null;
    }
  }

  final InAppPurchase? _inner;

  @override
  Future<bool> isAvailable() => _inner?.isAvailable() ?? Future.value(false);

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) =>
      _inner?.queryProductDetails(identifiers) ??
      Future.value(ProductDetailsResponse(
        productDetails: const [],
        notFoundIDs: identifiers.toList(),
        error: null,
      ));

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) =>
      _inner?.buyNonConsumable(purchaseParam: purchaseParam) ??
      Future.value(false);

  @override
  Future<void> restorePurchases({String? applicationUserName}) =>
      _inner?.restorePurchases(applicationUserName: applicationUserName) ??
      Future.value();

  @override
  Future<void> completePurchase(PurchaseDetails purchase) =>
      _inner?.completePurchase(purchase) ?? Future.value();

  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      _inner?.purchaseStream ?? const Stream.empty();
}

/// Outcome of a single purchase / restore round trip surfaced to the
/// controller and (transitively) the UI. Designed to be exhaustive so the
/// presentation layer can `switch` on it without a default branch.
@immutable
sealed class IapEvent {
  const IapEvent();
}

class IapPendingEvent extends IapEvent {
  const IapPendingEvent();
}

class IapPurchasedEvent extends IapEvent {
  const IapPurchasedEvent({
    required this.productId,
    required this.purchaseId,
    required this.purchaseDate,
    required this.expiresAt,
    required this.restored,
  });

  final String productId;
  final String purchaseId;

  /// When the platform billing layer registered the purchase. Always UTC.
  final DateTime purchaseDate;

  /// Local approximation of the subscription expiry; `null` when the
  /// platform did not give us a deterministic answer (e.g. iOS receipts).
  final DateTime? expiresAt;

  /// `true` when the platform redelivered an existing purchase (i.e. a
  /// successful Restore flow), `false` when this is a fresh purchase.
  final bool restored;
}

class IapErrorEvent extends IapEvent {
  const IapErrorEvent({required this.code, required this.rawCode});

  final IapErrorCode code;
  final String? rawCode;
}

class IapCanceledEvent extends IapEvent {
  const IapCanceledEvent();
}

/// Called by the service immediately after a successful purchase / restore
/// passes local sanity but before [InAppPurchaseAdapter.completePurchase] is
/// invoked. This lets the upstream controller persist the entitlement so an
/// unlucky `completePurchase` crash never leaves the user without their
/// subscription — the platform will simply redeliver the receipt on the
/// next launch and `_handleBatch` will run again.
typedef IapEntitlementPersistor = Future<void> Function(IapPurchasedEvent);

/// High-level API for Pulse's only IAP product — the «Pulse Premium» monthly
/// subscription.
///
/// The service:
///   * answers «is the store usable on this device?»;
///   * fetches product metadata so the paywall can show real prices later;
///   * kicks off `buyNonConsumable` / `restorePurchases` flows (subscriptions
///     in `in_app_purchase` ride on the non-consumable API);
///   * subscribes to the underlying `purchaseStream` **at construction
///     time** so a redelivery that arrives before the paywall is opened is
///     never missed;
///   * normalises every purchase into a single [IapEvent] so the controller
///     layer doesn't have to know about `PurchaseDetails`;
///   * runs a platform-aware sanity pass on the receipt (PKCS#7 marker on
///     iOS, JSON shape on Android) before yielding success.
class IapService {
  IapService({
    InAppPurchaseAdapter? adapter,
    IapEntitlementPersistor? onEntitlement,
    @visibleForTesting bool? overrideIsIOS,
  })  : _adapter = adapter ?? DefaultInAppPurchaseAdapter(),
        _onEntitlement = onEntitlement,
        _overrideIsIOS = overrideIsIOS {
    _subscription = _adapter.purchaseStream.listen(
      _handleBatch,
      onError: (Object error, StackTrace _) {
        _events.add(IapErrorEvent(
          code: classifyIapError(error.toString()),
          rawCode: error.toString(),
        ));
      },
    );
  }

  final InAppPurchaseAdapter _adapter;
  IapEntitlementPersistor? _onEntitlement;
  final bool? _overrideIsIOS;
  final StreamController<IapEvent> _events =
      StreamController<IapEvent>.broadcast();
  late final StreamSubscription<List<PurchaseDetails>> _subscription;

  /// Subscription-window heuristic used to derive a local `expiresAt`.
  /// Apple/Google honour the real billing window themselves; we only use
  /// this to gate features client-side between refreshes.
  static const Duration monthlyBillingWindow = Duration(days: 31);

  bool get _isIOS {
    if (_overrideIsIOS != null) return _overrideIsIOS;
    if (kIsWeb) return false;
    // ignore: avoid_dynamic_calls
    return defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Registers (or replaces) the persistor invoked before
  /// [InAppPurchaseAdapter.completePurchase] runs on every successful
  /// receipt. Returning `null` clears it.
  set onEntitlement(IapEntitlementPersistor? persistor) {
    _onEntitlement = persistor;
  }

  /// True when the underlying platform billing client is reachable.
  Future<bool> isAvailable() => _adapter.isAvailable();

  /// Looks up the Pulse Premium SKU on the store.
  ///
  /// Returns `null` when the store reports the product as unknown (e.g. the
  /// SKU is not yet configured in App Store Connect / Play Console).
  Future<ProductDetails?> fetchPremiumProduct() async {
    final response = await _adapter.queryProductDetails(IapProductIds.all());
    if (response.productDetails.isEmpty) return null;
    for (final p in response.productDetails) {
      if (p.id == IapProductIds.premiumMonthly) return p;
    }
    return null;
  }

  /// Initiates the purchase flow for Pulse Premium.
  ///
  /// Returns `true` if the request was queued on the platform; the actual
  /// purchase outcome arrives asynchronously through [events].
  Future<bool> buyPremium() async {
    final product = await fetchPremiumProduct();
    if (product == null) return false;
    final param = PurchaseParam(productDetails: product);
    return _adapter.buyNonConsumable(purchaseParam: param);
  }

  /// Re-asks the store to redeliver any active entitlements for the current
  /// account. Results are delivered asynchronously through [events].
  Future<void> restorePurchases() => _adapter.restorePurchases();

  /// Stream of high-level purchase events for the Pulse Premium SKU.
  Stream<IapEvent> events() => _events.stream;

  /// Spec-compatible view of [events] that flattens every event into the
  /// raw `PurchaseStatus` it originated from. Kept for the controller and
  /// for tests that only need to assert «something happened».
  Stream<PurchaseStatus> purchaseUpdates() => _events.stream.map(_toStatus);

  static PurchaseStatus _toStatus(IapEvent event) => switch (event) {
        IapPendingEvent() => PurchaseStatus.pending,
        IapPurchasedEvent(restored: true) => PurchaseStatus.restored,
        IapPurchasedEvent() => PurchaseStatus.purchased,
        IapErrorEvent() => PurchaseStatus.error,
        IapCanceledEvent() => PurchaseStatus.canceled,
      };

  /// Drops platform listeners and closes the broadcast controller. Called by
  /// the Riverpod provider when the service goes out of scope.
  Future<void> dispose() async {
    await _subscription.cancel();
    await _events.close();
  }

  /// Local sanity check on the platform receipt before we trust it as a
  /// real entitlement. Returns the derived `expiresAt` on success (which
  /// may be `null` on iOS) or `null` if the receipt fails sanity.
  ({bool ok, DateTime? expiresAt, DateTime? purchaseDate}) verifyReceipt(
    PurchaseDetails purchase,
  ) {
    if (purchase.purchaseID == null || purchase.purchaseID!.isEmpty) {
      return (ok: false, expiresAt: null, purchaseDate: null);
    }
    final raw = purchase.verificationData.localVerificationData;
    if (raw.isEmpty) {
      return (ok: false, expiresAt: null, purchaseDate: null);
    }

    if (_isIOS) {
      return _verifyIosReceipt(raw);
    }
    return _verifyAndroidReceipt(raw);
  }

  ({bool ok, DateTime? expiresAt, DateTime? purchaseDate}) _verifyIosReceipt(
    String raw,
  ) {
    // App Store receipts are base64-encoded PKCS#7 envelopes. The DER
    // signature always starts with the SEQUENCE tag `0x30 0x82`, which in
    // base64 becomes the literal `MII…` prefix. Anything else is bogus.
    if (!raw.startsWith('MII')) {
      return (ok: false, expiresAt: null, purchaseDate: null);
    }
    try {
      final bytes = base64.decode(raw);
      if (bytes.length < 4 || bytes[0] != 0x30 || bytes[1] != 0x82) {
        return (ok: false, expiresAt: null, purchaseDate: null);
      }
    } on FormatException {
      return (ok: false, expiresAt: null, purchaseDate: null);
    }
    // Apple does not expose the expiry in the local receipt; leave it
    // null and rely on server-side validation when it lands.
    return (ok: true, expiresAt: null, purchaseDate: null);
  }

  ({bool ok, DateTime? expiresAt, DateTime? purchaseDate})
      _verifyAndroidReceipt(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return (ok: false, expiresAt: null, purchaseDate: null);
      }
      final productId = decoded['productId'];
      final purchaseToken = decoded['purchaseToken'];
      final purchaseTime = decoded['purchaseTime'];
      if (productId is! String || productId.isEmpty) {
        return (ok: false, expiresAt: null, purchaseDate: null);
      }
      if (purchaseToken is! String || purchaseToken.isEmpty) {
        return (ok: false, expiresAt: null, purchaseDate: null);
      }
      if (purchaseTime is! int && purchaseTime is! num) {
        return (ok: false, expiresAt: null, purchaseDate: null);
      }
      final ts = (purchaseTime as num).toInt();
      final date = DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true);
      return (
        ok: true,
        expiresAt: date.add(monthlyBillingWindow),
        purchaseDate: date,
      );
    } on FormatException {
      return (ok: false, expiresAt: null, purchaseDate: null);
    }
  }

  Future<void> _handleBatch(List<PurchaseDetails> batch) async {
    for (final purchase in batch) {
      if (purchase.productID != IapProductIds.premiumMonthly) continue;
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _events.add(const IapPendingEvent());
        case PurchaseStatus.canceled:
          _events.add(const IapCanceledEvent());
        case PurchaseStatus.error:
          _events.add(IapErrorEvent(
            code: classifyIapError(purchase.error?.code),
            rawCode: purchase.error?.code,
          ));
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _deliverEntitlement(purchase);
      }
    }
  }

  Future<void> _deliverEntitlement(PurchaseDetails purchase) async {
    final result = verifyReceipt(purchase);
    if (!result.ok) {
      _events.add(const IapErrorEvent(
        code: IapErrorCode.generic,
        rawCode: 'receipt_sanity_failed',
      ));
      return;
    }
    final event = IapPurchasedEvent(
      productId: purchase.productID,
      purchaseId: purchase.purchaseID ?? '',
      purchaseDate: result.purchaseDate ?? DateTime.now().toUtc(),
      expiresAt: result.expiresAt,
      restored: purchase.status == PurchaseStatus.restored,
    );
    // Persist FIRST so that a crash inside `completePurchase` cannot leave
    // a verified entitlement unrecorded.
    final persistor = _onEntitlement;
    if (persistor != null) {
      try {
        await persistor(event);
      } on Object {
        // Persistence failures are surfaced as errors but we still
        // emit the success event so the UI reacts; the platform will
        // redeliver the receipt on next launch and we will retry.
        _events.add(const IapErrorEvent(
          code: IapErrorCode.generic,
          rawCode: 'entitlement_persist_failed',
        ));
      }
    }
    if (purchase.pendingCompletePurchase) {
      try {
        await _adapter.completePurchase(purchase);
      } on Object {
        // Swallowing here is deliberate — `completePurchase` failing does
        // not invalidate the entitlement and the platform will redeliver
        // the purchase on next launch.
      }
    }
    _events.add(event);
  }
}
