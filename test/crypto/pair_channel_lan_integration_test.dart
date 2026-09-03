import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/storage/secure_key_store.dart';
import 'package:pulse/features/crypto/aes_gcm_sealer.dart';
import 'package:pulse/features/crypto/nonce_counter.dart';
import 'package:pulse/features/crypto/pair_channel.dart';
import 'package:pulse/features/crypto/pair_channel_nonce_domains.dart';
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
  final List<Uint8List> sentPackets = <Uint8List>[];

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  Future<void> send(Uint8List bytes) async {
    sentPackets.add(Uint8List.fromList(bytes));
    if (dropNext) {
      dropNext = false;
      return;
    }
    peer?._incoming.add(Uint8List.fromList(bytes));
  }

  void inject(Uint8List bytes) => _incoming.add(Uint8List.fromList(bytes));

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
    final nonceDomains = _testNonceDomains();
    final hostStore = SecureKeyStore(storage: _MemoryStorage());
    final guestStore = SecureKeyStore(storage: _MemoryStorage());
    final hostChannel = PairChannel(
      transport: _TransportChannel(hostTransport),
      key: key,
      nonceDomains: nonceDomains.$1,
      outboundCounter: NonceCounter(storage: hostStore, storageKey: 'host.out'),
      inboundCounter: NonceCounter(storage: hostStore, storageKey: 'host.in'),
    );
    final guestChannel = PairChannel(
      transport: _TransportChannel(guestTransport),
      key: key,
      nonceDomains: nonceDomains.$2,
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
    final nonceDomains = _testNonceDomains();
    final hostStore = SecureKeyStore(storage: _MemoryStorage());
    final guestStore = SecureKeyStore(storage: _MemoryStorage());
    final host = PairChannel(
      transport: hostRaw,
      key: key,
      nonceDomains: nonceDomains.$1,
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
      nonceDomains: nonceDomains.$2,
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
    final nonceDomains = _testNonceDomains();
    final hostStore = SecureKeyStore(storage: _MemoryStorage());
    final guestStore = SecureKeyStore(storage: _MemoryStorage());
    final host = PairChannel(
      transport: hostRaw,
      key: key,
      nonceDomains: nonceDomains.$1,
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
      nonceDomains: nonceDomains.$2,
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

  test('simultaneous first packets use separate nonce domains', () async {
    final hostRaw = _MemoryRawChannel();
    final guestRaw = _MemoryRawChannel();
    hostRaw.peer = guestRaw;
    guestRaw.peer = hostRaw;
    final key = SecretKey(List<int>.generate(32, (i) => i));
    final nonceDomains = _testNonceDomains();
    final hostStore = SecureKeyStore(storage: _MemoryStorage());
    final guestStore = SecureKeyStore(storage: _MemoryStorage());
    final host = PairChannel(
      transport: hostRaw,
      key: key,
      nonceDomains: nonceDomains.$1,
      outboundCounter: NonceCounter(
        storage: hostStore,
        storageKey: 'duplex.host.out',
      ),
      inboundCounter: NonceCounter(
        storage: hostStore,
        storageKey: 'duplex.host.in',
      ),
    );
    final guest = PairChannel(
      transport: guestRaw,
      key: key,
      nonceDomains: nonceDomains.$2,
      outboundCounter: NonceCounter(
        storage: guestStore,
        storageKey: 'duplex.guest.out',
      ),
      inboundCounter: NonceCounter(
        storage: guestStore,
        storageKey: 'duplex.guest.in',
      ),
    );
    addTearDown(host.close);
    addTearDown(guest.close);
    await Future.wait(<Future<void>>[host.start(), guest.start()]);

    final atHost = host.incoming.first;
    final atGuest = guest.incoming.first;
    final samePlaintext = Uint8List.fromList(<int>[1, 2, 3]);
    await Future.wait(<Future<void>>[
      host.send(samePlaintext),
      guest.send(samePlaintext),
    ]);

    expect((await atHost).payload, <int>[1, 2, 3]);
    expect((await atGuest).payload, <int>[1, 2, 3]);
    final hostWire = hostRaw.sentPackets.single;
    final guestWire = guestRaw.sentPackets.single;
    expect(
      hostWire.sublist(0, AesGcmSealer.nonceLength),
      isNot(equals(guestWire.sublist(0, AesGcmSealer.nonceLength))),
      reason: 'opposite directions must never share a key/nonce pair',
    );
  });

  test('a reflected outbound packet fails inbound authentication', () async {
    final raw = _MemoryRawChannel();
    final sink = _MemoryRawChannel();
    raw.peer = sink;
    final key = SecretKey(List<int>.generate(32, (i) => i));
    final nonceDomains = _testNonceDomains();
    final store = SecureKeyStore(storage: _MemoryStorage());
    final channel = PairChannel(
      transport: raw,
      key: key,
      nonceDomains: nonceDomains.$1,
      outboundCounter: NonceCounter(
        storage: store,
        storageKey: 'reflect.out',
      ),
      inboundCounter: NonceCounter(
        storage: store,
        storageKey: 'reflect.in',
      ),
    );
    addTearDown(channel.close);
    addTearDown(sink.close);
    await channel.start();

    await channel.send(Uint8List.fromList(<int>[4, 5, 6]));
    final error = channel.errors.first;
    raw.inject(raw.sentPackets.single);

    await expectLater(error, completion(isA<StateError>()));
  });

  test('upgraded channel interoperates with a legacy v1 peer', () async {
    final upgradedRaw = _MemoryRawChannel();
    final legacyRaw = _MemoryRawChannel();
    upgradedRaw.peer = legacyRaw;
    legacyRaw.peer = upgradedRaw;
    final key = SecretKey(List<int>.generate(32, (i) => i));
    final nonceDomains = _testNonceDomains();
    final store = SecureKeyStore(storage: _MemoryStorage());
    final upgraded = PairChannel(
      transport: upgradedRaw,
      key: key,
      nonceDomains: nonceDomains.$1,
      outboundCounter: NonceCounter(
        storage: store,
        storageKey: 'compat.out',
      ),
      inboundCounter: NonceCounter(
        storage: store,
        storageKey: 'compat.in',
      ),
    );
    addTearDown(upgraded.close);
    addTearDown(legacyRaw.close);
    await upgraded.start();

    final legacyPacketFuture = legacyRaw.incoming.first;
    await upgraded.send(Uint8List.fromList(<int>[7, 8, 9]));
    final upgradedPacket = await legacyPacketFuture;
    final upgradedWireCounter = AesGcmSealer.counterFromNonce(
      upgradedPacket.sublist(0, AesGcmSealer.nonceLength),
    );
    final openedByLegacy = await AesGcmSealer().open(
      upgradedPacket,
      key: key,
      expectedNonceCounter: upgradedWireCounter,
    );
    expect(openedByLegacy, <int>[7, 8, 9]);

    final receivedByUpgraded = upgraded.incoming.first;
    final legacyPacket = await AesGcmSealer().seal(
      Uint8List.fromList(<int>[4, 5, 6]),
      key: key,
      nonceCounter: 1,
    );
    legacyRaw.send(legacyPacket);
    expect((await receivedByUpgraded).payload, <int>[4, 5, 6]);
  });
}

(PairChannelNonceDomains, PairChannelNonceDomains) _testNonceDomains() {
  final lowPublicKey = List<int>.generate(32, (i) => i);
  final highPublicKey = List<int>.generate(32, (i) => 255 - i);
  final deriver = PairChannelNonceDomainDeriver();
  return (
    deriver.derive(
      localPublicKey: lowPublicKey,
      peerPublicKey: highPublicKey,
    ),
    deriver.derive(
      localPublicKey: highPublicKey,
      peerPublicKey: lowPublicKey,
    ),
  );
}

Future<void> _waitConnected(LocalNetworkTransport transport) async {
  if (transport.isConnected) return;
  await transport.state
      .firstWhere((state) => state == TransportKind.localNetwork)
      .timeout(const Duration(seconds: 5));
}
