import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/transport/ble/ble_client.dart';
import 'package:pulse/features/transport/ble/packet_codec.dart';
import 'package:pulse/features/transport/ble/placeholder_ble_client.dart';
import 'package:pulse/features/transport/ble_transport.dart';
import 'package:pulse/features/transport/transport.dart';

/// Minimal scriptable [BleClient] used by [BleTransport] integration tests.
class _ScriptableBleClient implements BleClient {
  final StreamController<Packet> _incoming =
      StreamController<Packet>.broadcast();
  final StreamController<BleClientState> _state =
      StreamController<BleClientState>.broadcast();
  BleClientState _currentState = BleClientState.idle;
  final List<Packet> sent = [];
  int connectCount = 0;
  int disconnectCount = 0;

  @override
  Stream<Packet> get incoming => _incoming.stream;

  @override
  Stream<BleClientState> get state => _state.stream;

  @override
  BleClientState get currentState => _currentState;

  void setState(BleClientState s) {
    _currentState = s;
    _state.add(s);
  }

  void emit(Packet p) => _incoming.add(p);

  @override
  Future<void> connect({
    Duration scanTimeout = const Duration(seconds: 10),
    Map<String, String> reconnectTokens = const {},
  }) async {
    connectCount += 1;
    setState(BleClientState.connected);
  }

  @override
  Future<void> send(Packet packet) async {
    sent.add(packet);
  }

  @override
  Future<void> disconnect() async {
    disconnectCount += 1;
    setState(BleClientState.idle);
  }

  Future<void> dispose() async {
    await _incoming.close();
    await _state.close();
  }
}

void main() {
  group('BleTransport', () {
    test('defaults to a placeholder client when no client is supplied', () {
      // Construct via default ctor (build flag is off in tests).
      final t = BleTransport();
      addTearDown(t.dispose);
      expect(t.kind, TransportKind.direct);
      expect(t.isConnected, isFalse);
    });

    test('placeholder send() is a silent no-op', () async {
      final t = BleTransport(client: PlaceholderBleClient());
      addTearDown(t.dispose);
      await t.connect(reconnectTokens: const {});
      await t.send(
        TransportPacket(
          kind: 'mode_event',
          payload: Uint8List.fromList(const [1, 2, 3]),
        ),
      );
      // No exception is success.
    });

    test('forwards connected → searching state transitions', () async {
      final client = _ScriptableBleClient();
      addTearDown(client.dispose);
      final t = BleTransport(client: client);
      addTearDown(t.dispose);

      final states = <TransportKind>[];
      final sub = t.state.listen(states.add);

      await t.connect(reconnectTokens: const {});
      await Future<void>.delayed(Duration.zero);
      expect(t.isConnected, isTrue);
      expect(states, contains(TransportKind.direct));

      client.setState(BleClientState.disconnected);
      await Future<void>.delayed(Duration.zero);
      expect(t.isConnected, isFalse);
      expect(states.last, TransportKind.searching);

      await sub.cancel();
    });

    test('forwards incoming packets from the client', () async {
      final client = _ScriptableBleClient();
      addTearDown(client.dispose);
      final t = BleTransport(client: client);
      addTearDown(t.dispose);

      await t.connect(reconnectTokens: const {});
      final received = <TransportPacket>[];
      final sub = t.incoming.listen(received.add);

      client.emit(
        TransportPacket(
          kind: 'sneak_signal',
          payload: Uint8List.fromList(const [42]),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.kind, 'sneak_signal');

      await sub.cancel();
    });

    test('send drops on the floor when not connected', () async {
      final client = _ScriptableBleClient();
      addTearDown(client.dispose);
      final t = BleTransport(client: client);
      addTearDown(t.dispose);

      // Never called connect → not connected.
      await t.send(
        TransportPacket(
          kind: 'mode_event',
          payload: Uint8List.fromList(const [0]),
        ),
      );
      expect(client.sent, isEmpty);
    });

    test('disconnect emits searching and forwards to the client', () async {
      final client = _ScriptableBleClient();
      addTearDown(client.dispose);
      final t = BleTransport(client: client);
      addTearDown(t.dispose);

      await t.connect(reconnectTokens: const {});
      await t.disconnect();
      expect(client.disconnectCount, 1);
      expect(t.isConnected, isFalse);
    });
  });
}
