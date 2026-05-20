import 'dart:async';

import 'packet_codec.dart';

/// Connectivity tier reported by a [BleClient] back up to its host
/// [BleTransport]. The wider `TransportKind` enum cares about radio vs.
/// LAN vs. relay; this one only differentiates the BLE states the
/// transport itself can observe.
enum BleClientState {
  /// Not connected, not scanning. Initial state and reachable after a
  /// clean [BleClient.disconnect].
  idle,

  /// `FlutterBluePlus.startScan` is in flight. Will time out within
  /// the configured window.
  scanning,

  /// A peer was found and `connectToDevice` is in progress (GATT
  /// service discovery has not finished yet).
  connecting,

  /// GATT connected, TX subscribed, ready for traffic.
  connected,

  /// The peer dropped or the OS forced a disconnect. The client will
  /// stay in this state until the host transport calls [BleClient.connect]
  /// again.
  disconnected,
}

/// Thin, testable façade over a single role of the Pulse BLE transport.
///
/// In production both ends of a Pulse connection talk to a real
/// `flutter_blue_plus` stack — but each end picks at runtime whether to
/// act as a central (scan + connect) or as a peripheral (advertise +
/// accept). Each role is exposed through this same [BleClient] interface
/// so the higher-level `BleTransport` can stay agnostic.
///
/// All methods MUST be safe to call from `BleTransport.dispose` /
/// `disconnect` paths: implementations are required to apply a short
/// timeout to any awaited cleanup (see `RealBleClient.disconnect`).
abstract interface class BleClient {
  /// Decoded Pulse packets received from the peer.
  ///
  /// The stream is broadcast and never closes for the lifetime of the
  /// client — listeners stay subscribed across reconnects. Errors on
  /// this stream are surfaced as [BleTransportException] instances.
  Stream<Packet> get incoming;

  /// Observable BLE-layer state transitions for the UI / transport
  /// manager. Always emits the latest value on subscribe.
  Stream<BleClientState> get state;

  /// Current BLE-layer state without subscribing.
  BleClientState get currentState;

  /// Begin scanning (or advertising, for a peripheral implementation)
  /// and resolve when a GATT session is fully established.
  ///
  /// Throws [BleTransportException] with the matching [BleTransportFailure]
  /// variant on permission refusal, scan timeout, or write-channel
  /// failures. Implementations must stop scanning before throwing.
  Future<void> connect({
    Duration scanTimeout = const Duration(seconds: 10),
    Map<String, String> reconnectTokens = const {},
  });

  /// Send an already-sealed packet to the peer. Returns once the GATT
  /// write has been accepted (not necessarily delivered).
  Future<void> send(Packet packet);

  /// Best-effort graceful tear-down. Always completes within a short
  /// bounded window — implementations apply a 3-second timeout to every
  /// awaited cleanup step so a stuck radio can never wedge dispose.
  Future<void> disconnect();
}
