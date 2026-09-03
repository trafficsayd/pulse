import 'dart:convert';
import 'dart:typed_data';

import '../../core/storage/secure_key_store.dart';

/// Cryptographic material for a single saved connection.
///
/// Pulse derives this on first pairing via Curve25519 ECDH, authenticated
/// over a short numeric / QR code. The 32-byte symmetric key seals every
/// payload with AES-256-GCM in direction-separated nonce domains before it
/// reaches a transport.
///
/// Instances of this class only ever live in memory while a session is
/// running. The on-disk copy is wrapped by [SecureKeyStore] (iOS Keychain /
/// Android EncryptedSharedPreferences).
class PairKeys {
  PairKeys({
    required this.connectionId,
    required this.symmetricKey,
    required this.partnerPublicKey,
    required this.localPrivateKey,
  })  : assert(symmetricKey.length == 32, 'Pulse uses AES-256 (32-byte key)'),
        assert(partnerPublicKey.length == 32),
        assert(localPrivateKey.length == 32);

  final String connectionId;

  /// 32-byte AES-256-GCM key derived via ECDH on first pairing.
  final Uint8List symmetricKey;

  /// Partner's Curve25519 public key. Kept on disk so we can re-derive a
  /// fresh symmetric key if the user later re-pairs (e.g. after a reset).
  final Uint8List partnerPublicKey;

  /// Local Curve25519 private key. Generated once per connection and never
  /// reused across connections.
  final Uint8List localPrivateKey;

  /// Secure-storage key for this connection's serialized [PairKeys].
  static String storageKey(String connectionId) => 'pair_keys::$connectionId';

  /// Storage key for the outbound nonce counter associated with this
  /// pair. Kept here so every layer agrees on the same naming.
  static String outboundNonceKey(String connectionId) =>
      'pair_nonce::out::$connectionId';

  /// Storage key for the inbound nonce counter associated with this pair.
  static String inboundNonceKey(String connectionId) =>
      'pair_nonce::in::$connectionId';

  Map<String, Object?> toJson() => <String, Object?>{
        'connectionId': connectionId,
        'symmetricKey': base64.encode(symmetricKey),
        'partnerPublicKey': base64.encode(partnerPublicKey),
        'localPrivateKey': base64.encode(localPrivateKey),
      };

  factory PairKeys.fromJson(Map<String, Object?> json) {
    Uint8List decode(Object? v) =>
        Uint8List.fromList(base64.decode(v! as String));
    return PairKeys(
      connectionId: json['connectionId']! as String,
      symmetricKey: decode(json['symmetricKey']),
      partnerPublicKey: decode(json['partnerPublicKey']),
      localPrivateKey: decode(json['localPrivateKey']),
    );
  }

  /// Persist this pair to [SecureKeyStore] under [storageKey].
  Future<void> persist(SecureKeyStore store) =>
      store.writeJson(storageKey(connectionId), toJson());

  /// Read a previously persisted [PairKeys] for [connectionId], or null
  /// if nothing is on disk yet.
  static Future<PairKeys?> load(
    SecureKeyStore store,
    String connectionId,
  ) async {
    final raw = await store.readJson(storageKey(connectionId));
    if (raw == null) return null;
    return PairKeys.fromJson(raw);
  }

  /// Delete the persisted keys and nonce counters for [connectionId].
  ///
  /// Implements the "паническое стирание" requirement from §6 of the
  /// spec: after this call there is no way to recover the symmetric
  /// key, the partner's public key, or our local private key.
  static Future<void> wipe(
    SecureKeyStore store,
    String connectionId,
  ) async {
    await store.delete(storageKey(connectionId));
    await store.delete(outboundNonceKey(connectionId));
    await store.delete('${outboundNonceKey(connectionId)}::hwm');
    await store.delete(inboundNonceKey(connectionId));
    await store.delete('${inboundNonceKey(connectionId)}::hwm');
  }
}

/// Pairing operations contract.
///
/// Concrete implementation lands in a follow-up PR; the goal here is to lock
/// the surface so the rest of the app can already program against it.
abstract interface class PairingService {
  /// Generate a fresh keypair for a new pair, returning a 6-digit short code
  /// (or QR payload) to be shown to the partner for authenticated exchange.
  Future<String> beginPairing();

  /// Complete pairing with the partner's short code. Returns the derived
  /// [PairKeys] which the caller MUST hand to [SecureKeyStore] for at-rest
  /// encryption.
  Future<PairKeys> completePairing(String partnerCode);

  /// Derive a fresh AES-GCM nonce for the next outbound payload. Nonces are
  /// monotonic within each direction-separated nonce domain.
  Uint8List nextNonce(String connectionId);
}
