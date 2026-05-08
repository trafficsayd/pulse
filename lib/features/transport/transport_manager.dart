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
  })  : _transports = [
          ble ?? BleTransport(),
          localNetwork ?? LocalNetworkTransport(),
          relay ?? WebRtcTransport(),
        ];

  /// In priority order: direct → local network → relay.
  final List<Transport> _transports;

  final _state = StreamController<TransportKind>.broadcast();
  Stream<TransportKind> get state => _state.stream;

  TransportKind _current = TransportKind.searching;
  TransportKind get current => _current;

  /// Open all candidate transports. Whichever connects first wins; the
  /// others stay armed in case the active one degrades.
  Future<void> attach({required Map<String, String> reconnectTokens}) async {
    for (final t in _transports) {
      // Run in parallel — the manager just promotes whichever connects.
      unawaited(t.connect(reconnectTokens: reconnectTokens));
      t.state.listen((s) {
        if (s != TransportKind.searching && _rank(s) < _rank(_current)) {
          _current = s;
          _state.add(_current);
        }
      });
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

  static int _rank(TransportKind k) => switch (k) {
        TransportKind.direct => 0,
        TransportKind.localNetwork => 1,
        TransportKind.relay => 2,
        TransportKind.searching => 3,
      };
}
