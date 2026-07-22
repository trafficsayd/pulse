import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:pulse/core/storage/secure_key_store.dart';
import 'package:pulse/features/pairing/application/pairing_controller.dart';
import 'package:pulse/features/pairing/data/ble_pairing_rendezvous.dart';
import 'package:pulse/features/transport/ble/ble_client.dart';
import 'package:pulse/features/transport/ble/packet_codec.dart';
import 'package:pulse/features/transport/ble/real_ble_peripheral.dart';
import 'package:pulse/features/transport/webrtc/signaling_client.dart';

/// In-memory stand-in for the Android GATT server: the test drives central
/// writes into [centralWrites] and observes host replies via [onTx].
class _FakePeripheral implements RealBlePeripheral {
  final StreamController<Uint8List> _rx = StreamController.broadcast();
  final StreamController<bool> _central = StreamController.broadcast();
  final List<Uint8List> sentTx = <Uint8List>[];
  void Function(Uint8List bytes)? onTx;
  bool started = false;
  bool paired = false;
  bool disposed = false;

  void centralWrites(Uint8List bytes) {
    if (!_rx.isClosed) _rx.add(bytes);
  }

  @override
  Stream<Uint8List> get rxWrites => _rx.stream;

  @override
  Stream<bool> get centralConnected => _central.stream;

  @override
  Stream<BlePeripheralState> get state => const Stream.empty();

  @override
  BlePeripheralState get currentState => BlePeripheralState.idle;

  @override
  bool get isSupported => true;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<void> markPaired() async {
    paired = true;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> sendTx(Uint8List bytes) async {
    sentTx.add(bytes);
    onTx?.call(bytes);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _rx.close();
    await _central.close();
  }
}

/// In-memory stand-in for the central role: the test injects host frames via
/// [hostSends] and observes joiner writes via [onSend].
class _FakeBleClient implements BleClient {
  final StreamController<Packet> _incoming = StreamController.broadcast();
  final List<Packet> sent = <Packet>[];
  void Function(Packet packet)? onSend;
  bool connected = false;
  bool disconnectCalled = false;

  void hostSends(Packet packet) {
    if (!_incoming.isClosed) _incoming.add(packet);
  }

  @override
  Stream<Packet> get incoming => _incoming.stream;

  @override
  Stream<BleClientState> get state => const Stream.empty();

  @override
  BleClientState get currentState =>
      connected ? BleClientState.connected : BleClientState.idle;

  @override
  Future<void> connect({
    Duration scanTimeout = const Duration(seconds: 10),
    Map<String, String> reconnectTokens = const {},
  }) async {
    connected = true;
  }

  @override
  Future<void> send(Packet packet) async {
    sent.add(packet);
    onSend?.call(packet);
  }

  @override
  Future<void> disconnect() async {
    disconnectCalled = true;
  }
}

Packet _hello({String code = '123456', String pub = 'am9pbmVyLXB1Yg', int? v}) {
  return Packet(
    kind: kBlePairHelloKind,
    payload: Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'v': v ?? kBlePairProtocolVersion,
          'code': code,
          'pub': pub,
        }),
      ),
    ),
  );
}

Map<String, Object?> _body(Packet packet) =>
    (jsonDecode(utf8.decode(packet.payload)) as Map).cast<String, Object?>();

void main() {
  group('BleHostRendezvous', () {
    test('answers a correct hello with pair_reply and completes', () async {
      final peripheral = _FakePeripheral();
      final host = BleHostRendezvous(peripheralFactory: () => peripheral);

      final future = host.waitForPartner(
        pairingCode: '123456',
        localPublicKeyBase64: 'aG9zdC1wdWI',
        timeout: const Duration(seconds: 5),
      );
      // Wait until advertising is up, then simulate the joiner's write.
      while (!peripheral.started) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      peripheral.centralWrites(packetEncoder(_hello()));

      final result = await future;
      expect(result.peerPublicKeyBase64, 'am9pbmVyLXB1Yg');
      expect(result.connectionId, isNotEmpty);
      expect(result.signalingToken, hasLength(32));

      expect(peripheral.sentTx, hasLength(1));
      final reply = packetDecoder(peripheral.sentTx.single);
      expect(reply.kind, kBlePairReplyKind);
      final body = _body(reply);
      expect(body['pub'], 'aG9zdC1wdWI');
      expect(body['cid'], result.connectionId);
      expect(body['token'], result.signalingToken);

      expect(peripheral.paired, isTrue);
      expect(peripheral.disposed, isTrue);
    });

    test('NACKs a wrong code and keeps waiting for the right one', () async {
      final peripheral = _FakePeripheral();
      final host = BleHostRendezvous(peripheralFactory: () => peripheral);

      final future = host.waitForPartner(
        pairingCode: '123456',
        localPublicKeyBase64: 'aG9zdC1wdWI',
        timeout: const Duration(seconds: 5),
      );
      while (!peripheral.started) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      peripheral.centralWrites(packetEncoder(_hello(code: '999999')));
      while (peripheral.sentTx.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final nack = packetDecoder(peripheral.sentTx.first);
      expect(nack.kind, kBlePairNackKind);
      expect(_body(nack)['reason'], 'code_mismatch');

      // The correct code still succeeds afterwards.
      peripheral.centralWrites(packetEncoder(_hello()));
      final result = await future;
      expect(result.peerPublicKeyBase64, 'am9pbmVyLXB1Yg');
    });

    test('ignores foreign frames and NACKs a bad protocol version', () async {
      final peripheral = _FakePeripheral();
      final host = BleHostRendezvous(peripheralFactory: () => peripheral);

      final future = host.waitForPartner(
        pairingCode: '123456',
        localPublicKeyBase64: 'aG9zdC1wdWI',
        timeout: const Duration(seconds: 5),
      );
      while (!peripheral.started) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      // Corrupt bytes and unrelated packet kinds must not kill the wait.
      peripheral.centralWrites(Uint8List.fromList(<int>[1, 2, 3]));
      peripheral.centralWrites(
        packetEncoder(
          Packet(kind: 'mode_event', payload: Uint8List(4)),
        ),
      );
      // Future protocol version → bad_hello NACK.
      peripheral.centralWrites(packetEncoder(_hello(v: 2)));
      while (peripheral.sentTx.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(
          _body(packetDecoder(peripheral.sentTx.first))['reason'], 'bad_hello');

      peripheral.centralWrites(packetEncoder(_hello()));
      await future;
    });

    test('times out when nobody pairs and releases the radio', () async {
      final peripheral = _FakePeripheral();
      final host = BleHostRendezvous(peripheralFactory: () => peripheral);

      await expectLater(
        host.waitForPartner(
          pairingCode: '123456',
          localPublicKeyBase64: 'aG9zdC1wdWI',
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(peripheral.disposed, isTrue);
      expect(peripheral.paired, isFalse);
    });
  });

  group('BleJoinerRendezvous', () {
    test('sends pair_hello and parses the reply', () async {
      final client = _FakeBleClient();
      client.onSend = (packet) {
        expect(packet.kind, kBlePairHelloKind);
        final body = _body(packet);
        expect(body['code'], '123456');
        expect(body['pub'], 'am9pbmVyLXB1Yg');
        client.hostSends(
          Packet(
            kind: kBlePairReplyKind,
            payload: Uint8List.fromList(
              utf8.encode(
                jsonEncode(<String, Object?>{
                  'v': kBlePairProtocolVersion,
                  'pub': 'aG9zdC1wdWI',
                  'cid': 'cid-1',
                  'token': 'tok-1',
                }),
              ),
            ),
          ),
        );
      };

      final joiner = BleJoinerRendezvous(clientFactory: () => client);
      final result = await joiner.exchange(
        pairingCode: '123456',
        localPublicKeyBase64: 'am9pbmVyLXB1Yg',
        timeout: const Duration(seconds: 5),
      );
      expect(result.peerPublicKeyBase64, 'aG9zdC1wdWI');
      expect(result.connectionId, 'cid-1');
      expect(result.signalingToken, 'tok-1');
      expect(client.disconnectCalled, isTrue);
    });

    test('surfaces a NACK as BlePairingRejectedException', () async {
      final client = _FakeBleClient();
      client.onSend = (_) {
        client.hostSends(
          Packet(
            kind: kBlePairNackKind,
            payload: Uint8List.fromList(
              utf8.encode(
                jsonEncode(<String, Object?>{
                  'v': kBlePairProtocolVersion,
                  'reason': 'code_mismatch',
                }),
              ),
            ),
          ),
        );
      };

      final joiner = BleJoinerRendezvous(clientFactory: () => client);
      await expectLater(
        joiner.exchange(
          pairingCode: '000000',
          localPublicKeyBase64: 'am9pbmVyLXB1Yg',
          timeout: const Duration(seconds: 5),
        ),
        throwsA(
          isA<BlePairingRejectedException>()
              .having((e) => e.reason, 'reason', 'code_mismatch'),
        ),
      );
      expect(client.disconnectCalled, isTrue);
    });

    test('times out when the host never replies', () async {
      final client = _FakeBleClient();
      final joiner = BleJoinerRendezvous(clientFactory: () => client);
      await expectLater(
        joiner.exchange(
          pairingCode: '123456',
          localPublicKeyBase64: 'am9pbmVyLXB1Yg',
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(client.disconnectCalled, isTrue);
    });
  });

  group('offline pairing end-to-end', () {
    test(
        'two controllers derive the same pair over BLE '
        'when signaling is unreachable', () async {
      // Simulated dead internet: every signaling request explodes.
      final offlineClient = MockClient(
        (request) async => throw const SocketException('network unreachable'),
      );

      final peripheral = _FakePeripheral();
      final client = _FakeBleClient();
      // Wire the two fake radios back-to-back: joiner writes appear as RX
      // writes on the host; host notifies appear as incoming packets on the
      // joiner. Real crypto and real protocol frames in between.
      client.onSend =
          (packet) => peripheral.centralWrites(packetEncoder(packet));
      peripheral.onTx = (bytes) => client.hostSends(packetDecoder(bytes));

      ProviderContainer offlineContainer() => ProviderContainer(
            overrides: <Override>[
              secureKeyStoreProvider.overrideWithValue(
                SecureKeyStore(storage: _MemoryStorage()),
              ),
              pairingSignalingClientProvider.overrideWith(
                (ref) => SignalingClient(
                  httpClient: offlineClient,
                  baseUrl: 'https://unreachable.test',
                ),
              ),
            ],
          );

      final host = offlineContainer();
      final guest = offlineContainer();
      addTearDown(host.dispose);
      addTearDown(guest.dispose);

      final hostController = host.read(pairingControllerProvider.notifier)
        ..overrideForTesting(
          bleHostSupported: true,
          bleHostFactory: () =>
              BleHostRendezvous(peripheralFactory: () => peripheral),
        );
      final guestController = guest.read(pairingControllerProvider.notifier)
        ..overrideForTesting(
          bleJoinerSupported: true,
          bleJoinerFactory: () =>
              BleJoinerRendezvous(clientFactory: () => client),
        );

      final hostFuture = hostController.startHostHandshake(
        timeout: const Duration(seconds: 5),
      );
      await _waitFor(host, (s) => s.pairingCode != null);
      final code = host.read(pairingControllerProvider).pairingCode!;

      await guestController.joinHandshake(
        code,
        timeout: const Duration(seconds: 5),
      );
      await hostFuture;

      final hostState = host.read(pairingControllerProvider);
      final guestState = guest.read(pairingControllerProvider);
      expect(hostState.phase, PairingPhase.awaitingConfirmation);
      expect(guestState.phase, PairingPhase.awaitingConfirmation);
      expect(hostState.sasCode, isNotNull);
      expect(hostState.sasCode, guestState.sasCode);
      expect(hostState.connectionId, guestState.connectionId);
      expect(hostState.signalingToken, guestState.signalingToken);

      final hostKeys =
          await hostController.confirmAndPersist(sasConfirmed: true);
      final guestKeys =
          await guestController.confirmAndPersist(sasConfirmed: true);
      expect(hostKeys, isNotNull);
      expect(hostKeys?.connectionId, guestKeys?.connectionId);
      expect(hostKeys?.symmetricKey, guestKeys?.symmetricKey);
      // Forward secrecy holds on the BLE path too.
      expect(hostKeys?.localPrivateKey, isNull);
      expect(guestKeys?.localPrivateKey, isNull);
    });

    test('joiner with a wrong code fails cleanly over BLE', () async {
      final offlineClient = MockClient(
        (request) async => throw const SocketException('network unreachable'),
      );

      final peripheral = _FakePeripheral();
      final client = _FakeBleClient();
      client.onSend =
          (packet) => peripheral.centralWrites(packetEncoder(packet));
      peripheral.onTx = (bytes) => client.hostSends(packetDecoder(bytes));

      final host = ProviderContainer(
        overrides: <Override>[
          secureKeyStoreProvider.overrideWithValue(
            SecureKeyStore(storage: _MemoryStorage()),
          ),
          pairingSignalingClientProvider.overrideWith(
            (ref) => SignalingClient(
              httpClient: offlineClient,
              baseUrl: 'https://unreachable.test',
            ),
          ),
        ],
      );
      final guest = ProviderContainer(
        overrides: <Override>[
          secureKeyStoreProvider.overrideWithValue(
            SecureKeyStore(storage: _MemoryStorage()),
          ),
          pairingSignalingClientProvider.overrideWith(
            (ref) => SignalingClient(
              httpClient: offlineClient,
              baseUrl: 'https://unreachable.test',
            ),
          ),
        ],
      );
      addTearDown(host.dispose);
      addTearDown(guest.dispose);

      host.read(pairingControllerProvider.notifier).overrideForTesting(
            bleHostSupported: true,
            bleHostFactory: () =>
                BleHostRendezvous(peripheralFactory: () => peripheral),
          );
      final guestController = guest.read(pairingControllerProvider.notifier)
        ..overrideForTesting(
          bleJoinerSupported: true,
          bleJoinerFactory: () =>
              BleJoinerRendezvous(clientFactory: () => client),
        );

      unawaited(
        host.read(pairingControllerProvider.notifier).startHostHandshake(
              timeout: const Duration(seconds: 5),
            ),
      );
      await _waitFor(host, (s) => s.pairingCode != null);
      final realCode = host.read(pairingControllerProvider).pairingCode!;
      final wrongCode = realCode == '111111' ? '222222' : '111111';

      await guestController.joinHandshake(
        wrongCode,
        timeout: const Duration(seconds: 5),
      );

      final guestState = guest.read(pairingControllerProvider);
      expect(guestState.phase, PairingPhase.failed);
      expect(guestState.error, isA<BlePairingRejectedException>());
      // Host keeps advertising — its window is still open.
      expect(
        host.read(pairingControllerProvider).phase,
        PairingPhase.awaitingPartner,
      );
      host.read(pairingControllerProvider.notifier).reset();
    });
  });
}

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _waitFor(
  ProviderContainer container,
  bool Function(PairingState state) test,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (DateTime.now().isBefore(deadline)) {
    if (test(container.read(pairingControllerProvider))) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TimeoutException('Pairing state did not satisfy predicate');
}
