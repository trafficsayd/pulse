import 'dart:async';

import 'ble_client.dart';
import 'packet_codec.dart';

/// Inert [BleClient] used by `BleTransport` whenever the real BLE stack
/// is disabled (development builds, widget tests, headless CI).
///
/// It honours the interface contract — `incoming` never emits, `send`
/// silently succeeds, `connect` parks the client in [BleClientState.idle]
/// — so the surrounding `TransportManager` can pretend BLE is just
/// "permanently searching" without taking any code paths that touch the
/// radio.
class PlaceholderBleClient implements BleClient {
  PlaceholderBleClient();

  final StreamController<Packet> _incoming =
      StreamController<Packet>.broadcast();
  final StreamController<BleClientState> _state =
      StreamController<BleClientState>.broadcast();
  BleClientState _currentState = BleClientState.idle;
  bool _disposed = false;

  @override
  Stream<Packet> get incoming => _incoming.stream;

  @override
  Stream<BleClientState> get state => _state.stream;

  @override
  BleClientState get currentState => _currentState;

  @override
  Future<void> connect({
    Duration scanTimeout = const Duration(seconds: 10),
    Map<String, String> reconnectTokens = const {},
  }) async {
    // Pretend we are scanning forever — the manager treats this as
    // "searching" and falls back to local network / relay.
    if (!_disposed && _currentState != BleClientState.scanning) {
      _currentState = BleClientState.scanning;
      _state.add(_currentState);
    }
  }

  @override
  Future<void> send(Packet packet) async {
    // Drop on the floor — the placeholder never reaches a real peer.
  }

  @override
  Future<void> disconnect() async {
    if (_disposed) return;
    if (_currentState != BleClientState.idle) {
      _currentState = BleClientState.idle;
      _state.add(_currentState);
    }
  }

  /// Release stream controllers. Safe to call multiple times.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _incoming.close().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
    await _state.close().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
  }
}
