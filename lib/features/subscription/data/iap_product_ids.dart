/// Central registry for the SKU identifiers Pulse uses with the underlying
/// platform stores (App Store Connect / Google Play Console).
///
/// Pulse intentionally ships a single subscription product. Centralising the
/// id here lets the IAP service, repository, and tests share one source of
/// truth — if the SKU is ever renamed we only patch this file.
class IapProductIds {
  const IapProductIds._();

  /// SKU for the monthly «Pulse Premium» auto-renewable subscription.
  ///
  /// Matches the product id configured in `docs/spec_ru.md` (§7).
  static const String premiumMonthly = 'pulse_premium_monthly';

  /// All product ids Pulse will ever query the store for. Returning a fresh
  /// set on every read keeps callers from mutating the constant.
  static Set<String> all() => {premiumMonthly};
}
