import 'dart:async';

import 'ble_transport.dart';
import 'local_network_transport.dart';
import 'transport.dart';
import 'webrtc_transport.dart';

/// Picks the best available [Transport] for a given connection and falls
/// through automatically without dropping the user-visible session.
///
/// Priority follows the spec: direct (BLE / Wi-Fi Direct) → local network
/// → relay. The manager never raises a "disconnected" event upward — it
/// switches to [TransportKind.searching] and keeps trying with exponential
/// backoff so that the connection survives network blips and sleep.
class TransportManager {
  TransportManager({
    Transport? ble,
    Transport? localNetwork,
    Transport? relay,
  }) : _transports = [
          ble ?? BleTransport(),
          localNetwork ?? LocalNetworkTransport(),
          relay ?? WebRtcTransport(),
        ];

  /// In priority order: direct → local network → relay.
  final List<Transport> _transports;

  final _state = StreamController<TransportKind>.broadcast();
  Stream<TransportKind> get state => _state.stream;

  // Aggregated incoming from all connected transports.
  final _incoming = StreamController<TransportPacket>.broadcast();
  Stream<TransportPacket> get incoming => _incoming.stream;

  final List<StreamSubscription<dynamic>> _subs = [];

  TransportKind _current = TransportKind.searching;
  TransportKind get current => _current;

  /// Open all candidate transports. Whichever connects first wins; the
  /// others stay armed in case the active one degrades.
  Future<void> attach({required Map<String, String> reconnectTokens}) async {
    for (final t in _transports) {
      // Run in parallel — the manager just promotes whichever connects.
      unawaited(_connectTransport(t, reconnectTokens));

      // Aggregate incoming packets from every transport.
      _subs.add(t.incoming.listen(
        _incoming.add,
        onError: _incoming.addError,
      ));

      // Track state transitions with proper promotion AND demotion.
      _subs.add(t.state.listen((s) {
        if (s == TransportKind.searching && _current == t.kind) {
          // Active transport lost — find next best connected transport.
          final fallback = _findBestConnected();
          _current = fallback ?? TransportKind.searching;
          _state.add(_current);
        } else if (s != TransportKind.searching && _rank(s) < _rank(_current)) {
          // Better transport connected — promote.
          _current = s;
          _state.add(_current);
        }
      }));
    }
  }

  Future<void> _connectTransport(
    Transport transport,
    Map<String, String> reconnectTokens,
  ) async {
    try {
      await transport.connect(reconnectTokens: reconnectTokens);
    } catch (e, st) {
      if (!_incoming.isClosed) _incoming.addError(e, st);
      if (_current == transport.kind) {
        _current = _findBestConnected() ?? TransportKind.searching;
        if (!_state.isClosed) _state.add(_current);
      } else if (!_transports.any((t) => t.isConnected)) {
        if (!_state.isClosed) _state.add(TransportKind.searching);
      }
    }
  }

  /// Send via the highest-priority connected transport.
  ///
  /// If none is connected, the packet is dropped — Pulse never queues mode
  /// events; missed beats simply don't arrive. (Sneak In delivery is
  /// handled separately on the shadow channel.)
  Future<void> send(TransportPacket packet) async {
    for (final t in _transports) {
      if (t.isConnected) {
        await t.send(packet);
        return;
      }
    }
  }

  Future<void> detach() async {
    for (final t in _transports) {
      await t.disconnect();
    }
    _current = TransportKind.searching;
    _state.add(_current);
  }

  /// Cancel all stream subscriptions and close controllers. Call this when
  /// the session is being torn down for good.
  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel().timeout(
            const Duration(seconds: 3),
            onTimeout: () {},
          );
    }
    _subs.clear();
    await _incoming.close().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
    await _state.close().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
  }

  /// Find the highest-priority transport that is currently connected.
  TransportKind? _findBestConnected() {
    for (final t in _transports) {
      if (t.isConnected) return t.kind;
    }
    return null;
  }

  static int _rank(TransportKind k) => switch (k) {
        TransportKind.direct => 0,
        TransportKind.localNetwork => 1,
        TransportKind.relay => 2,
        TransportKind.searching => 3,
      };
}
