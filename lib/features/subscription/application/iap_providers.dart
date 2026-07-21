import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/storage/secure_key_store.dart';
import '../data/iap_repository.dart';
import '../data/iap_service.dart';

/// True when the platform supports In-App Purchase (iOS/Android only).
bool get _iapSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

/// Singleton [IapService] used by [SubscriptionController] and watched by
/// the paywall UI.
///
/// Marked `keepAlive`/auto-disposed via [Ref.onDispose] so the underlying
/// platform listener is kept up for the whole app lifetime — Pulse needs
/// to react to a redelivery that arrives **before** the paywall is opened.
///
/// On desktop platforms (Windows/macOS/Linux) where `in_app_purchase` has
/// no platform backend, the provider returns a no-op service so the app
/// boots without crashing.
final iapServiceProvider = Provider<IapService>((ref) {
  if (!_iapSupported) {
    // Desktop / web: IAP unavailable, use a no-op service.
    return IapService(
      adapter: _NoopInAppPurchaseAdapter(),
    );
  }
  final service = IapService();
  ref.onDispose(() async {
    await service.dispose();
  });
  return service;
});

/// Persistence facade over [SecureKeyStore] for the IAP entitlement cache.
final iapRepositoryProvider = Provider<IapRepository>((ref) {
  final store = ref.watch(secureKeyStoreProvider);
  return IapRepository(store);
});

/// Live `Stream<IapEvent>` of platform purchase events the UI subscribes to.
final purchaseUpdatesProvider = StreamProvider<IapEvent>((ref) {
  return ref.watch(iapServiceProvider).events();
});

/// No-op IAP adapter for platforms where In-App Purchase is unavailable
/// (Windows, macOS desktop, Linux, web). Every call reports the store
/// as unavailable and the purchase stream as empty.
class _NoopInAppPurchaseAdapter implements InAppPurchaseAdapter {
  @override
  Future<bool> isAvailable() => Future.value(false);

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) =>
      Future.value(ProductDetailsResponse(
        productDetails: const [],
        notFoundIDs: identifiers.toList(),
        error: null,
      ));

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) =>
      Future.value(false);

  @override
  Future<void> restorePurchases({String? applicationUserName}) =>
      Future.value();

  @override
  Future<void> completePurchase(PurchaseDetails purchase) => Future.value();

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();
}
