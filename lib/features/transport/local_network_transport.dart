import 'dart:async';

import 'transport.dart';

/// Local-network transport (placeholder).
///
/// On the production build this advertises and discovers the partner via
/// mDNS/Bonjour over the same Wi-Fi LAN. It carries the same encrypted
/// payloads as [BleTransport] but with much higher throughput, used for
/// continuous audio and tactile feedback in active sessions.
class LocalNetworkTransport implements Transport {
  LocalNetworkTransport();

  // ignore: close_sinks
  final _incoming = StreamController<TransportPacket>.broadcast();
  // ignore: close_sinks
  final _state = StreamController<TransportKind>.broadcast();
  bool _connected = false;

  @override
  TransportKind get kind => TransportKind.localNetwork;

  @override
  bool get isConnected => _connected;

  @override
  Stream<TransportPacket> get incoming => _incoming.stream;

  @override
  Stream<TransportKind> get state => _state.stream;

  @override
  Future<void> connect({required Map<String, String> reconnectTokens}) async {
    // TODO(transport): publish + browse a Bonjour service whose name is
    // derived from reconnectTokens['signalingToken'].
    _connected = false;
    _state.add(TransportKind.searching);
  }

  @override
  Future<void> send(TransportPacket packet) async {}

  @override
  Future<void> disconnect() async {
    _connected = false;
    _state.add(TransportKind.searching);
  }
}
