import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/crypto/curve25519_pairing_service.dart';

void main() {
  group('Curve25519PairingService', () {
    late Curve25519PairingService service;

    setUp(() {
      service = Curve25519PairingService();
    });

    test('two parties derive the same 32-byte shared key', () async {
      final alice = await service.generateLocalKeyPair();
      final bob = await service.generateLocalKeyPair();

      final aliceShared = await service.deriveSharedSecret(
        localKeyPair: alice.keyPair,
        peerPublicKey: bob.publicKey,
      );
      final bobShared = await service.deriveSharedSecret(
        localKeyPair: bob.keyPair,
        peerPublicKey: alice.publicKey,
      );

      expect(aliceShared.bytes.length, 32);
      expect(bobShared.bytes.length, 32);
      expect(aliceShared.bytes, equals(bobShared.bytes));
    });

    test('two parties derive the same 6-digit SAS code', () async {
      final alice = await service.generateLocalKeyPair();
      final bob = await service.generateLocalKeyPair();

      final aliceShared = await service.deriveSharedSecret(
        localKeyPair: alice.keyPair,
        peerPublicKey: bob.publicKey,
      );
      final bobShared = await service.deriveSharedSecret(
        localKeyPair: bob.keyPair,
        peerPublicKey: alice.publicKey,
      );

      final aliceCode = service.deriveShortCode(aliceShared);
      final bobCode = service.deriveShortCode(bobShared);

      expect(aliceCode, hasLength(6));
      expect(int.tryParse(aliceCode), isNotNull);
      expect(aliceCode, bobCode);
    });

    test('different pairs produce different shared secrets', () async {
      final alice = await service.generateLocalKeyPair();
      final bob = await service.generateLocalKeyPair();
      final carol = await service.generateLocalKeyPair();

      final aliceBob = await service.deriveSharedSecret(
        localKeyPair: alice.keyPair,
        peerPublicKey: bob.publicKey,
      );
      final aliceCarol = await service.deriveSharedSecret(
        localKeyPair: alice.keyPair,
        peerPublicKey: carol.publicKey,
      );

      expect(aliceBob.bytes, isNot(equals(aliceCarol.bytes)));
    });

    test('short code is deterministic for identical secrets', () {
      final fixed = SharedSecret(_filledKey(0x42));
      final first = service.deriveShortCode(fixed);
      final second = service.deriveShortCode(fixed);
      expect(first, second);
      expect(first, hasLength(6));
    });

    test('rejects a small-subgroup (all-zero) peer public key', () async {
      final alice = await service.generateLocalKeyPair();
      // RFC 7748 §6.1: a public key of all zeros is a low-order point;
      // ECDH against it yields the all-zero shared secret, which leaks no
      // information about the private key. The service MUST refuse it.
      final lowOrder = SimplePublicKey(
        List<int>.filled(32, 0),
        type: KeyPairType.x25519,
      );
      await expectLater(
        service.deriveSharedSecret(
          localKeyPair: alice.keyPair,
          peerPublicKey: lowOrder,
        ),
        throwsA(isA<SmallSubgroupPublicKeyException>()),
      );
    });

    test('public key bytes round-trip into a SimplePublicKey', () async {
      final pair = await service.generateLocalKeyPair();
      final bytes = pair.publicKey.bytes;
      expect(bytes.length, 32);

      final restored = SimplePublicKey(
        bytes,
        type: KeyPairType.x25519,
      );
      final partner = await service.generateLocalKeyPair();

      final asLive = await service.deriveSharedSecret(
        localKeyPair: partner.keyPair,
        peerPublicKey: pair.publicKey,
      );
      final asRestored = await service.deriveSharedSecret(
        localKeyPair: partner.keyPair,
        peerPublicKey: restored,
      );

      expect(asLive.bytes, equals(asRestored.bytes));
    });
  });
}

Uint8List _filledKey(int value) {
  return Uint8List.fromList(List<int>.filled(32, value));
}
