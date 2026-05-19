import 'dart:async';

import '../../core/storage/secure_key_store.dart';

/// Thrown when the persisted nonce counter on disk has moved *backwards*
/// relative to the high-water mark we previously recorded.
///
/// An honest counter only ever increases. Going down means either:
///   * the storage layer was tampered with (e.g. someone restored an
///     older backup of `EncryptedSharedPreferences` to try to force
///     AES-GCM nonce reuse), or
///   * a bug in higher-level code reset the counter without going
///     through [NonceCounter.resetToZero].
///
/// Either way we *must* refuse to mint new nonces from this counter —
/// reusing an AES-GCM nonce instantly breaks confidentiality.
class NonceRollbackException implements Exception {
  const NonceRollbackException({
    required this.storageKey,
    required this.persistedValue,
    required this.highWaterMark,
  });

  /// Storage key whose value rolled backwards.
  final String storageKey;

  /// Value currently sitting under [storageKey] on disk.
  final int persistedValue;

  /// Highest value Pulse has ever seen for this counter on this device.
  final int highWaterMark;

  @override
  String toString() => 'NonceRollbackException(storageKey: $storageKey, '
      'persistedValue: $persistedValue, highWaterMark: $highWaterMark)';
}

/// Monotonic 64-bit counter used to derive deterministic AES-GCM nonces
/// for a single direction of a paired channel.
///
/// One counter exists per direction (outbound/inbound) so that the two
/// peers never collide on a nonce, even if they restart the app or swap
/// transports mid-session.
///
/// Backed by [SecureKeyStore] (iOS Keychain / Android
/// EncryptedSharedPreferences) with a *compare-and-set* style high-water
/// mark: every increment writes both the current value and a separate
/// "highest-ever-seen" key. On reload we verify the two are still
/// consistent; if not, [NonceRollbackException] is raised and the
/// channel must be re-paired.
class NonceCounter {
  NonceCounter({
    required SecureKeyStore storage,
    required String storageKey,
  })  : _storage = storage,
        _storageKey = storageKey,
        _hwmKey = '$storageKey::hwm';

  final SecureKeyStore _storage;
  final String _storageKey;
  final String _hwmKey;

  int _lastUsed = 0;
  bool _loaded = false;

  /// Re-read the counter from secure storage. Must be called before the
  /// first [peek] / [next] if you cannot guarantee that a previous
  /// session left the in-memory state consistent. Subsequent calls
  /// short-circuit unless [force] is true.
  ///
  /// Throws [NonceRollbackException] if the persisted value is below
  /// the recorded high-water mark.
  Future<void> restore({bool force = false}) async {
    if (_loaded && !force) return;
    final mainRaw = await _storage.readString(_storageKey);
    final hwmRaw = await _storage.readString(_hwmKey);
    final main = int.tryParse(mainRaw ?? '') ?? 0;
    final hwm = int.tryParse(hwmRaw ?? '') ?? 0;
    if (main < hwm) {
      throw NonceRollbackException(
        storageKey: _storageKey,
        persistedValue: main,
        highWaterMark: hwm,
      );
    }
    _lastUsed = main;
    _loaded = true;
  }

  /// Return the next counter value that [next] would emit, without
  /// advancing.
  Future<int> peek() async {
    await restore();
    return _lastUsed + 1;
  }

  /// Increment the counter, persist the new value plus the high-water
  /// mark, and return it.
  Future<int> next() async {
    await restore();
    final newValue = _lastUsed + 1;
    // High-water mark first: if the process is killed between writes,
    // a subsequent restore will detect the rollback and bail.
    await _storage.writeString(_hwmKey, newValue.toString());
    await _storage.writeString(_storageKey, newValue.toString());
    _lastUsed = newValue;
    return newValue;
  }

  /// Force the counter back to zero and persist. Intended for the
  /// explicit "wipe pair" flow (§6 of the spec — паническое стирание).
  Future<void> resetToZero() async {
    _lastUsed = 0;
    _loaded = true;
    await _storage.writeString(_hwmKey, '0');
    await _storage.writeString(_storageKey, '0');
  }

  /// Permanently delete both the counter and its high-water mark from
  /// secure storage. Pair this with [PairKeys] wiping during unpair.
  Future<void> wipe() async {
    _lastUsed = 0;
    _loaded = false;
    await _storage.delete(_storageKey);
    await _storage.delete(_hwmKey);
  }

  /// Last value emitted by [next]. Useful for diagnostics / debugging.
  int get lastUsed => _lastUsed;
}
