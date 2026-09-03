import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/crypto/pair_channel_nonce_domains.dart';
import 'package:pulse/features/crypto/pair_keys.dart';

void main() {
  group('PairChannelNonceDomainDeriver', () {
    test('opposite peers derive matching, disjoint nonce directions', () {
      final alicePublic = List<int>.generate(32, (i) => i);
      final bobPublic = List<int>.generate(32, (i) => 255 - i);
      final deriver = PairChannelNonceDomainDeriver();

      final alice = deriver.derive(
        localPublicKey: alicePublic,
        peerPublicKey: bobPublic,
      );
      final bob = deriver.derive(
        localPublicKey: bobPublic,
        peerPublicKey: alicePublic,
      );

      expect(alice.outboundMarker, bob.inboundMarker);
      expect(bob.outboundMarker, alice.inboundMarker);
      expect(alice.outboundMarker, isNot(alice.inboundMarker));
      expect(
        alice.outboundWireCounter(1),
        isNot(bob.outboundWireCounter(1)),
      );
    });

    test('reconstructs the local public key from persisted pair keys',
        () async {
      final x25519 = X25519();
      final aliceKeyPair = await x25519.newKeyPair();
      final bobKeyPair = await x25519.newKeyPair();
      final alicePublic = await aliceKeyPair.extractPublicKey();
      final bobPublic = await bobKeyPair.extractPublicKey();
      final alicePrivate = await aliceKeyPair.extractPrivateKeyBytes();
      final bobPrivate = await bobKeyPair.extractPrivateKeyBytes();
      final root = Uint8List.fromList(List<int>.filled(32, 0x73));
      final aliceRecord = PairKeys(
        connectionId: 'pair',
        symmetricKey: root,
        partnerPublicKey: Uint8List.fromList(bobPublic.bytes),
        localPrivateKey: Uint8List.fromList(alicePrivate),
      );
      final bobRecord = PairKeys(
        connectionId: 'pair',
        symmetricKey: root,
        partnerPublicKey: Uint8List.fromList(alicePublic.bytes),
        localPrivateKey: Uint8List.fromList(bobPrivate),
      );
      final deriver = PairChannelNonceDomainDeriver(x25519: x25519);

      final alice = await deriver.deriveFromPairKeys(aliceRecord);
      final bob = await deriver.deriveFromPairKeys(bobRecord);

      expect(alice.outboundMarker, bob.inboundMarker);
      expect(alice.inboundMarker, bob.outboundMarker);
    });

    test('accepts legacy marker zero but rejects the outbound direction', () {
      final domains = PairChannelNonceDomainDeriver().derive(
        localPublicKey: List<int>.filled(32, 1),
        peerPublicKey: List<int>.filled(32, 2),
      );

      expect(domains.acceptsInboundWireCounter(7), isTrue);
      final inboundWire = domains.inboundMarker * 0x100000000 + 7;
      expect(domains.acceptsInboundWireCounter(inboundWire), isTrue);
      expect(
        domains.acceptsInboundWireCounter(domains.outboundWireCounter(7)),
        isFalse,
      );
    });

    test('rejects identical endpoint public keys', () {
      final publicKey = List<int>.filled(32, 7);
      expect(
        () => PairChannelNonceDomainDeriver().derive(
          localPublicKey: publicKey,
          peerPublicKey: publicKey,
        ),
        throwsStateError,
      );
    });
  });
}
