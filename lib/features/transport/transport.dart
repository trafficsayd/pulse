import 'dart:async';
import 'dart:typed_data';

/// Quality tier of the transport currently carrying traffic for a connection.
///
/// The hub displays a small dot in this color so the user always knows whether
/// they are on a direct radio link, the local network, or a relayed channel.
enum TransportKind {
  /// BLE or Wi-Fi Direct / Multipeer Connectivity. Lowest latency, no relay.
  direct,

  /// mDNS/Bonjour discovery on the same Wi-Fi LAN. No internet involved.
  localNetwork,

  /// WebRTC over the public internet, brokered by a STUN/TURN signaling server.
  /// All payload bytes remain end-to-end encrypted on this path.
  relay,

  /// No transport currently available. The connection is in search mode and
  /// will resume automatically the moment any transport recovers.
  searching,
}

/// Outbound payload sent across a [Transport]. The contents are opaque bytes
/// that the higher layers have already wrapped with AES-256-GCM.
class TransportPacket {
  TransportPacket({
    required this.kind,
    required this.payload,
  });

  /// One of the well-known message kinds (`mode_event`, `sneak_signal`, etc.)
  final String kind;

  /// Already-encrypted bytes. The transport layer never inspects these.
  final Uint8List payload;
}

/// Abstract transport implementation.
///
/// Pulse layers three of these (BLE, local network, WebRTC) under a
/// [TransportManager] which picks the best available channel and falls back
/// gracefully without dropping the user-visible session.
abstract interface class Transport {
  /// Quality tier this transport reports when active.
  TransportKind get kind;

  /// True when the channel is fully established with the partner.
  bool get isConnected;

  /// Stream of inbound encrypted packets from the partner.
  Stream<TransportPacket> get incoming;

  /// Stream of connection state transitions.
  Stream<TransportKind> get state;

  /// Open or resume the channel using the supplied opaque tokens.
  ///
  /// [reconnectTokens] are random per-connection identifiers (BLE address
  /// token, signaling token) — never user identity.
  Future<void> connect({required Map<String, String> reconnectTokens});

  /// Send an encrypted packet. Returns when the transport has accepted it
  /// (not necessarily delivered).
  Future<void> send(TransportPacket packet);

  /// Best-effort graceful close. Keys are not erased — the higher layers
  /// decide whether the connection is paused, archived, or deleted.
  Future<void> disconnect();
}
