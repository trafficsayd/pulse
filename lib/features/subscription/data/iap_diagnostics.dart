/// Stable, store-agnostic error codes Pulse surfaces to the UI.
///
/// The underlying `in_app_purchase` plugin exposes a fairly opaque
/// `IAPError.code` (StoreKit error names on iOS, Billing-result strings on
/// Android). We translate those into a small enum so the paywall can show
/// a localised message without leaking platform jargon into the UI layer.
enum IapErrorCode {
  paymentInvalid,
  paymentNotAllowed,
  billingUnavailable,
  itemUnavailable,
  generic,
}

/// Maps a raw store error code (from `IAPError.code`) to one of the
/// [IapErrorCode] buckets above.
///
/// The matcher is lenient on purpose — both iOS and Android keep tweaking
/// the strings they emit, so we lowercase + substring-match instead of
/// pinning to an exact value.
IapErrorCode classifyIapError(String? rawCode) {
  if (rawCode == null) return IapErrorCode.generic;
  final c = rawCode.toLowerCase();
  if (c.contains('not_allowed') || c.contains('paymentnotallowed')) {
    return IapErrorCode.paymentNotAllowed;
  }
  if (c.contains('payment_invalid') || c.contains('paymentinvalid')) {
    return IapErrorCode.paymentInvalid;
  }
  if (c.contains('billing_unavailable') ||
      c.contains('service_unavailable') ||
      c.contains('storekitnotenabled')) {
    return IapErrorCode.billingUnavailable;
  }
  if (c.contains('item_unavailable') || c.contains('product_unavailable')) {
    return IapErrorCode.itemUnavailable;
  }
  return IapErrorCode.generic;
}
