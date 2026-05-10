import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/crypto/pulse_crypto.dart';
import 'package:pulse/core/crypto/pulse_key_manager.dart';
import 'package:pulse/core/storage/secure_key_store.dart';

import 'fakes/in_memory_secure_storage.dart';

void main() {
  group('PulseKeyManager', () {
    late SecureKeyStore store;
    late PulseKeyManager manager;
    final crypto = PulseCrypto();

    setUp(() {
      store = SecureKeyStore(storage: InMemoryFlutterSecureStorage());
      manager = PulseKeyManager(keyStore: store, crypto: crypto);
    });

    test('getOrCreate returns the same key pair across calls', () async {
      const id = 'conn-1';
      final first = await manager.getOrCreate(id);
      final second = await manager.getOrCreate(id);

      expect(first.publicKey, second.publicKey);
      expect(first.privateSeed, second.privateSeed);
      expect(first.publicKey.length, 32);
      expect(first.privateSeed.length, 32);
    });

    test('two connections get independent key pairs', () async {
      final a = await manager.getOrCreate('alpha');
      final b = await manager.getOrCreate('beta');
      expect(a.publicKey, isNot(b.publicKey));
    });

    test('sharedSecret is null until peer public key is set', () async {
      const id = 'conn-2';
      await manager.getOrCreate(id);
      expect(await manager.sharedSecret(id), isNull);
    });

    test('after binding peer public key, both peers derive the same secret',
        () async {
      // Two managers backed by independent stores act as Alice and Bob.
      final aliceStore =
          SecureKeyStore(storage: InMemoryFlutterSecureStorage());
      final bobStore = SecureKeyStore(storage: InMemoryFlutterSecureStorage());
      final alice = PulseKeyManager(keyStore: aliceStore, crypto: crypto);
      final bob = PulseKeyManager(keyStore: bobStore, crypto: crypto);

      const id = 'pair-1';
      final aliceKey = await alice.getOrCreate(id);
      final bobKey = await bob.getOrCreate(id);

      await alice.setPeerPublicKey(id, bobKey.publicKey);
      await bob.setPeerPublicKey(id, aliceKey.publicKey);

      final aliceSecret = await alice.sharedSecret(id);
      final bobSecret = await bob.sharedSecret(id);

      expect(aliceSecret, isNotNull);
      expect(bobSecret, isNotNull);
      expect(aliceSecret!.length, 32);
      expect(aliceSecret, bobSecret);
    });

    test('erase wipes seed, public key and peer public key', () async {
      const id = 'conn-3';
      final pair = await manager.getOrCreate(id);
      await manager.setPeerPublicKey(id, pair.publicKey);

      // Sanity: secret derives before erase.
      expect(await manager.sharedSecret(id), isNotNull);

      await manager.erase(id);

      // After erasing every saved byte, sharedSecret can no longer derive.
      expect(await manager.peerPublicKey(id), isNull);
      // getOrCreate post-erase produces a *new* key pair.
      final regenerated = await manager.getOrCreate(id);
      expect(regenerated.publicKey, isNot(pair.publicKey));
    });

    test('setPeerPublicKey rejects wrong-length keys', () async {
      const id = 'conn-4';
      await manager.getOrCreate(id);
      expect(
        () => manager.setPeerPublicKey(id, List<int>.filled(31, 0)),
        throwsArgumentError,
      );
    });
  });
}
