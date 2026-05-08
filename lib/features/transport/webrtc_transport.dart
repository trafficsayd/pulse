import 'dart:async';

import 'transport.dart';

/// WebRTC relay transport (placeholder).
///
/// In production this uses the `flutter_webrtc` plugin with DTLS-SRTP
/// transport. The signaling server only learns the pairing of two opaque
/// tokens — it never sees payload bytes, which are end-to-end encrypted with
/// the connection's symmetric key on top of the DTLS-SRTP layer.
class WebRtcTransport implements Transport {
  WebRtcTransport();

  // ignore: close_sinks
  final _incoming = StreamController<TransportPacket>.broadcast();
  // ignore: close_sinks
  final _state = StreamController<TransportKind>.broadcast();
  bool _connected = false;

  @override
  TransportKind get kind => TransportKind.relay;

  @override
  bool get isConnected => _connected;

  @override
  Stream<TransportPacket> get incoming => _incoming.stream;

  @override
  Stream<TransportKind> get state => _state.stream;

  @override
  Future<void> connect({required Map<String, String> reconnectTokens}) async {
    // TODO(transport): exchange SDP offers via the signaling server keyed by
    // reconnectTokens['signalingToken']; once ICE is stable, mark connected.
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
