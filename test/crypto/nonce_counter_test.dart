import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/storage/secure_key_store.dart';
import 'package:pulse/features/crypto/nonce_counter.dart';

/// In-memory [FlutterSecureStorage] stand-in for tests. The real
/// implementation needs platform channels which are unavailable in the
/// `flutter test` host.
class _MemoryStorage implements FlutterSecureStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.clear();
  }

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _values.containsKey(key);

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      Map<String, String>.from(_values);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('NonceCounter', () {
    late SecureKeyStore store;
    late NonceCounter counter;

    setUp(() {
      store = SecureKeyStore(storage: _MemoryStorage());
      counter = NonceCounter(storage: store, storageKey: 'test::out');
    });

    test('next() increments monotonically and starts at 1', () async {
      expect(await counter.next(), 1);
      expect(await counter.next(), 2);
      expect(await counter.next(), 3);
    });

    test('peek() returns the next value without advancing', () async {
      expect(await counter.peek(), 1);
      expect(await counter.peek(), 1);
      expect(await counter.next(), 1);
      expect(await counter.peek(), 2);
      expect(await counter.next(), 2);
    });

    test('counter survives a restore() across instances', () async {
      expect(await counter.next(), 1);
      expect(await counter.next(), 2);

      final reloaded = NonceCounter(
        storage: store,
        storageKey: 'test::out',
      );
      await reloaded.restore();
      expect(await reloaded.peek(), 3);
      expect(await reloaded.next(), 3);
      expect(await reloaded.next(), 4);
    });

    test('resetToZero clears in-memory and persisted state', () async {
      await counter.next();
      await counter.next();
      await counter.resetToZero();
      expect(counter.lastUsed, 0);

      final reloaded = NonceCounter(
        storage: store,
        storageKey: 'test::out',
      );
      await reloaded.restore();
      expect(reloaded.lastUsed, 0);
      expect(await reloaded.next(), 1);
    });

    test(
      'restore() throws NonceRollbackException when storage is rolled back',
      () async {
        // Burn three nonces — HWM is now 3 and current is 3.
        expect(await counter.next(), 1);
        expect(await counter.next(), 2);
        expect(await counter.next(), 3);

        // Simulate an attacker (or a stale Android backup) rewriting the
        // "current" slot back to 1, leaving the HWM at 3. A fresh
        // counter instance must refuse to load.
        await store.writeString('test::out', '1');

        final tampered = NonceCounter(
          storage: store,
          storageKey: 'test::out',
        );
        await expectLater(
          tampered.restore(),
          throwsA(isA<NonceRollbackException>()),
        );
      },
    );

    test(
      'next() refuses to mint nonces once a rollback is detected',
      () async {
        await counter.next();
        await counter.next();
        await store.writeString('test::out', '0');

        final tampered = NonceCounter(
          storage: store,
          storageKey: 'test::out',
        );
        await expectLater(
          tampered.next(),
          throwsA(isA<NonceRollbackException>()),
        );
      },
    );

    test('wipe() removes both the counter and its high-water mark', () async {
      await counter.next();
      await counter.next();
      await counter.wipe();

      final reloaded = NonceCounter(
        storage: store,
        storageKey: 'test::out',
      );
      // Both slots are gone, so restore sees a fresh counter at zero
      // and next() starts at 1 again.
      await reloaded.restore();
      expect(reloaded.lastUsed, 0);
      expect(await reloaded.next(), 1);
    });

    test('two counters with different storage keys are independent', () async {
      final other = NonceCounter(storage: store, storageKey: 'test::in');
      expect(await counter.next(), 1);
      expect(await counter.next(), 2);
      expect(await other.next(), 1);
      expect(await other.peek(), 2);
      expect(await counter.peek(), 3);
    });

    test('reserved ranges skip unused nonces after a process restart',
        () async {
      expect(await counter.next(reservationSize: 4), 1);
      expect(await counter.next(reservationSize: 4), 2);
      expect(await counter.peek(), 3);

      final restarted = NonceCounter(
        storage: store,
        storageKey: 'test::out',
      );
      // Values 3 and 4 were durably reserved before value 1 was emitted. A
      // restart skips them, guaranteeing they can never be reused.
      expect(await restarted.next(), 5);
    });

    test('advanceTo skips a lost inbound range but never moves backwards',
        () async {
      await counter.advanceTo(7);
      expect(counter.lastUsed, 7);
      expect(await counter.peek(), 8);
      await expectLater(counter.advanceTo(6), throwsStateError);

      final reloaded = NonceCounter(
        storage: store,
        storageKey: 'test::out',
      );
      await reloaded.restore();
      expect(reloaded.lastUsed, 7);
    });

    test('advanceTo can durably reserve an inbound replay window', () async {
      await counter.advanceTo(10, reservationSize: 4);
      expect(counter.lastUsed, 10);
      await counter.advanceTo(11, reservationSize: 4);
      expect(counter.lastUsed, 11);

      final restarted = NonceCounter(
        storage: store,
        storageKey: 'test::out',
      );
      await restarted.restore();
      expect(restarted.lastUsed, 13);
      await expectLater(restarted.advanceTo(12), throwsStateError);
    });
  });
}
