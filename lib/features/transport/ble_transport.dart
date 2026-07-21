import 'dart:async';

import 'ble/ble_client.dart';
import 'ble/ble_transport_config.dart';
import 'ble/ble_transport_exception.dart';
import 'ble/placeholder_ble_client.dart';
import 'ble/real_ble_client.dart';
import 'transport.dart';

/// BLE transport tier of the Pulse `TransportManager`.
///
/// This class is the seam between the generic [Transport] interface and
/// the role-aware [BleClient] (central or peripheral). It owns:
///
/// - the choice between the real `flutter_blue_plus`-backed
///   [RealBleClient] and the inert [PlaceholderBleClient] (gated by the
///   `useRealBleTransport` build flag — see `ble_transport_config.dart`),
/// - the bridge between the BLE-layer [BleClientState] machine and the
///   transport-layer [TransportKind] reporting,
/// - and clean disconnection so the placeholder and the real client
///   look identical from the rest of the app.
///
/// All payload bytes are encrypted before they reach this class — the
/// BLE layer never inspects them.
class BleTransport implements Transport {
  BleTransport({BleClient? client})
      : _client = client ??
            (useRealBleTransport ? RealBleClient() : PlaceholderBleClient());

  final BleClient _client;

  final StreamController<TransportPacket> _incoming =
      StreamController<TransportPacket>.broadcast();
  final StreamController<TransportKind> _state =
      StreamController<TransportKind>.broadcast();
  StreamSubscription<TransportPacket>? _incomingSub;
  StreamSubscription<BleClientState>? _stateSub;
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
    _incomingSub ??= _client.incoming.listen(
      _incoming.add,
      onError: _incoming.addError,
    );
    _stateSub ??= _client.state.listen(_onClientState);
    try {
      await _client.connect(reconnectTokens: reconnectTokens);
    } on BleTransportException {
      _connected = false;
      _state.add(TransportKind.searching);
      rethrow;
    }
  }

  @override
  Future<void> send(TransportPacket packet) async {
    if (!_connected) return;
    await _client.send(packet);
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _state.add(TransportKind.searching);
    await _client.disconnect();
  }

  /// Tear the transport down for good. Safe to call multiple times.
  Future<void> dispose() async {
    _connected = false;
    await _incomingSub?.cancel().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
    _incomingSub = null;
    await _stateSub?.cancel().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
    _stateSub = null;
    final c = _client;
    if (c is RealBleClient) {
      await c.dispose();
    } else if (c is PlaceholderBleClient) {
      await c.dispose();
    } else {
      await c.disconnect();
    }
    await _incoming.close().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
    await _state.close().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
  }

  void _onClientState(BleClientState s) {
    switch (s) {
      case BleClientState.connected:
        _connected = true;
        _state.add(TransportKind.direct);
      case BleClientState.scanning:
      case BleClientState.connecting:
      case BleClientState.idle:
      case BleClientState.disconnected:
        _connected = false;
        _state.add(TransportKind.searching);
    }
  }
}
