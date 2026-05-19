import '../../../core/storage/secure_key_store.dart';
import '../domain/entitlements.dart';

/// Persists the latest verified entitlement to [SecureKeyStore] so the app
/// remembers Premium across restarts even when the device is offline and
/// the store cannot be reached.
///
/// Stored separately from the trial-start anchor used by
/// `SubscriptionController` — the controller composes the two on boot to
/// derive the effective tier.
class IapRepository {
  IapRepository(this._store);

  final SecureKeyStore _store;

  static const String _storageKey = 'iap.entitlement.v1';

  /// Loads the cached entitlement or `null` if nothing has been persisted
  /// yet. Returns `null` on malformed payloads too — better to fall back
  /// to the trial flow than crash on boot.
  Future<Entitlements?> load() async {
    final raw = await _store.readJson(_storageKey);
    if (raw == null) return null;
    try {
      return Entitlements.fromJson(raw);
    } on Object {
      return null;
    }
  }

  /// Writes the entitlement snapshot. Called by the IAP service **before**
  /// `completePurchase` so a crash in the platform layer cannot leave a
  /// verified entitlement unrecorded.
  Future<void> save(Entitlements entitlements) {
    return _store.writeJson(_storageKey, entitlements.toJson());
  }

  /// Drops the cached entitlement. Useful for tests and for the eventual
  /// «sign out» flow.
  Future<void> clear() => _store.delete(_storageKey);
}
