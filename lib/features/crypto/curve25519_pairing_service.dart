import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Ephemeral Curve25519 keypair owned by the local device for a single
/// pairing.
///
/// Wraps the `package:cryptography` [SimpleKeyPair] so the rest of Pulse
/// does not have to depend on the underlying types directly.
class Curve25519KeyPair {
  Curve25519KeyPair({required this.keyPair, required this.publicKey});

  /// The opaque ECDH key pair. Hand this back to
  /// [Curve25519PairingService.deriveSharedSecret] together with the
  /// partner's public key.
  final SimpleKeyPair keyPair;

  /// Raw 32-byte X25519 public key suitable for embedding in QR payloads
  /// or short-code transports.
  final SimplePublicKey publicKey;

  /// Returns the public key bytes encoded as URL-safe base64 (no padding).
  /// This is what we put inside the QR payload during pairing.
  Future<String> publicKeyBase64Url() async {
    return base64Url.encode(publicKey.bytes).replaceAll('=', '');
  }
}

/// Thrown when the peer's X25519 public key lies in a small subgroup of
/// the curve and ECDH collapses to an all-zero output. This is an active
/// MitM attempt — a normal peer never sends such a key.
class SmallSubgroupPublicKeyException implements Exception {
  const SmallSubgroupPublicKeyException();

  @override
  String toString() =>
      'SmallSubgroupPublicKeyException: peer public key is a low-order '
      'point on Curve25519; pairing rejected.';
}

/// Output of the ECDH + HKDF step. The contained 32 bytes are the symmetric
/// key both peers will use for AES-256-GCM sealing.
class SharedSecret {
  SharedSecret(Uint8List bytes)
      : assert(bytes.length == 32, 'Pulse uses AES-256 (32-byte key)'),
        _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;

  /// 32-byte derived key. Wrap with [secretKey] when handing to AES-GCM.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  /// Convenience: wrap the derived bytes as a [SecretKey].
  SecretKey secretKey() => SecretKey(_bytes);
}

/// Curve25519 ECDH + HKDF-SHA-256 pairing primitive.
///
/// This is the cryptographic core of §3 "Подключение" and §6 "Приватность и
/// безопасность" in [docs/spec_ru.md]. The class is deliberately tiny: it
/// generates ephemeral X25519 keypairs, derives the shared 32-byte AES-256
/// key over HKDF-SHA-256, and turns that key into a 6-digit SAS code so
/// both partners can verify the channel out-of-band.
class Curve25519PairingService {
  Curve25519PairingService({X25519? x25519, Hkdf? hkdf, Sha256? sha256})
      : _x25519 = x25519 ?? X25519(),
        _hkdf = hkdf ?? Hkdf(hmac: Hmac.sha256(), outputLength: 32),
        _sha256 = sha256 ?? Sha256();

  final X25519 _x25519;
  final Hkdf _hkdf;
  final Sha256 _sha256;

  /// HKDF "info" string. Domain-separates Pulse's pairing key from anything
  /// else that might share the same DH secret in the future.
  static const String hkdfInfo = 'pulse:pair:v1:aead-key';

  /// HKDF salt. Empty is RFC 5869 compliant and intentionally fixed so
  /// both peers derive the same key without negotiating a salt.
  static const List<int> hkdfSalt = <int>[];

  /// SAS domain-separator. Pulse hashes [hkdfSasContext] || sharedKey to
  /// avoid reusing the AEAD key directly as a SAS oracle.
  static const String hkdfSasContext = 'pulse:pair:v1:sas';

  /// Generate a fresh ephemeral X25519 keypair for a single pairing.
  Future<Curve25519KeyPair> generateLocalKeyPair() async {
    final kp = await _x25519.newKeyPair();
    final pub = await kp.extractPublicKey();
    return Curve25519KeyPair(keyPair: kp, publicKey: pub);
  }

  /// Perform X25519 ECDH followed by HKDF-SHA-256 to produce a 32-byte
  /// AES-256 key bound to this pair.
  ///
  /// Throws [SmallSubgroupPublicKeyException] when the peer key is a
  /// low-order point on Curve25519 (RFC 7748 §6.1) and ECDH degenerates
  /// to the all-zero shared secret.
  Future<SharedSecret> deriveSharedSecret({
    required SimpleKeyPair localKeyPair,
    required SimplePublicKey peerPublicKey,
  }) async {
    final dh = await _x25519.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: peerPublicKey,
    );
    final dhBytes = await dh.extractBytes();
    if (_isAllZero(dhBytes)) {
      throw const SmallSubgroupPublicKeyException();
    }
    final derived = await _hkdf.deriveKey(
      secretKey: dh,
      nonce: hkdfSalt,
      info: utf8.encode(hkdfInfo),
    );
    final bytes = await derived.extractBytes();
    return SharedSecret(Uint8List.fromList(bytes));
  }

  static bool _isAllZero(List<int> bytes) {
    var diff = 0;
    for (final b in bytes) {
      diff |= b;
    }
    return diff == 0;
  }

  /// Derive the 6-digit Short Authentication String the user must compare
  /// out-of-band.
  ///
  /// Steps (deterministic, identical on both peers):
  ///  1. SHA-256 of `hkdfSasContext || secret.bytes`.
  ///  2. Read the first 4 bytes as a big-endian uint32.
  ///  3. Reduce mod 1_000_000 and zero-pad to 6 decimal digits.
  String deriveShortCode(SharedSecret secret) {
    final input = <int>[
      ...utf8.encode(hkdfSasContext),
      ...secret.bytes,
    ];
    final digest = _sha256.toSync().hashSync(input);
    final bytes = digest.bytes;
    if (bytes.length < 4) {
      throw StateError('SHA-256 digest must be at least 4 bytes');
    }
    final value =
        (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | (bytes[3]);
    // `&`-mask to 32 bits to keep behaviour identical on web (JS ints are
    // doubles) and native.
    final masked = value & 0xFFFFFFFF;
    final code = (masked % 1000000).toString().padLeft(6, '0');
    return code;
  }
}
