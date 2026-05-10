import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/crypto/pulse_crypto.dart';

void main() {
  group('PulseCrypto', () {
    final crypto = PulseCrypto();

    test('generateKeyPair produces 32-byte X25519 public keys', () async {
      final pair = await crypto.generateKeyPair();
      expect(pair.publicKey.length, 32);
      expect(pair.publicKeyBase64, isNotEmpty);
      // Two fresh key pairs must differ.
      final other = await crypto.generateKeyPair();
      expect(pair.publicKey, isNot(other.publicKey));
    });

    test('ECDH shared secret is symmetric between both peers', () async {
      final alice = await crypto.generateKeyPair();
      final bob = await crypto.generateKeyPair();

      final aliceSide = await crypto.deriveSharedSecret(
        keyPair: alice,
        remotePublicKey: bob.publicKey,
      );
      final bobSide = await crypto.deriveSharedSecret(
        keyPair: bob,
        remotePublicKey: alice.publicKey,
      );

      expect(aliceSide.length, 32);
      expect(aliceSide, bobSide);
    });

    test('seal + open round-trips arbitrary plaintext', () async {
      final alice = await crypto.generateKeyPair();
      final bob = await crypto.generateKeyPair();
      final secret = await crypto.deriveSharedSecret(
        keyPair: alice,
        remotePublicKey: bob.publicKey,
      );

      final plain = utf8.encode('pulse: tap-tap');
      final sealed = await crypto.seal(
        sharedSecret: secret,
        plaintext: plain,
      );

      // Layout: nonce(12) || ciphertext(n) || tag(16) — total length must add up.
      expect(sealed.length, plain.length + 12 + 16);

      final opened = await crypto.open(
        sharedSecret: secret,
        sealed: sealed,
      );
      expect(utf8.decode(opened), 'pulse: tap-tap');
    });

    test('open rejects a tampered tag', () async {
      final alice = await crypto.generateKeyPair();
      final bob = await crypto.generateKeyPair();
      final secret = await crypto.deriveSharedSecret(
        keyPair: alice,
        remotePublicKey: bob.publicKey,
      );

      final sealed = await crypto.seal(
        sharedSecret: secret,
        plaintext: utf8.encode('hello'),
      );
      // Flip a bit in the GCM tag (last 16 bytes).
      final tampered = Uint8List.fromList(sealed);
      tampered[tampered.length - 1] ^= 0x01;

      expect(
        () => crypto.open(sharedSecret: secret, sealed: tampered),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('open rejects too-short payloads', () async {
      final alice = await crypto.generateKeyPair();
      final bob = await crypto.generateKeyPair();
      final secret = await crypto.deriveSharedSecret(
        keyPair: alice,
        remotePublicKey: bob.publicKey,
      );

      expect(
        () => crypto.open(
          sharedSecret: secret,
          sealed: List<int>.filled(10, 0),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('open rejects payload sealed with the wrong key', () async {
      final alice = await crypto.generateKeyPair();
      final bob = await crypto.generateKeyPair();
      final eve = await crypto.generateKeyPair();

      final secret = await crypto.deriveSharedSecret(
        keyPair: alice,
        remotePublicKey: bob.publicKey,
      );
      final wrong = await crypto.deriveSharedSecret(
        keyPair: alice,
        remotePublicKey: eve.publicKey,
      );

      final sealed = await crypto.seal(
        sharedSecret: secret,
        plaintext: utf8.encode('private'),
      );

      expect(
        () => crypto.open(sharedSecret: wrong, sealed: sealed),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });
}
