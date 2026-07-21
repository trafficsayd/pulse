import 'dart:typed_data';

import '../crypto/pair_channel.dart';
import 'transport.dart';
import 'transport_manager.dart';

/// Bridges a [TransportManager] into the [RawByteChannel] interface that
/// [PairChannel] expects.
///
/// Each inbound [TransportPacket] is unwrapped to its raw `payload` bytes
/// (already AES-256-GCM ciphertext); outbound plaintext sealed by
/// [PairChannel] is re-wrapped into a [TransportPacket] with a fixed
/// kind tag so the transport layer can forward it opaquely.
///
/// The transport manager's lifecycle is owned by the session provider —
/// [close] is intentionally a no-op so that `PairChannel.close()` cannot
/// prematurely destroy the transport while other components still hold
/// references.
class TransportByteAdapter implements RawByteChannel {
  TransportByteAdapter({required TransportManager manager})
      : _manager = manager;

  final TransportManager _manager;

  /// All sealed payloads use this fixed kind — the transport layer never
  /// inspects the contents, and the mode-level event type lives inside the
  /// encrypted payload.
  static const String sealedKind = 'sealed';

  @override
  Stream<Uint8List> get incoming =>
      _manager.incoming.map((packet) => packet.payload);

  @override
  Future<void> send(Uint8List bytes) => _manager.send(
        TransportPacket(kind: sealedKind, payload: bytes),
      );

  @override
  Future<void> close() async {
    // Intentional no-op — TransportManager lifecycle is managed by the
    // session provider. PairChannel.close() calls this but the transport
    // must outlive the channel for reconnect scenarios.
  }
}
