import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/transport/transport.dart';
import 'package:pulse/features/transport/transport_byte_adapter.dart';
import 'package:pulse/features/transport/transport_manager.dart';

/// Minimal fake [Transport] that records sent packets and lets tests push
/// incoming packets and state transitions.
class _FakeTransport implements Transport {
  _FakeTransport();

  final TransportKind _kind = TransportKind.direct;
  final List<TransportPacket> sent = [];
  // ignore: close_sinks
  final _incoming = StreamController<TransportPacket>.broadcast();
  // ignore: close_sinks
  final _state = StreamController<TransportKind>.broadcast();
  bool _connected = true;

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
    _connected = true;
    _state.add(kind);
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

  void pushIncoming(TransportPacket packet) => _incoming.add(packet);

  Future<void> dispose() async {
    await _incoming.close();
    await _state.close();
  }
}

void main() {
  group('TransportByteAdapter', () {
    late TransportManager manager;
    late TransportByteAdapter adapter;
    late _FakeTransport fake;

    setUp(() async {
      fake = _FakeTransport();
      manager = TransportManager(ble: fake);
      adapter = TransportByteAdapter(manager: manager);
      await manager.attach(reconnectTokens: {});
    });

    tearDown(() async {
      await manager.dispose();
      await fake.dispose();
    });

    test('send wraps bytes in a TransportPacket with sealed kind', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      await adapter.send(bytes);
      expect(fake.sent, hasLength(1));
      expect(fake.sent.first.kind, TransportByteAdapter.sealedKind);
      expect(fake.sent.first.payload, bytes);
    });

    test('incoming unwraps payload from transport packets', () async {
      final completer = Completer<Uint8List>();
      adapter.incoming.listen((data) {
        if (!completer.isCompleted) completer.complete(data);
      });

      final payload = Uint8List.fromList([10, 20, 30]);
      fake.pushIncoming(TransportPacket(kind: 'sealed', payload: payload));

      final received = await completer.future.timeout(
        const Duration(seconds: 2),
      );
      expect(received, payload);
    });

    test('close is a no-op', () async {
      // Should not throw.
      await adapter.close();
    });
  });
}
