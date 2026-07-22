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
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
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
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.clear();
  }

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _values.containsKey(key);

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
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
}

Future<void> _waitConnected(LocalNetworkTransport transport) async {
  if (transport.isConnected) return;
  await transport.state
      .firstWhere((state) => state == TransportKind.localNetwork)
      .timeout(const Duration(seconds: 5));
}
