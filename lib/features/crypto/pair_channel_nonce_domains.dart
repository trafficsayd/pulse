import 'package:cryptography/cryptography.dart';

import 'pair_keys.dart';

/// Disjoint AES-GCM nonce domains for the two directions of a pair.
///
/// The direction marker occupies bytes 4..7 of Pulse's existing 96-bit nonce,
/// while bytes 8..11 hold a per-direction counter. Bytes 0..3 remain zero, so
/// pre-fix v1 clients can still decode and authenticate packets from upgraded
/// peers. Legacy packets use marker zero and remain accepted until that peer
/// starts sending direction-marked packets.
final class PairChannelNonceDomains {
  const PairChannelNonceDomains._({
    required this.outboundMarker,
    required this.inboundMarker,
  });

  /// ASCII-like markers below the signed 64-bit boundary once shifted.
  static const int lowToHighMarker = 0x50554c31; // "PUL1"
  static const int highToLowMarker = 0x50554c32; // "PUL2"
  static const int maxCounter = 0xffffffff;
  static const int _counterRadix = 0x100000000;

  final int outboundMarker;
  final int inboundMarker;

  int outboundWireCounter(int counter) {
    _validateCounter(counter);
    return outboundMarker * _counterRadix + counter;
  }

  /// Whether [wireCounter] belongs to the expected inbound direction or to a
  /// legacy v1 peer, whose direction marker was always zero.
  bool acceptsInboundWireCounter(int wireCounter) {
    if (wireCounter < 0) return false;
    final marker = wireCounter ~/ _counterRadix;
    return marker == inboundMarker || marker == 0;
  }

  int logicalCounter(int wireCounter) => wireCounter % _counterRadix;

  static void _validateCounter(int counter) {
    if (counter < 0 || counter > maxCounter) {
      throw StateError(
        'AES-GCM direction counter exhausted; re-pair before sending more',
      );
    }
  }
}

/// Assigns stable nonce directions by lexicographically ordering both X25519
/// public keys. Both devices therefore agree which marker protects each flow.
final class PairChannelNonceDomainDeriver {
  PairChannelNonceDomainDeriver({X25519? x25519})
      : _x25519 = x25519 ?? X25519();

  final X25519 _x25519;

  Future<PairChannelNonceDomains> deriveFromPairKeys(PairKeys pairKeys) async {
    final localKeyPair =
        await _x25519.newKeyPairFromSeed(pairKeys.localPrivateKey);
    final localPublicKey = await localKeyPair.extractPublicKey();
    return derive(
      localPublicKey: localPublicKey.bytes,
      peerPublicKey: pairKeys.partnerPublicKey,
    );
  }

  PairChannelNonceDomains derive({
    required List<int> localPublicKey,
    required List<int> peerPublicKey,
  }) {
    _validatePublicKey(localPublicKey, 'localPublicKey');
    _validatePublicKey(peerPublicKey, 'peerPublicKey');
    final order = _compareBytes(localPublicKey, peerPublicKey);
    if (order == 0) {
      throw StateError(
        'Cannot assign nonce directions to identical X25519 public keys',
      );
    }
    return order < 0
        ? const PairChannelNonceDomains._(
            outboundMarker: PairChannelNonceDomains.lowToHighMarker,
            inboundMarker: PairChannelNonceDomains.highToLowMarker,
          )
        : const PairChannelNonceDomains._(
            outboundMarker: PairChannelNonceDomains.highToLowMarker,
            inboundMarker: PairChannelNonceDomains.lowToHighMarker,
          );
  }

  static void _validatePublicKey(List<int> key, String name) {
    if (key.length != 32) {
      throw ArgumentError.value(key.length, name, 'must be 32 bytes');
    }
  }

  static int _compareBytes(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return 0;
  }
}
