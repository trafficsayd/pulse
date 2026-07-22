import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/crypto/aes_gcm_sealer.dart';

void main() {
  group('AesGcmSealer', () {
    late AesGcmSealer sealer;
    late SecretKey key;

    setUp(() {
      sealer = AesGcmSealer();
      key = SecretKey(List<int>.filled(32, 0x7a));
    });

    test('roundtrip: seal then open returns the original plaintext', () async {
      final plaintext = Uint8List.fromList(
        utf8Bytes('pulse mode_event: knock-knock x3'),
      );

      final packet = await sealer.seal(
        plaintext,
        key: key,
        nonceCounter: 1,
      );

      // Layout sanity: nonce(12) | ct(N) | mac(16).
      expect(packet.length, plaintext.length + 12 + 16);

      final opened = await sealer.open(
        packet,
        key: key,
        expectedNonceCounter: 1,
      );
      expect(opened, equals(plaintext));
    });

    test('counter is encoded in the low 64 bits, high 32 bits stay zero',
        () async {
      final nonce = AesGcmSealer.nonceFromCounter(0x01020304);
      expect(nonce.length, 12);
      // High 32 bits reserved.
      expect(nonce.sublist(0, 4), equals([0, 0, 0, 0]));
      // Counter big-endian in bytes [4..12].
      expect(
        nonce.sublist(4),
        equals([0, 0, 0, 0, 0x01, 0x02, 0x03, 0x04]),
      );
    });

    test('tampering with the ciphertext is detected', () async {
      final plaintext = Uint8List.fromList(utf8Bytes('integrity matters'));
      final packet = await sealer.seal(
        plaintext,
        key: key,
        nonceCounter: 7,
      );

      // Flip a bit somewhere inside the ciphertext region (skip the
      // 12-byte nonce header).
      packet[14] ^= 0x01;

      await expectLater(
        () => sealer.open(packet, key: key, expectedNonceCounter: 7),
        throwsA(isA<StateError>()),
      );
    });

    test('tampering with the MAC tag is detected', () async {
      final plaintext = Uint8List.fromList(utf8Bytes('mac protected'));
      final packet = await sealer.seal(
        plaintext,
        key: key,
        nonceCounter: 9,
      );
      packet[packet.length - 1] ^= 0x80;

      await expectLater(
        () => sealer.open(packet, key: key, expectedNonceCounter: 9),
        throwsA(isA<StateError>()),
      );
    });

    test('mismatched expected counter throws StateError', () async {
      final plaintext = Uint8List.fromList(utf8Bytes('replay guard'));
      final packet = await sealer.seal(
        plaintext,
        key: key,
        nonceCounter: 42,
      );

      await expectLater(
        () => sealer.open(packet, key: key, expectedNonceCounter: 43),
        throwsA(isA<StateError>()),
      );
    });

    test('open rejects truncated packets', () async {
      final tooShort = Uint8List(10);
      await expectLater(
        () => sealer.open(tooShort, key: key, expectedNonceCounter: 0),
        throwsA(isA<FormatException>()),
      );
    });

    test('the same counter reproduces an identical nonce', () {
      final a = AesGcmSealer.nonceFromCounter(12345);
      final b = AesGcmSealer.nonceFromCounter(12345);
      expect(a, equals(b));
    });

    test('two different counters produce different nonces', () {
      final a = AesGcmSealer.nonceFromCounter(1);
      final b = AesGcmSealer.nonceFromCounter(2);
      expect(a, isNot(equals(b)));
    });

    test(
        'roundtrip with non-empty aad: seal then open with the same aad '
        'returns the original plaintext', () async {
      final plaintext = Uint8List.fromList(
        utf8Bytes('pulse mode_event: aad bound packet'),
      );
      final aad = utf8Bytes('pulse:v1:aad:epoch-0');

      final packet = await sealer.seal(
        plaintext,
        key: key,
        nonceCounter: 3,
        aad: aad,
      );

      // Wire layout is unaffected by aad: nonce(12) | ct(N) | mac(16).
      // AAD is authenticated-only and never appended to the buffer.
      expect(packet.length, plaintext.length + 12 + 16);

      final opened = await sealer.open(
        packet,
        key: key,
        expectedNonceCounter: 3,
        aad: aad,
      );
      expect(opened, equals(plaintext));
    });

    test(
        'open with a different aad than what was used to seal fails '
        'authentication', () async {
      final plaintext = Uint8List.fromList(utf8Bytes('aad must match'));
      final sealAad = utf8Bytes('pulse:v1:aad:epoch-0');
      final openAad = utf8Bytes('pulse:v1:aad:epoch-1');

      final packet = await sealer.seal(
        plaintext,
        key: key,
        nonceCounter: 4,
        aad: sealAad,
      );

      await expectLater(
        () => sealer.open(
          packet,
          key: key,
          expectedNonceCounter: 4,
          aad: openAad,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test(
        'open with no aad fails authentication when seal used a '
        'non-empty aad', () async {
      final plaintext = Uint8List.fromList(utf8Bytes('aad presence matters'));
      final aad = utf8Bytes('pulse:v1:aad:epoch-0');

      final packet = await sealer.seal(
        plaintext,
        key: key,
        nonceCounter: 5,
        aad: aad,
      );

      // Default aad on open() is the empty list — must not silently
      // succeed against a packet sealed with non-empty aad.
      await expectLater(
        () => sealer.open(packet, key: key, expectedNonceCounter: 5),
        throwsA(isA<StateError>()),
      );
    });

    test(
        'empty aad (explicit or defaulted) behaves identically — backward '
        'compatibility for every pre-existing call site', () async {
      final plaintext = Uint8List.fromList(utf8Bytes('no aad here'));

      final packet = await sealer.seal(
        plaintext,
        key: key,
        nonceCounter: 6,
      );

      final openedDefault = await sealer.open(
        packet,
        key: key,
        expectedNonceCounter: 6,
      );
      expect(openedDefault, equals(plaintext));

      final openedExplicitEmpty = await sealer.open(
        packet,
        key: key,
        expectedNonceCounter: 6,
        aad: const [],
      );
      expect(openedExplicitEmpty, equals(plaintext));
    });
  });
}

List<int> utf8Bytes(String s) => utf8.encode(s);
