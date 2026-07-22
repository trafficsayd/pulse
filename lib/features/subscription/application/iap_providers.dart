import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/storage/secure_key_store.dart';
import '../data/iap_repository.dart';
import '../data/iap_service.dart';

/// Singleton [IapService] used by [SubscriptionController] and watched by
/// the paywall UI.
///
/// Marked `keepAlive`/auto-disposed via [Ref.onDispose] so the underlying
/// platform listener is kept up for the whole app lifetime — Pulse needs
/// to react to a redelivery that arrives **before** the paywall is opened.
final iapServiceProvider = Provider<IapService>((ref) {
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

/// Store metadata for the Pulse Premium SKU.
///
/// Resolves to `null` when the store is unreachable or the product is not
/// configured yet — the paywall then falls back to the static localised
/// price string instead of showing nothing.
final premiumProductProvider = FutureProvider<ProductDetails?>((ref) {
  return ref.watch(iapServiceProvider).fetchPremiumProduct();
});
