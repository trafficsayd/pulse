/// Small ordering envelope for the candle's fast, transient signals.
///
/// A late breath or motion packet must never pull the partner's flame back to
/// an older pose.  Reliable ritual events (light, wish, portal) intentionally
/// do not use this guard; only disposable realtime samples do.
class CandleRealtimeGuard {
  final Map<String, int> _latestByChannel = <String, int>{};

  bool accept(String channel, Map<String, Object?> data) {
    final raw = data['sequence'];
    if (raw == null) return true; // Backwards-compatible with older clients.
    if (raw is! num) return false;
    final sequence = raw.toInt();
    if (sequence < 0) return false;
    final latest = _latestByChannel[channel];
    if (latest != null && sequence <= latest) return false;
    _latestByChannel[channel] = sequence;
    return true;
  }

  void reset() => _latestByChannel.clear();
}

Map<String, Object?> candleRealtimePayload({
  required int sequence,
  required Duration elapsed,
  required Map<String, Object?> values,
}) {
  return <String, Object?>{
    ...values,
    'sequence': sequence,
    // Useful for latency diagnostics. It is deliberately monotonic and is
    // never interpreted as wall-clock time across devices.
    'elapsedMicros': elapsed.inMicroseconds,
  };
}
