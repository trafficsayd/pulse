import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/transport/transport.dart';
import 'package:pulse/features/transport/transport_manager.dart';

/// Fake transport whose connectivity and incoming can be controlled in tests.
class _FakeTransport implements Transport {
  _FakeTransport(this._kind, {bool connected = false})
      : _connected = connected;

  final TransportKind _kind;
  bool _connected;
  final List<TransportPacket> sent = [];

  // ignore: close_sinks
  final _incoming = StreamController<TransportPacket>.broadcast();
  // ignore: close_sinks
  final _state = StreamController<TransportKind>.broadcast();

  @override
  TransportKind get kind => _kind;

  @override
  bool get isConnected => _connected;

  @override
  Stream<TransportPacket> get incoming => _incoming.stream;

  @override
  Stream<TransportKind> get state => _state.stream;

  @override
  Future<void> connect({required Map<String, String> reconnectTokens}) async {
    // Don't auto-connect — test controls this.
  }

  @override
  Future<void> send(TransportPacket packet) async {
    sent.add(packet);
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _state.add(TransportKind.searching);
  }

  void simulateConnect() {
    _connected = true;
    _state.add(kind);
  }

  void simulateDisconnect() {
    _connected = false;
    _state.add(TransportKind.searching);
  }

  void pushPacket(TransportPacket p) => _incoming.add(p);

  Future<void> dispose() async {
    await _incoming.close();
    await _state.close();
  }
}

void main() {
  group('TransportManager', () {
    late _FakeTransport ble;
    late _FakeTransport lan;
    late _FakeTransport relay;
    late TransportManager manager;

    setUp(() {
      ble = _FakeTransport(TransportKind.direct);
      lan = _FakeTransport(TransportKind.localNetwork);
      relay = _FakeTransport(TransportKind.relay);
      manager = TransportManager(ble: ble, localNetwork: lan, relay: relay);
    });

    tearDown(() async {
      await manager.dispose();
      await ble.dispose();
      await lan.dispose();
      await relay.dispose();
    });

    test('initial state is searching', () {
      expect(manager.current, TransportKind.searching);
    });

    test('promotes to best connected transport', () async {
      await manager.attach(reconnectTokens: {});

      final states = <TransportKind>[];
      manager.state.listen(states.add);

      // LAN connects first.
      lan.simulateConnect();
      await Future<void>.delayed(Duration.zero);
      expect(manager.current, TransportKind.localNetwork);

      // BLE connects — should promote (higher priority).
      ble.simulateConnect();
      await Future<void>.delayed(Duration.zero);
      expect(manager.current, TransportKind.direct);
    });

    test('demotes when active transport disconnects', () async {
      await manager.attach(reconnectTokens: {});

      ble.simulateConnect();
      lan.simulateConnect();
      await Future<void>.delayed(Duration.zero);
      expect(manager.current, TransportKind.direct);

      // BLE disconnects — should fall back to LAN.
      ble.simulateDisconnect();
      await Future<void>.delayed(Duration.zero);
      expect(manager.current, TransportKind.localNetwork);
    });

    test('goes to searching when all transports disconnect', () async {
      await manager.attach(reconnectTokens: {});

      ble.simulateConnect();
      await Future<void>.delayed(Duration.zero);
      expect(manager.current, TransportKind.direct);

      ble.simulateDisconnect();
      await Future<void>.delayed(Duration.zero);
      expect(manager.current, TransportKind.searching);
    });

    test('aggregates incoming packets from all transports', () async {
      await manager.attach(reconnectTokens: {});

      final packets = <TransportPacket>[];
      manager.incoming.listen(packets.add);

      ble.pushPacket(TransportPacket(
        kind: 'test',
        payload: Uint8List.fromList([1]),
      ));
      lan.pushPacket(TransportPacket(
        kind: 'test',
        payload: Uint8List.fromList([2]),
      ));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(packets, hasLength(2));
    });

    test('send routes to the first connected transport', () async {
      await manager.attach(reconnectTokens: {});

      ble.simulateConnect();
      lan.simulateConnect();
      await Future<void>.delayed(Duration.zero);

      await manager.send(TransportPacket(
        kind: 'x',
        payload: Uint8List.fromList([42]),
      ));

      expect(ble.sent, hasLength(1));
      expect(lan.sent, isEmpty);
    });

    test('detach disconnects all transports', () async {
      await manager.attach(reconnectTokens: {});
      ble.simulateConnect();
      await Future<void>.delayed(Duration.zero);

      await manager.detach();
      expect(manager.current, TransportKind.searching);
    });
  });
}
