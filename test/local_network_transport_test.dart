import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/transport/local_network_transport.dart';
import 'package:pulse/features/transport/transport.dart';

void main() {
  group('LocalNetworkTransport', () {
    test('kind is localNetwork', () {
      final transport = LocalNetworkTransport();
      expect(transport.kind, TransportKind.localNetwork);
    });

    test('isConnected is initially false', () {
      final transport = LocalNetworkTransport();
      expect(transport.isConnected, isFalse);
    });

    test('send does not throw when disconnected', () async {
      final transport = LocalNetworkTransport();
      // No socket connected — send should silently return.
      await transport.send(TransportPacket(
        kind: 'test',
        payload: Uint8List.fromList([1, 2, 3]),
      ));
    });

    test('disconnect resets state', () async {
      final transport = LocalNetworkTransport();
      await transport.disconnect();
      expect(transport.isConnected, isFalse);
    });

    test('state emits searching on connect without partner', () async {
      final transport = LocalNetworkTransport();
      final states = <TransportKind>[];
      transport.state.listen(states.add);

      // Connect with empty token — will attempt to bind but fail in test env.
      await transport.connect(reconnectTokens: {'signalingToken': ''});
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(states.first, TransportKind.searching);
      await transport.disconnect();
    });

    test('incoming stream is broadcast', () async {
      final transport = LocalNetworkTransport();
      final sub1 = transport.incoming.listen((_) {});
      final sub2 = transport.incoming.listen((_) {});
      await sub1.cancel();
      await sub2.cancel();
    });

    test('two instances connect over loopback and exchange packets', () async {
      final host = LocalNetworkTransport();
      final guest = LocalNetworkTransport();
      addTearDown(host.disconnect);
      addTearDown(guest.disconnect);

      final token =
          'local-network-test-${DateTime.now().microsecondsSinceEpoch}';
      final hostConnected = _waitConnected(host);
      final guestConnected = _waitConnected(guest);

      await host.connect(reconnectTokens: {'signalingToken': token});
      await guest.connect(reconnectTokens: {'signalingToken': token});
      await Future.wait([hostConnected, guestConnected]);

      final inbound = host.incoming.first.timeout(const Duration(seconds: 3));
      await guest.send(TransportPacket(
        kind: 'ping',
        payload: Uint8List.fromList([4, 5, 6]),
      ));

      final packet = await inbound;
      expect(packet.kind, 'ping');
      expect(packet.payload, [4, 5, 6]);
    });
  });
}

Future<void> _waitConnected(LocalNetworkTransport transport) async {
  if (transport.isConnected) return;
  await transport.state
      .firstWhere((state) => state == TransportKind.localNetwork)
      .timeout(const Duration(seconds: 5));
}
