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
        _inert = false,
        _onTestSend = null {
    _bindIncoming(session.events);
  }

  /// Injected transport used by widget tests and isolated QA entrypoints.
  ModeEventBus.testing(
    Stream<ModeEvent> incoming, {
    FutureOr<void> Function(ModeEvent event)? onSend,
  })  : _session = null,
        _inert = false,
        _onTestSend = onSend {
    _bindIncoming(incoming);
  }

  void _bindIncoming(Stream<ModeEvent> incoming) {
    _subscription = incoming.listen((event) {
      final now = DateTime.now();
      _recent.add(_BufferedModeEvent(event, now));
      _prune(now);
      _live.add(event);
    }, onError: _live.addError);
  }

  ModeEventBus.inert()
      : _session = null,
        _inert = true,
        _onTestSend = null;

  final PulseSession? _session;
  final bool _inert;
  final FutureOr<void> Function(ModeEvent event)? _onTestSend;
  final _live = StreamController<ModeEvent>.broadcast();
  final List<_BufferedModeEvent> _recent = <_BufferedModeEvent>[];
  StreamSubscription<ModeEvent>? _subscription;

  static const _replayWindow = Duration(seconds: 30);

  /// True when the bus is backed by a live encrypted channel.
  bool get isConnected => !_inert;

  /// Send a mode event to the partner. No-op if inert.
  Future<void> send(ModeEvent event) async {
    final testSend = _onTestSend;
    if (testSend != null) {
      await testSend(event);
      return;
    }
    if (_inert || _session == null) return;
    await _session.sendEvent(event);
  }

  /// Inbound events from the partner. Empty stream if inert.
  Stream<ModeEvent> get liveIncoming {
    if (_inert) return const Stream.empty();
    return _live.stream;
  }

  /// Live events plus a short replay window. This lets a partner open the
  /// matching mode from the incoming banner without losing the first touch.
  Stream<ModeEvent> get incoming {
    if (_inert) return const Stream.empty();
    _prune(DateTime.now());
    final replayEntries = List<_BufferedModeEvent>.of(_recent);
    final replay =
        replayEntries.map((entry) => entry.event).toList(growable: false);
    // Replay is a hand-off from the app-wide incoming banner to the mode that
    // has just opened, not event history. Consume the snapshot so reopening a
    // mode cannot repeat an old touch, bell or firework.
    _recent.removeWhere(replayEntries.contains);
    return Stream<ModeEvent>.multi((controller) {
      // A mode usually subscribes in initState. Coordinate-based events need
      // the first frame to finish before context.size is available, otherwise
      // opening an incoming notification can drop the beginning of a stroke.
      // Keep live events ordered behind the replay during this short window.
      final pendingLive = <ModeEvent>[];
      var replayComplete = false;
      final subscription = _live.stream.listen(
        (event) {
          if (replayComplete) {
            controller.add(event);
          } else {
            pendingLive.add(event);
          }
        },
        onError: controller.addError,
        onDone: controller.close,
      );
      final replayTimer = Timer(const Duration(milliseconds: 100), () {
        for (final event in replay) {
          controller.add(event);
        }
        for (final event in pendingLive) {
          controller.add(event);
        }
        pendingLive.clear();
        replayComplete = true;
      });
      controller.onCancel = () async {
        replayTimer.cancel();
        await subscription.cancel();
      };
    });
  }

  void _prune(DateTime now) {
    _recent.removeWhere(
        (entry) => now.difference(entry.receivedAt) > _replayWindow);
    if (_recent.length > 32) {
      _recent.removeRange(0, _recent.length - 32);
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _live.close();
  }
}

class _BufferedModeEvent {
  const _BufferedModeEvent(this.event, this.receivedAt);

  final ModeEvent event;
  final DateTime receivedAt;
}

/// Provider exposing a [ModeEventBus] for the current session.
///
/// Mode screens read this to send and receive events without caring
/// whether a real P2P session is available.
final modeEventBusProvider = Provider<ModeEventBus>((ref) {
  final sessionAsync = ref.watch(sessionProvider);
  final bus = sessionAsync.when(
    data: (session) =>
        session != null ? ModeEventBus.live(session) : ModeEventBus.inert(),
    loading: ModeEventBus.inert,
    error: (_, __) => ModeEventBus.inert(),
  );
  ref.onDispose(() => unawaited(bus.dispose()));
  return bus;
});

/// App-wide stream used for incoming-mode notifications. Mode screens use
/// [ModeEventBus.incoming] instead so they also receive the short replay.
final incomingModeEventProvider = StreamProvider<ModeEvent>((ref) {
  return ref.watch(modeEventBusProvider).liveIncoming;
});
