import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// End-to-end encryption layer used between paired devices.
///
/// Wraps the well-known [`cryptography`](https://pub.dev/packages/cryptography)
/// package so the rest of the app can stay agnostic to algorithm choice:
///
/// * **Key exchange**: X25519 (Curve25519 ECDH) — produces a 32-byte shared
///   secret per pair of devices.
/// * **Symmetric cipher**: AES-256-GCM — authenticated encryption with a
///   12-byte random nonce and a 16-byte MAC tag.
///
/// The transport layer is responsible for distributing public keys and
/// transmitting the framed ciphertext bytes; this class handles only the
/// crypto primitives.
class PulseCrypto {
  PulseCrypto({X25519? kex, Cipher? cipher})
      : _kex = kex ?? X25519(),
        _cipher = cipher ?? AesGcm.with256bits();

  final X25519 _kex;
  final Cipher _cipher;

  /// Generates a fresh X25519 key pair. Private bytes never leave the device;
  /// only the public key (32 bytes) is shared with the peer.
  Future<PulseKeyPair> generateKeyPair() async {
    final pair = await _kex.newKeyPair();
    final pub = await pair.extractPublicKey();
    final seed = await pair.extractPrivateKeyBytes();
    return PulseKeyPair._(pair, pub, Uint8List.fromList(seed));
  }

  /// Restores a key pair from a previously saved 32-byte seed. The seed must
  /// have been produced by [PulseKeyPair.privateSeed]; passing arbitrary bytes
  /// throws [ArgumentError].
  Future<PulseKeyPair> keyPairFromSeed(List<int> seed) async {
    if (seed.length != 32) {
      throw ArgumentError(
        'PulseCrypto.keyPairFromSeed: seed must be 32 bytes, got ${seed.length}',
      );
    }
    final pair = await _kex.newKeyPairFromSeed(List<int>.from(seed));
    final pub = await pair.extractPublicKey();
    return PulseKeyPair._(pair, pub, Uint8List.fromList(seed));
  }

  /// Derives the 32-byte shared secret from this device's [keyPair] and the
  /// peer's raw 32-byte X25519 public key bytes.
  Future<List<int>> deriveSharedSecret({
    required PulseKeyPair keyPair,
    required List<int> remotePublicKey,
  }) async {
    final remote = SimplePublicKey(
      List<int>.unmodifiable(remotePublicKey),
      type: KeyPairType.x25519,
    );
    final secret = await _kex.sharedSecretKey(
      keyPair: keyPair._inner,
      remotePublicKey: remote,
    );
    return secret.extractBytes();
  }

  /// Encrypts [plaintext] under [sharedSecret] and packs the random nonce, the
  /// ciphertext and the 16-byte GCM tag into a single byte buffer:
  ///
  ///     [nonce (12) || ciphertext (n) || tag (16)]
  ///
  /// The returned bytes are safe to send over any transport.
  Future<Uint8List> seal({
    required List<int> sharedSecret,
    required List<int> plaintext,
    List<int>? aad,
  }) async {
    final secretKey = SecretKey(sharedSecret);
    final nonce = _cipher.newNonce();
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
      aad: aad ?? const <int>[],
    );
    final out = BytesBuilder(copy: false)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return out.toBytes();
  }

  /// Inverse of [seal]. Returns the plaintext bytes, or throws
  /// [SecretBoxAuthenticationError] if the MAC tag fails verification (i.e.
  /// the message was tampered with or the key is wrong).
  Future<Uint8List> open({
    required List<int> sharedSecret,
    required List<int> sealed,
    List<int>? aad,
  }) async {
    const macLen = 16; // AES-GCM tag is always 128 bits.
    final nonceLen = _cipher.nonceLength; // 12 bytes for AES-GCM.
    if (sealed.length < nonceLen + macLen) {
      throw const FormatException('PulseCrypto: sealed payload too short');
    }
    final nonce = sealed.sublist(0, nonceLen);
    final cipherText = sealed.sublist(nonceLen, sealed.length - macLen);
    final macBytes = sealed.sublist(sealed.length - macLen);
    final box = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
    final clear = await _cipher.decrypt(
      box,
      secretKey: SecretKey(sharedSecret),
      aad: aad ?? const <int>[],
    );
    return Uint8List.fromList(clear);
  }
}

/// A handle around an [`X25519`] [KeyPair] that keeps the matching public key
/// cached so callers can serialize / send it without an extra await.
class PulseKeyPair {
  PulseKeyPair._(this._inner, this._publicKey, this._privateSeed);

  final KeyPair _inner;
  final PublicKey _publicKey;
  final Uint8List _privateSeed;

  /// Raw 32-byte public key. Safe to share with the peer.
  List<int> get publicKey => List<int>.unmodifiable(
        (_publicKey as SimplePublicKey).bytes,
      );

  /// Convenience: base64-url encoded public key for QR / NFC / pairing wires.
  String get publicKeyBase64 => base64Url.encode(publicKey);

  /// Raw 32-byte private seed. Must be persisted in [SecureKeyStore]; never
  /// transmit it.
  List<int> get privateSeed => List<int>.unmodifiable(_privateSeed);
}
