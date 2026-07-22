import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mode_event.dart';
import 'pulse_session.dart';
import 'session_provider.dart';

/// Scoped event bus that a mode screen reads to send/receive mode events.
///
/// Two flavours:
/// - **live** — wraps an active [PulseSession], forwarding events through
///   the encrypted channel.
/// - **inert** — returned when no session exists (no active connection,
///   pairing incomplete). Modes still render and work locally but cannot
///   communicate with a partner.
///
/// The provider watches [sessionProvider] so switching connections on the
/// People screen transparently swaps the underlying session.
class ModeEventBus {
  ModeEventBus.live(PulseSession session)
      : _session = session,
        _inert = false;

  ModeEventBus.inert()
      : _session = null,
        _inert = true;

  final PulseSession? _session;
  final bool _inert;

  /// True when the bus is backed by a live encrypted channel.
  bool get isConnected => !_inert && _session != null;

  /// Send a mode event to the partner. No-op if inert.
  Future<void> send(ModeEvent event) async {
    if (_inert || _session == null) return;
    await _session.sendEvent(event);
  }

  /// Send a Sneak In signal to the partner over the live channel.
  ///
  /// Returns `true` if there was a live session to hand the signal to,
  /// `false` when the bus is inert (no active connection / pairing
  /// incomplete). Never throws — a missing session is a normal, expected
  /// state, not an error.
  Future<bool> sendSneak(String signalId, {String? senderId}) async {
    final session = _session;
    if (_inert || session == null) return false;
    await session.sendSneak(signalId, senderId: senderId);
    return true;
  }

  /// Inbound events from the partner. Empty stream if inert.
  Stream<ModeEvent> get incoming {
    if (_inert || _session == null) return const Stream.empty();
    return _session.events;
  }

  /// Inbound Sneak In signals from the partner. Empty stream if inert.
  Stream<ModeEvent> get sneaks {
    if (_inert || _session == null) return const Stream.empty();
    return _session.sneaks;
  }
}

/// Provider exposing a [ModeEventBus] for the current session.
///
/// Mode screens read this to send and receive events without caring
/// whether a real P2P session is available.
final modeEventBusProvider = Provider<ModeEventBus>((ref) {
  final sessionAsync = ref.watch(sessionProvider);
  return sessionAsync.when(
    data: (session) =>
        session != null ? ModeEventBus.live(session) : ModeEventBus.inert(),
    loading: ModeEventBus.inert,
    error: (_, __) => ModeEventBus.inert(),
  );
});
