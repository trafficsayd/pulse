import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/storage/secure_key_store.dart';
import 'package:pulse/features/crypto/nonce_counter.dart';
import 'package:pulse/features/crypto/pair_channel.dart';
import 'package:pulse/features/transport/local_network_transport.dart';
import 'package:pulse/features/transport/transport.dart';

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

class _TransportChannel implements RawByteChannel {
  _TransportChannel(this.transport);

  final LocalNetworkTransport transport;

  @override
  Stream<Uint8List> get incoming =>
      transport.incoming.map((packet) => packet.payload);

  @override
  Future<void> send(Uint8List bytes) => transport.send(
        TransportPacket(kind: 'sealed', payload: bytes),
      );

  @override
  Future<void> close() => transport.disconnect();
}

class _MemoryRawChannel implements RawByteChannel {
  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();
  _MemoryRawChannel? peer;
  bool dropNext = false;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  Future<void> send(Uint8List bytes) async {
    if (dropNext) {
      dropNext = false;
      return;
    }
    peer?._incoming.add(Uint8List.fromList(bytes));
  }

  @override
  Future<void> close() => _incoming.close();
}

void main() {
  test('PairChannel sends encrypted bytes over two local transports', () async {
    final hostTransport = LocalNetworkTransport();
    final guestTransport = LocalNetworkTransport();
    addTearDown(hostTransport.disconnect);
    addTearDown(guestTransport.disconnect);

    final token = 'pair-channel-test-${DateTime.now().microsecondsSinceEpoch}';
    final hostConnected = _waitConnected(hostTransport);
    final guestConnected = _waitConnected(guestTransport);

    await hostTransport.connect(reconnectTokens: {'signalingToken': token});
    await guestTransport.connect(reconnectTokens: {'signalingToken': token});
    await Future.wait([hostConnected, guestConnected]);

    final key = SecretKey(List<int>.generate(32, (i) => i));
    final hostStore = SecureKeyStore(storage: _MemoryStorage());
    final guestStore = SecureKeyStore(storage: _MemoryStorage());
    final hostChannel = PairChannel(
      transport: _TransportChannel(hostTransport),
      key: key,
      outboundCounter: NonceCounter(storage: hostStore, storageKey: 'host.out'),
      inboundCounter: NonceCounter(storage: hostStore, storageKey: 'host.in'),
    );
    final guestChannel = PairChannel(
      transport: _TransportChannel(guestTransport),
      key: key,
      outboundCounter:
          NonceCounter(storage: guestStore, storageKey: 'guest.out'),
      inboundCounter: NonceCounter(storage: guestStore, storageKey: 'guest.in'),
    );
    addTearDown(hostChannel.close);
    addTearDown(guestChannel.close);

    await Future.wait([hostChannel.start(), guestChannel.start()]);

    final received =
        guestChannel.incoming.first.timeout(const Duration(seconds: 3));
    await hostChannel.send(Uint8List.fromList([7, 8, 9]));

    final packet = await received;
    expect(packet.payload, [7, 8, 9]);
    expect(packet.nonceCounter, 1);
  });

  test('PairChannel recovers when a packet is lost during handover', () async {
    final hostRaw = _MemoryRawChannel();
    final guestRaw = _MemoryRawChannel();
    hostRaw.peer = guestRaw;
    guestRaw.peer = hostRaw;
    final key = SecretKey(List<int>.generate(32, (i) => i));
    final hostStore = SecureKeyStore(storage: _MemoryStorage());
    final guestStore = SecureKeyStore(storage: _MemoryStorage());
    final host = PairChannel(
      transport: hostRaw,
      key: key,
      outboundCounter: NonceCounter(
        storage: hostStore,
        storageKey: 'gap.host.out',
      ),
      inboundCounter: NonceCounter(
        storage: hostStore,
        storageKey: 'gap.host.in',
      ),
    );
    final guest = PairChannel(
      transport: guestRaw,
      key: key,
      outboundCounter: NonceCounter(
        storage: guestStore,
        storageKey: 'gap.guest.out',
      ),
      inboundCounter: NonceCounter(
        storage: guestStore,
        storageKey: 'gap.guest.in',
      ),
    );
    addTearDown(host.close);
    addTearDown(guest.close);
    await Future.wait(<Future<void>>[host.start(), guest.start()]);

    hostRaw.dropNext = true;
    await host.send(Uint8List.fromList(<int>[1]));
    final received = guest.incoming.first.timeout(const Duration(seconds: 2));
    await host.send(Uint8List.fromList(<int>[2]));

    final packet = await received;
    expect(packet.payload, <int>[2]);
    expect(packet.nonceCounter, 2);
  });

  test('PairChannel serializes a burst of concurrent gesture packets',
      () async {
    final hostRaw = _MemoryRawChannel();
    final guestRaw = _MemoryRawChannel();
    hostRaw.peer = guestRaw;
    guestRaw.peer = hostRaw;
    final key = SecretKey(List<int>.generate(32, (i) => i));
    final hostStore = SecureKeyStore(storage: _MemoryStorage());
    final guestStore = SecureKeyStore(storage: _MemoryStorage());
    final host = PairChannel(
      transport: hostRaw,
      key: key,
      outboundCounter: NonceCounter(
        storage: hostStore,
        storageKey: 'burst.host.out',
      ),
      inboundCounter: NonceCounter(
        storage: hostStore,
        storageKey: 'burst.host.in',
      ),
    );
    final guest = PairChannel(
      transport: guestRaw,
      key: key,
      outboundCounter: NonceCounter(
        storage: guestStore,
        storageKey: 'burst.guest.out',
      ),
      inboundCounter: NonceCounter(
        storage: guestStore,
        storageKey: 'burst.guest.in',
      ),
    );
    addTearDown(host.close);
    addTearDown(guest.close);
    await Future.wait(<Future<void>>[host.start(), guest.start()]);

    const packetCount = 40;
    final received = guest.incoming.take(packetCount).toList();
    await Future.wait(
      List<Future<void>>.generate(
        packetCount,
        (index) => host.send(Uint8List.fromList(<int>[index])),
      ),
    );

    final packets = await received.timeout(const Duration(seconds: 5));
    expect(packets.map((packet) => packet.payload.single),
        orderedEquals(List<int>.generate(packetCount, (index) => index)));
    expect(packets.map((packet) => packet.nonceCounter),
        orderedEquals(List<int>.generate(packetCount, (index) => index + 1)));
  });
}

Future<void> _waitConnected(LocalNetworkTransport transport) async {
  if (transport.isConnected) return;
  await transport.state
      .firstWhere((state) => state == TransportKind.localNetwork)
      .timeout(const Duration(seconds: 5));
}
