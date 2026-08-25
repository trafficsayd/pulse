import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/transport/transport.dart';
import 'package:pulse/features/transport/transport_manager.dart';

void main() {
  test('send falls through when the preferred transport rejects a write',
      () async {
    final direct = _FakeTransport(
      TransportKind.direct,
      onSend: (_) async => throw StateError('radio disappeared'),
    );
    final local = _FakeTransport(TransportKind.localNetwork);
    final relay = _FakeTransport(TransportKind.relay);
    final manager = TransportManager(
      ble: direct,
      localNetwork: local,
      relay: relay,
    );
    addTearDown(manager.dispose);

    final packet = TransportPacket(kind: 'mode_event', payload: Uint8List(1));
    await manager.send(packet);

    expect(direct.sent, hasLength(1));
    expect(local.sent, hasLength(1));
    expect(relay.sent, isEmpty);
    expect(manager.current, TransportKind.localNetwork);
  });
}

class _FakeTransport implements Transport {
  _FakeTransport(this.kind, {this.onSend});

  @override
  final TransportKind kind;
  final Future<void> Function(TransportPacket packet)? onSend;
  final List<TransportPacket> sent = [];

  @override
  bool isConnected = true;

  @override
  Stream<TransportPacket> get incoming => const Stream.empty();

  @override
  Stream<TransportKind> get state => const Stream.empty();

  @override
  Future<void> connect({required Map<String, String> reconnectTokens}) async {}

  @override
  Future<void> disconnect() async => isConnected = false;

  @override
  Future<void> send(TransportPacket packet) async {
    sent.add(packet);
    await onSend?.call(packet);
  }
}
