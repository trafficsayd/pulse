import 'dart:async';
import 'dart:developer' as dev;
import 'dart:math';

import 'ble_transport.dart';
import 'local_network_transport.dart';
import 'transport.dart';
import 'webrtc_transport.dart';

/// Base delay for the first reconnect attempt on any transport.
const Duration _kBackoffBase = Duration(seconds: 1);

/// Upper bound the exponential backoff delay never exceeds.
const Duration _kBackoffCap = Duration(seconds: 30);

/// Multiplier applied to the previous delay on every failed attempt.
const int _kBackoffMultiplier = 2;

/// Randomised spread applied around the computed delay (±20%) so that two
/// peers reconnecting after the same network blip don't hammer the relay
/// (or each other's radios) in lockstep.
const double _kBackoffJitterFraction = 0.2;

/// Picks the best available [Transport] for a given connection and falls
/// through automatically without dropping the user-visible session.
///
/// Priority follows the spec: direct (BLE / Wi-Fi Direct) → local network
/// → relay. The manager never raises a "disconnected" event upward — it
/// switches to [TransportKind.searching] and keeps trying with exponential
/// backoff so that the connection survives network blips and sleep.
///
/// Backoff formula (per transport, independently): delay = min(base * 2^n,
/// cap) with base = 1s, cap = 30s, n = number of consecutive failed attempts
/// since the transport last connected successfully — i.e. 1s, 2s, 4s, 8s,
/// 16s, 30s, 30s, ... A random ±20% jitter is applied to every computed
/// delay so retries from multiple devices don't synchronise. The attempt
/// counter resets to zero the moment the transport reports a successful
/// connection again.
class TransportManager {
  TransportManager({
    Transport? ble,
    Transport? localNetwork,
    Transport? relay,
    Random? random,
  })  : _transports = [
          ble ?? BleTransport(),
          localNetwork ?? LocalNetworkTransport(),
          relay ?? WebRtcTransport(),
        ],
        _random = random ?? Random();

  /// In priority order: direct → local network → relay.
  final List<Transport> _transports;

  final Random _random;

  final _state = StreamController<TransportKind>.broadcast();
  Stream<TransportKind> get state => _state.stream;

  // Aggregated incoming from all connected transports.
  final _incoming = StreamController<TransportPacket>.broadcast();
  Stream<TransportPacket> get incoming => _incoming.stream;

  final List<StreamSubscription<dynamic>> _subs = [];

  /// Consecutive failed-reconnect counter, keyed by transport identity.
  /// Reset to 0 as soon as that transport connects successfully.
  final Map<Transport, int> _reconnectAttempts = {};

  /// Pending backoff timer per transport, so a transport that is already
  /// waiting to retry never gets a second timer stacked on top of it.
  final Map<Transport, Timer> _retryTimers = {};

  /// Last-observed `isConnected` per transport, used to tell a genuine
  /// mid-session drop (connected -> searching) apart from the harmless
  /// `searching` a transport emits at the very start of every [connect]
  /// attempt (which must NOT double-count as a failure on top of the one
  /// already recorded by [_connectTransport]).
  final Map<Transport, bool> _wasConnected = {};

  /// Tokens from the most recent [attach] call, reused by scheduled
  /// reconnect attempts. `null` before the first [attach] / after [detach].
  Map<String, String>? _reconnectTokens;

  /// True once [detach] or [dispose] has run — reconnect attempts scheduled
  /// before that point must not fire afterwards.
  bool _stopped = false;

  TransportKind _current = TransportKind.searching;
  TransportKind get current => _current;

  /// Open all candidate transports. Whichever connects first wins; the
  /// others stay armed in case the active one degrades.
  Future<void> attach({required Map<String, String> reconnectTokens}) async {
    _stopped = false;
    _reconnectTokens = reconnectTokens;

    for (final t in _transports) {
      _wasConnected[t] = t.isConnected;

      // Run in parallel — the manager just promotes whichever connects.
      unawaited(_connectTransport(t, reconnectTokens));

      // Aggregate incoming packets from every transport.
      _subs.add(t.incoming.listen(
        _incoming.add,
        onError: _incoming.addError,
      ));

      // Track state transitions with proper promotion AND demotion, and
      // arm/disarm the exponential-backoff reconnect loop.
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

        if (s == t.kind) {
          // The transport itself just reported success — clear its retry
          // state so the next drop starts the backoff from the beginning.
          _reconnectAttempts[t] = 0;
          _cancelRetryTimer(t);
          _wasConnected[t] = true;
        } else if (s == TransportKind.searching) {
          // A `searching` state fires both (a) at the very start of every
          // `connect()` attempt — that failure path is already handled by
          // `_connectTransport` once the attempt's Future settles — and
          // (b) when an already-established channel drops mid-session,
          // which is NOT otherwise observed by `_connectTransport`. Only
          // the latter should arm a fresh retry here; the former would
          // otherwise double-count the very attempt already in flight.
          final wasConnected = _wasConnected[t] ?? false;
          _wasConnected[t] = false;
          if (wasConnected) {
            _scheduleReconnect(t);
          }
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
    // Whether `connect()` threw or simply returned without succeeding
    // (e.g. a scan timeout swallowed internally), the attempt is over: if
    // the transport is still not connected, arm the next backoff retry.
    // If it did connect, its own `state` emission already reset the
    // attempt counter above.
    if (!transport.isConnected) {
      _wasConnected[transport] = false;
      _scheduleReconnect(transport);
    }
  }

  /// Schedule a reconnect attempt for [transport] using exponential backoff
  /// with jitter. No-op if a retry is already pending for it, or if the
  /// manager has been detached/disposed since the drop was observed.
  void _scheduleReconnect(Transport transport) {
    if (_stopped) return;
    if (_retryTimers.containsKey(transport)) return;
    if (transport.isConnected) return;

    final attempt = (_reconnectAttempts[transport] ?? 0) + 1;
    _reconnectAttempts[transport] = attempt;

    final delay = _backoffDelay(attempt);
    _retryTimers[transport] = Timer(delay, () {
      _retryTimers.remove(transport);
      if (_stopped || transport.isConnected) return;
      final tokens = _reconnectTokens;
      if (tokens == null) return;
      unawaited(_connectTransport(transport, tokens));
    });
  }

  /// Exponential backoff with a ±20% jitter: base 1s, ×2 per attempt,
  /// capped at 30s — i.e. nominal delays of 1, 2, 4, 8, 16, 30, 30, ...
  /// before jitter is applied.
  Duration _backoffDelay(int attempt) {
    final double capMs = _kBackoffCap.inMilliseconds.toDouble();
    final int exponent = attempt - 1; // attempt 1 -> base delay (1s).
    final double scaled = _kBackoffBase.inMilliseconds *
        pow(_kBackoffMultiplier, exponent).toDouble();
    final double capped = min(scaled, capMs);

    // Jitter in [-fraction, +fraction] of the capped delay.
    final double jitterSpread = capped * _kBackoffJitterFraction;
    final double jitter = (_random.nextDouble() * 2 - 1) * jitterSpread;

    final double jittered = (capped + jitter).clamp(0.0, capMs).toDouble();
    return Duration(milliseconds: jittered.round());
  }

  void _cancelRetryTimer(Transport transport) {
    _retryTimers.remove(transport)?.cancel();
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
    _stopped = true;
    _cancelAllRetryTimers();
    for (final t in _transports) {
      await t.disconnect();
    }
    _reconnectAttempts.clear();
    _current = TransportKind.searching;
    _state.add(_current);
  }

  /// Cancel all stream subscriptions and close controllers. Call this when
  /// the session is being torn down for good.
  Future<void> dispose() async {
    _stopped = true;
    _cancelAllRetryTimers();
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

  void _cancelAllRetryTimers() {
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
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
