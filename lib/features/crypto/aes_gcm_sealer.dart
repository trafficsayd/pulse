import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// AES-256-GCM sealed packet codec used by every Pulse transport.
///
/// Wire format:
///
/// ```
/// +----------+----------------+-----+
/// | nonce 12 |   ciphertext   | mac |
/// +----------+----------------+-----+
///                                |
///                                +-- 16-byte GCM tag
/// ```
///
/// The 12-byte nonce is derived deterministically from a monotonically
/// increasing per-direction counter: the high 32 bits are reserved (and
/// currently always zero), and the low 64 bits hold the counter encoded
/// as a big-endian uint64. This makes nonce-reuse a programmer error
/// rather than a probabilistic risk.
class AesGcmSealer {
  AesGcmSealer({AesGcm? algorithm}) : _algo = algorithm ?? AesGcm.with256bits();

  final AesGcm _algo;

  /// AES-GCM nonce length in bytes (96 bits).
  static const int nonceLength = 12;

  /// AES-GCM authentication tag length in bytes (128 bits).
  static const int macLength = 16;

  /// Encrypt [plaintext] under [key] using a counter-derived nonce and
  /// return a single buffer `nonce || ciphertext || mac`.
  Future<Uint8List> seal(
    Uint8List plaintext, {
    required SecretKey key,
    required int nonceCounter,
  }) async {
    final nonce = nonceFromCounter(nonceCounter);
    final box = await _algo.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
    );
    final ct = box.cipherText;
    final mac = box.mac.bytes;
    final out = Uint8List(nonce.length + ct.length + mac.length);
    out.setRange(0, nonce.length, nonce);
    out.setRange(nonce.length, nonce.length + ct.length, ct);
    out.setRange(
      nonce.length + ct.length,
      nonce.length + ct.length + mac.length,
      mac,
    );
    return out;
  }

  /// Reverse [seal]. Throws [StateError] when the embedded nonce does
  /// not match [expectedNonceCounter] or when AES-GCM authentication
  /// fails (tampered ciphertext / wrong key).
  Future<Uint8List> open(
    Uint8List packet, {
    required SecretKey key,
    required int expectedNonceCounter,
  }) async {
    if (packet.length < nonceLength + macLength) {
      throw const FormatException(
        'AES-GCM packet too short: needs at least nonce + tag',
      );
    }
    final nonce = Uint8List.sublistView(packet, 0, nonceLength);
    final expected = nonceFromCounter(expectedNonceCounter);
    if (!_constantTimeEquals(nonce, expected)) {
      throw StateError(
        'AES-GCM nonce counter mismatch (replay or out-of-order packet)',
      );
    }
    final macStart = packet.length - macLength;
    final ct = Uint8List.sublistView(packet, nonceLength, macStart);
    final mac = Uint8List.sublistView(packet, macStart);
    final box = SecretBox(
      ct,
      nonce: nonce,
      mac: Mac(mac),
    );
    try {
      final plain = await _algo.decrypt(box, secretKey: key);
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError catch (e) {
      throw StateError('AES-GCM authentication failed: $e');
    }
  }

  /// Public for testing — produces the deterministic 12-byte nonce for a
  /// given counter value.
  static Uint8List nonceFromCounter(int counter) {
    if (counter < 0) {
      throw ArgumentError.value(
        counter,
        'counter',
        'Nonce counter must be non-negative',
      );
    }
    final out = Uint8List(nonceLength);
    // High 32 bits reserved (left as zero).
    var value = counter;
    for (var i = nonceLength - 1; i >= 4; i--) {
      out[i] = value % 256;
      value = value ~/ 256;
    }
    return out;
  }

  /// Decode the low 64-bit counter embedded by [nonceFromCounter].
  /// Rejects non-zero reserved bytes so alternate nonce domains cannot be
  /// confused with Pulse's monotonic counter domain.
  static int counterFromNonce(List<int> nonce) {
    if (nonce.length != nonceLength) {
      throw ArgumentError.value(nonce.length, 'nonce', 'must be 12 bytes');
    }
    if (nonce[0] != 0 || nonce[1] != 0 || nonce[2] != 0 || nonce[3] != 0) {
      throw const FormatException('AES-GCM reserved nonce bytes must be zero');
    }
    var value = 0;
    for (var i = 4; i < nonceLength; i++) {
      value = value * 256 + nonce[i];
    }
    return value;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
