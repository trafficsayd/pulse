import 'heart_presence_models.dart';

/// Deterministic two-person presence state.
///
/// It deliberately does not own timers or transport. Callers feed it local
/// and remote samples and ask for a time-relative [snapshot], which keeps the
/// protocol testable without frames, widgets, or a real network.
class HeartPresenceController {
  HeartPresenceController({
    required String Function() idFactory,
    this.remoteTimeoutMs = 1500,
    this.convergenceMs = 520,
    this.fadeMs = 650,
    this.maxClockSkewMs = 120000,
  }) : _idFactory = idFactory;

  final String Function() _idFactory;
  final int remoteTimeoutMs;
  final int convergenceMs;
  final int fadeMs;
  final int maxClockSkewMs;

  String? _localHoldId;
  int _localSequence = 0;
  double _localStrength = .5;
  double _localX = .5;
  double _localY = .5;

  String? _remoteHoldId;
  int _remoteSequence = -1;
  int _remoteSentAtMs = -1;
  int? _remoteReceivedAtMs;
  bool _remoteHeld = false;
  double _remoteStrength = .5;
  double _remoteX = .5;
  double _remoteY = .5;

  int? _mutualStartedAtMs;
  int? _lastMutualAtMs;
  final Set<String> _seenEventIds = <String>{};
  final List<String> _eventOrder = <String>[];

  bool get localHeld => _localHoldId != null;
  bool get partnerHeld => _remoteHeld;
  String? get localHoldId => _localHoldId;

  HeartHoldSignal beginLocal({
    required int nowMs,
    double strength = .5,
    double x = .5,
    double y = .5,
  }) {
    if (_localHoldId == null) {
      _localHoldId = _idFactory();
      _localSequence = 0;
    }
    return _localSignal(nowMs: nowMs, strength: strength, x: x, y: y);
  }

  HeartHoldSignal keepLocalAlive({
    required int nowMs,
    double? strength,
    double? x,
    double? y,
  }) {
    if (_localHoldId == null) {
      return beginLocal(
        nowMs: nowMs,
        strength: strength ?? .5,
        x: x ?? .5,
        y: y ?? .5,
      );
    }
    return _localSignal(
      nowMs: nowMs,
      strength: strength ?? _localStrength,
      x: x ?? _localX,
      y: y ?? _localY,
    );
  }

  HeartHoldSignal? endLocal({required int nowMs}) {
    final holdId = _localHoldId;
    if (holdId == null) return null;
    final signal = HeartHoldSignal(
      eventId: _idFactory(),
      holdId: holdId,
      sequence: _localSequence++,
      sentAtMs: nowMs,
      held: false,
      strength: _localStrength,
      x: _localX,
      y: _localY,
    );
    _localHoldId = null;
    _mutualStartedAtMs = null;
    return signal;
  }

  HeartHoldSignal _localSignal({
    required int nowMs,
    required double strength,
    required double x,
    required double y,
  }) {
    _localStrength = strength.clamp(0.0, 1.0).toDouble();
    _localX = x.clamp(0.0, 1.0).toDouble();
    _localY = y.clamp(0.0, 1.0).toDouble();
    return HeartHoldSignal(
      eventId: _idFactory(),
      holdId: _localHoldId!,
      sequence: _localSequence++,
      sentAtMs: nowMs,
      held: true,
      strength: _localStrength,
      x: _localX,
      y: _localY,
    );
  }

  /// Applies an inbound packet. Returns false for malformed chronology,
  /// duplicates, old sessions, and delayed releases from superseded holds.
  bool receive(HeartHoldSignal signal, {required int receivedAtMs}) {
    if ((signal.sentAtMs - receivedAtMs).abs() > maxClockSkewMs) return false;
    if (!_remember(signal.eventId)) return false;

    final sameHold = signal.holdId == _remoteHoldId;
    if (sameHold && signal.sequence <= _remoteSequence) return false;
    if (!sameHold) {
      if (!signal.held) return false;
      if (signal.sentAtMs < _remoteSentAtMs) return false;
      _remoteHoldId = signal.holdId;
      _remoteSequence = -1;
    }
    if (signal.sentAtMs < _remoteSentAtMs && !signal.isLegacy) return false;

    _remoteSequence = signal.sequence;
    _remoteSentAtMs = signal.sentAtMs;
    _remoteReceivedAtMs = receivedAtMs;
    _remoteHeld = signal.held;
    _remoteStrength = signal.strength;
    _remoteX = signal.x;
    _remoteY = signal.y;
    if (!signal.held) {
      _mutualStartedAtMs = null;
    }
    return true;
  }

  HeartPresenceSnapshot snapshot(int nowMs) {
    if (_remoteHeld &&
        _remoteReceivedAtMs != null &&
        nowMs - _remoteReceivedAtMs! > remoteTimeoutMs) {
      if (localHeld) {
        // Anchor the graceful separation at the exact TTL boundary, not at
        // whichever frame happened to notice it. This keeps the transition
        // deterministic after a stalled frame or resumed app.
        _lastMutualAtMs = _remoteReceivedAtMs! + remoteTimeoutMs;
      }
      _remoteHeld = false;
      _mutualStartedAtMs = null;
    }

    final mutual = localHeld && _remoteHeld;
    if (mutual) {
      _mutualStartedAtMs ??= nowMs;
      _lastMutualAtMs = nowMs;
    } else {
      _mutualStartedAtMs = null;
    }
    final unity = mutual
        ? ((nowMs - _mutualStartedAtMs!) / convergenceMs)
            .clamp(0.0, 1.0)
            .toDouble()
        : 0.0;
    final fading = !mutual &&
        _lastMutualAtMs != null &&
        nowMs - _lastMutualAtMs! <= fadeMs;
    final phase = mutual
        ? (unity >= 1
            ? HeartPresencePhase.united
            : HeartPresencePhase.approaching)
        : fading
            ? HeartPresencePhase.fading
            : localHeld
                ? HeartPresencePhase.localSeeking
                : _remoteHeld
                    ? HeartPresencePhase.partnerSeeking
                    : HeartPresencePhase.waiting;
    final fadeUnity = fading
        ? (1 - (nowMs - _lastMutualAtMs!) / fadeMs).clamp(0.0, 1.0).toDouble()
        : unity;
    return HeartPresenceSnapshot(
      phase: phase,
      localHeld: localHeld,
      partnerHeld: _remoteHeld,
      unity: fadeUnity,
      localStrength: _localStrength,
      partnerStrength: _remoteStrength,
      localX: _localX,
      localY: _localY,
      partnerX: _remoteX,
      partnerY: _remoteY,
    );
  }

  bool _remember(String eventId) {
    if (!_seenEventIds.add(eventId)) return false;
    _eventOrder.add(eventId);
    if (_eventOrder.length > 192) {
      _seenEventIds.remove(_eventOrder.removeAt(0));
    }
    return true;
  }
}
