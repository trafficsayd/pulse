import 'dart:convert';

import '../storage/secure_key_store.dart';
import 'pulse_crypto.dart';

/// Owns the per-connection X25519 key material and exposes the small set of
/// operations the rest of the app needs to drive a pairing handshake.
///
/// Wire model — for each connection id we persist three optional values in
/// [SecureKeyStore]:
///
///   * `crypto.kp.<id>.seed`     — local 32-byte private seed (base64)
///   * `crypto.kp.<id>.pub`      — local 32-byte X25519 public key (base64)
///   * `crypto.kp.<id>.peer_pub` — remote 32-byte X25519 public key (base64)
///
/// Only the seed is sensitive. The public keys are stored alongside it so we
/// don't have to re-derive them on every read. The shared secret is **never**
/// persisted: it's recomputed on demand from the saved seed + peer public key
/// and lives in memory only.
class PulseKeyManager {
  PulseKeyManager({
    required SecureKeyStore keyStore,
    PulseCrypto? crypto,
  })  : _keyStore = keyStore,
        _crypto = crypto ?? PulseCrypto();

  static const _prefix = 'crypto.kp.';
  static const _seedSuffix = '.seed';
  static const _pubSuffix = '.pub';
  static const _peerSuffix = '.peer_pub';

  final SecureKeyStore _keyStore;
  final PulseCrypto _crypto;

  /// Returns the [PulseKeyPair] for [connectionId], generating and persisting
  /// one on first use.
  Future<PulseKeyPair> getOrCreate(String connectionId) async {
    final saved = await _keyStore.readString('$_prefix$connectionId$_seedSuffix');
    if (saved != null) {
      return _crypto.keyPairFromSeed(base64.decode(saved));
    }
    final fresh = await _crypto.generateKeyPair();
    await _keyStore.writeString(
      '$_prefix$connectionId$_seedSuffix',
      base64.encode(fresh.privateSeed),
    );
    await _keyStore.writeString(
      '$_prefix$connectionId$_pubSuffix',
      base64.encode(fresh.publicKey),
    );
    return fresh;
  }

  /// Stores the peer's 32-byte X25519 public key for [connectionId]. Call this
  /// once the pairing handshake has delivered the peer's bytes.
  Future<void> setPeerPublicKey(String connectionId, List<int> peerPublicKey) async {
    if (peerPublicKey.length != 32) {
      throw ArgumentError(
        'Peer X25519 public key must be 32 bytes, got ${peerPublicKey.length}',
      );
    }
    await _keyStore.writeString(
      '$_prefix$connectionId$_peerSuffix',
      base64.encode(peerPublicKey),
    );
  }

  /// Returns the 32-byte peer public key for [connectionId], or `null` if
  /// the handshake hasn't completed yet.
  Future<List<int>?> peerPublicKey(String connectionId) async {
    final raw = await _keyStore.readString('$_prefix$connectionId$_peerSuffix');
    return raw == null ? null : base64.decode(raw);
  }

  /// Derives the 32-byte AES-256-GCM session secret for [connectionId], or
  /// returns `null` if either side of the handshake is missing.
  Future<List<int>?> sharedSecret(String connectionId) async {
    final peerRaw = await _keyStore.readString('$_prefix$connectionId$_peerSuffix');
    if (peerRaw == null) return null;
    final keyPair = await getOrCreate(connectionId);
    return _crypto.deriveSharedSecret(
      keyPair: keyPair,
      remotePublicKey: base64.decode(peerRaw),
    );
  }

  /// Wipes every persisted byte tied to [connectionId]. Used by
  /// `ConnectionsController.delete` so an unpaired connection leaves no trace.
  Future<void> erase(String connectionId) async {
    await _keyStore.delete('$_prefix$connectionId$_seedSuffix');
    await _keyStore.delete('$_prefix$connectionId$_pubSuffix');
    await _keyStore.delete('$_prefix$connectionId$_peerSuffix');
  }
}
