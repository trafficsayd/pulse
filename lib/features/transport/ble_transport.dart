import 'dart:async';

import 'transport.dart';

/// BLE transport (placeholder).
///
/// In the production build this binds to a platform-specific BLE plugin
/// (e.g. `flutter_blue_plus` on both Android and iOS) and exposes:
///
/// - a foreground GATT connection for short signals,
/// - a `sneak_signal` characteristic that stays subscribed even when the
///   connection is in [ConnectionStatus.paused], so a partner can wake the
///   app and deliver a one-shot Sneak In without resuming a full session.
///
/// All payload bytes are encrypted before they reach this class — the BLE
/// layer never inspects them.
class BleTransport implements Transport {
  BleTransport();

  // ignore: close_sinks
  final _incoming = StreamController<TransportPacket>.broadcast();
  // ignore: close_sinks
  final _state = StreamController<TransportKind>.broadcast();
  bool _connected = false;

  @override
  TransportKind get kind => TransportKind.direct;

  @override
  bool get isConnected => _connected;

  @override
  Stream<TransportPacket> get incoming => _incoming.stream;

  @override
  Stream<TransportKind> get state => _state.stream;

  @override
  Future<void> connect({required Map<String, String> reconnectTokens}) async {
    // TODO(transport): wire flutter_blue_plus advertising/scanning here using
    // reconnectTokens['bleAddressToken'] as the rotating service identifier.
    _connected = false;
    _state.add(TransportKind.searching);
  }

  @override
  Future<void> send(TransportPacket packet) async {
    // TODO(transport): write packet.payload to the appropriate GATT
    // characteristic (mode_event vs. sneak_signal).
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _state.add(TransportKind.searching);
  }
}
