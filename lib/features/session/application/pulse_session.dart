import 'dart:typed_data';

import '../../crypto/pair_channel.dart';
import '../../transport/transport.dart';
import '../../transport/transport_manager.dart';
import 'mode_event.dart';

/// Aggregates the transport layer and the encrypted channel for a single
/// active connection so that mode screens and the hub can send/receive
/// events without caring which physical transport is carrying them.
///
/// Lifecycle is owned by [SessionNotifier] — when the user switches the
/// active connection on the People screen, the old session is disposed and
/// a new one is created.
class PulseSession {
  PulseSession({
    required this.connectionId,
    required this.transportManager,
    required this.pairChannel,
  });

  final String connectionId;
  final TransportManager transportManager;
  final PairChannel pairChannel;

  /// Current transport quality tier.
  Stream<TransportKind> get transportState => transportManager.state;

  /// The transport kind currently carrying traffic, or [TransportKind.searching].
  TransportKind get currentTransport => transportManager.current;

  /// Decrypted inbound packets from the partner.
  Stream<PulsePacket> get incoming => pairChannel.incoming;

  /// Crypto errors (replay, tamper, MAC failure). The stream stays open
  /// so the UI can surface a "secure channel desynced" banner.
  Stream<Object> get errors => pairChannel.errors;

  /// Send raw plaintext bytes through the encrypted channel.
  Future<void> send(Uint8List plaintext) => pairChannel.send(plaintext);

  /// Encode and send a [ModeEvent].
  Future<void> sendEvent(ModeEvent event) => send(event.encode());

  /// Decrypted inbound events from the partner as typed [ModeEvent]s.
  /// Malformed packets are silently skipped.
  Stream<ModeEvent> get events => incoming
      .map((packet) => ModeEvent.tryDecode(packet.payload))
      .where((e) => e != null)
      .cast<ModeEvent>();

  /// Send a Sneak In signal to the partner. Travels the exact same path as
  /// every other mode event: encoded to JSON, sealed by [PairChannel], and
  /// handed to the active transport.
  ///
  /// [signalId] must be a stable id from `kSneakSignals`. [senderId] lets the
  /// receiver attribute the signal (defaults to this session's
  /// [connectionId]).
  Future<void> sendSneak(String signalId, {String? senderId}) =>
      sendEvent(ModeEvent.sneak(signalId, senderId: senderId ?? connectionId));

  /// Inbound Sneak In signals from the partner, filtered out of the shared
  /// [events] stream. Reuses the single encrypted channel — no second pipe.
  Stream<ModeEvent> get sneaks => events.where((e) => e.isSneak);

  /// Tear everything down. Safe to call multiple times.
  Future<void> dispose() async {
    await pairChannel.close();
    await transportManager.detach();
    await transportManager.dispose();
  }
}
