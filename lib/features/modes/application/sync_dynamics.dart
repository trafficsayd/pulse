import 'dart:math' as math;

/// Estimates the partner clock relative to this device with an NTP-style
/// four-timestamp exchange. Only timing metadata is exchanged.
class SyncClockEstimator {
  static const int _maxSamples = 8;

  final List<_ClockSample> _samples = [];
  double _offsetUs = 0;
  double _roundTripUs = 0;

  bool get hasSample => _samples.isNotEmpty;
  Duration get roundTrip =>
      Duration(microseconds: math.max(0, _roundTripUs.round()));
  Duration get partnerOffset => Duration(microseconds: _offsetUs.round());

  void observeExchange({
    required int localSentUs,
    required int partnerReceivedUs,
    required int partnerSentUs,
    required int localReceivedUs,
  }) {
    if (localReceivedUs < localSentUs || partnerSentUs < partnerReceivedUs) {
      return;
    }
    final remoteWorkUs = partnerSentUs - partnerReceivedUs;
    final rttUs = math.max(
      0,
      (localReceivedUs - localSentUs) - remoteWorkUs,
    );
    final offsetUs = ((partnerReceivedUs - localSentUs) +
            (partnerSentUs - localReceivedUs)) /
        2;
    _samples.add(_ClockSample(offsetUs: offsetUs, roundTripUs: rttUs));
    if (_samples.length > _maxSamples) _samples.removeAt(0);

    // Low-latency samples contain less asymmetric network error. Average the
    // best half instead of letting one congested packet move the shared beat.
    final ranked = List<_ClockSample>.of(_samples)
      ..sort((a, b) => a.roundTripUs.compareTo(b.roundTripUs));
    final selected = ranked.take(math.max(1, (ranked.length + 1) ~/ 2));
    _offsetUs =
        selected.map((sample) => sample.offsetUs).reduce((a, b) => a + b) /
            selected.length;
    _roundTripUs = selected
            .map((sample) => sample.roundTripUs.toDouble())
            .reduce((a, b) => a + b) /
        selected.length;
  }

  /// Converts a timestamp produced by the partner into this device's clock.
  int partnerToLocalUs(int partnerTimestampUs) =>
      partnerTimestampUs - _offsetUs.round();

  /// Both devices converge on the midpoint between their clocks. It provides
  /// a shared phase for guide pulses without declaring either phone the host.
  int sharedNowUs(int localNowUs) => localNowUs + (_offsetUs / 2).round();
}

class SyncProgressUpdate {
  const SyncProgressUpdate({
    required this.progress,
    required this.streak,
    required this.toleranceMs,
    required this.accuracy,
    required this.matched,
    required this.completedNow,
  });

  final double progress;
  final int streak;
  final int toleranceMs;
  final double accuracy;
  final bool matched;
  final bool completedNow;
}

/// Turns repeated timing matches into a forgiving, gradually tightening
/// journey. A single miss never destroys the feeling already built together.
class SyncProgressTracker {
  double _progress = 0;
  int _streak = 0;

  double get progress => _progress;
  int get streak => _streak;

  int get toleranceMs {
    final eased = math.pow(_progress, .78).toDouble();
    return (600 - 450 * eased).round().clamp(150, 600);
  }

  SyncProgressUpdate scoreDifference(int differenceMs) {
    final tolerance = toleranceMs;
    final wasComplete = _progress >= 1;
    final matched = differenceMs <= tolerance;
    var accuracy = 0.0;
    if (matched) {
      accuracy = (1 - differenceMs / tolerance).clamp(0.0, 1.0);
      _streak++;
      final streakWarmth = math.min(_streak, 5) * .012;
      _progress =
          (_progress + .095 + accuracy * .12 + streakWarmth).clamp(0.0, 1.0);
    } else {
      _streak = 0;
      _progress = (_progress - .045).clamp(0.0, 1.0);
    }
    return SyncProgressUpdate(
      progress: _progress,
      streak: _streak,
      toleranceMs: tolerance,
      accuracy: accuracy,
      matched: matched,
      completedNow: !wasComplete && _progress >= 1,
    );
  }

  void mergeRemote(double remoteProgress) {
    final safe = remoteProgress.clamp(0.0, 1.0);
    // Move quickly toward a more advanced partner, but never jump the whole
    // journey because of an old or duplicated state packet.
    if (safe > _progress) {
      _progress = (_progress * .42 + safe * .58).clamp(0.0, 1.0);
    }
  }
}

class _ClockSample {
  const _ClockSample({required this.offsetUs, required this.roundTripUs});

  final double offsetUs;
  final int roundTripUs;
}
