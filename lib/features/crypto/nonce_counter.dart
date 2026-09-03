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
/// One counter exists per local direction (outbound/inbound). Counter
/// monotonicity prevents reuse within a direction, while [PairChannel] maps
/// opposite directions into disjoint nonce namespaces.
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
  int _reservedThrough = 0;
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
    _reservedThrough = main;
    _loaded = true;
  }

  /// Return the next counter value that [next] would emit, without
  /// advancing.
  Future<int> peek() async {
    await restore();
    return _lastUsed + 1;
  }

  /// Increment the counter and return it.
  ///
  /// [reservationSize] reserves a future range in secure storage before the
  /// first value from that range is emitted. Unused values are deliberately
  /// skipped after a process crash, which preserves nonce uniqueness while
  /// avoiding two encrypted-storage writes for every live gesture point.
  /// Callers that do not opt in retain the original persist-every-value
  /// behaviour.
  Future<int> next({int reservationSize = 1}) async {
    if (reservationSize < 1) {
      throw ArgumentError.value(
        reservationSize,
        'reservationSize',
        'must be positive',
      );
    }
    await restore();
    if (_lastUsed >= _reservedThrough) {
      final reservationEnd = _lastUsed + reservationSize;
      // High-water mark first: if the process is killed between writes,
      // a subsequent restore detects the rollback and refuses to reuse the
      // reserved nonces.
      await _storage.writeString(_hwmKey, reservationEnd.toString());
      await _storage.writeString(_storageKey, reservationEnd.toString());
      _reservedThrough = reservationEnd;
    }
    _lastUsed += 1;
    return _lastUsed;
  }

  /// Persist [value] as the last successfully observed counter.
  ///
  /// The inbound channel uses this when a transport handover loses one or
  /// more packets. The newer packet is still AES-GCM authenticated, so it is
  /// safe to advance to its embedded counter while continuing to reject
  /// replays. Outbound callers must keep using [next] so a nonce is never
  /// minted twice.
  Future<void> advanceTo(int value, {int reservationSize = 1}) async {
    if (value < 0) {
      throw ArgumentError.value(value, 'value', 'must be non-negative');
    }
    if (reservationSize < 1) {
      throw ArgumentError.value(
        reservationSize,
        'reservationSize',
        'must be positive',
      );
    }
    await restore();
    if (value < _lastUsed) {
      throw StateError('Nonce counter cannot move backwards');
    }
    if (value == _lastUsed) return;
    if (value > _reservedThrough) {
      final reservationEnd = value + reservationSize - 1;
      await _storage.writeString(_hwmKey, reservationEnd.toString());
      await _storage.writeString(_storageKey, reservationEnd.toString());
      _reservedThrough = reservationEnd;
    }
    _lastUsed = value;
  }

  /// Force the counter back to zero and persist. Intended for the
  /// explicit "wipe pair" flow (§6 of the spec — паническое стирание).
  Future<void> resetToZero() async {
    _lastUsed = 0;
    _reservedThrough = 0;
    _loaded = true;
    await _storage.writeString(_hwmKey, '0');
    await _storage.writeString(_storageKey, '0');
  }

  /// Permanently delete both the counter and its high-water mark from
  /// secure storage. Pair this with [PairKeys] wiping during unpair.
  Future<void> wipe() async {
    _lastUsed = 0;
    _reservedThrough = 0;
    _loaded = false;
    await _storage.delete(_storageKey);
    await _storage.delete(_hwmKey);
  }

  /// Last value emitted by [next]. Useful for diagnostics / debugging.
  int get lastUsed => _lastUsed;
}
