import 'dart:typed_data';

/// Cryptographic material for a single saved connection.
///
/// Pulse derives this on first pairing via Curve25519 ECDH, authenticated
/// over a short numeric / QR code. The 32-byte symmetric key is used to seal
/// every payload with AES-256-GCM before it ever touches a transport.
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
  /// monotonic per direction to prevent reuse.
  Uint8List nextNonce(String connectionId);
}
