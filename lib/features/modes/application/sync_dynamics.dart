import 'dart:math' as math;

enum SyncLinkQuality { acquiring, stable, degraded, offline }

/// Robust NTP-style clock estimate for translating partner timestamps.
class SyncClockEstimator {
  static const int _maxSamples = 12;

  final List<_ClockSample> _samples = [];
  double _offsetUs = 0;
  double _roundTripUs = 0;
  double _jitterUs = 0;
  int? _lastAcceptedLocalUs;

  bool get hasSample => _samples.isNotEmpty;
  int get sampleCount => _samples.length;
  Duration get roundTrip =>
      Duration(microseconds: math.max(0, _roundTripUs.round()));
  Duration get jitter => Duration(microseconds: math.max(0, _jitterUs.round()));
  Duration get partnerOffset => Duration(microseconds: _offsetUs.round());

  double get confidence {
    if (_samples.isEmpty) return 0;
    final sampleConfidence = (_samples.length / 6).clamp(0.0, 1.0);
    final jitterPenalty = (1 - _jitterUs / 180000).clamp(0.0, 1.0);
    final latencyPenalty = (1 - _roundTripUs / 900000).clamp(.25, 1.0);
    return sampleConfidence * jitterPenalty * latencyPenalty;
  }

  SyncLinkQuality qualityAt(int localNowUs) {
    final last = _lastAcceptedLocalUs;
    if (last == null) return SyncLinkQuality.acquiring;
    final age = localNowUs - last;
    if (age > const Duration(seconds: 12).inMicroseconds) {
      return SyncLinkQuality.offline;
    }
    if (age > const Duration(seconds: 6).inMicroseconds ||
        jitter.inMilliseconds > 140) {
      return SyncLinkQuality.degraded;
    }
    return confidence >= .42
        ? SyncLinkQuality.stable
        : SyncLinkQuality.acquiring;
  }

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
    final rttUs = math.max(0, (localReceivedUs - localSentUs) - remoteWorkUs);
    if (rttUs > const Duration(seconds: 4).inMicroseconds) return;
    final offsetUs = ((partnerReceivedUs - localSentUs) +
            (partnerSentUs - localReceivedUs)) /
        2;
    if (_samples.length >= 4) {
      final rankedRtt = _samples.map((s) => s.roundTripUs).toList()..sort();
      final medianRtt = rankedRtt[rankedRtt.length ~/ 2];
      if (rttUs > math.max(350000, medianRtt * 3)) return;
    }

    _samples.add(_ClockSample(offsetUs: offsetUs, roundTripUs: rttUs));
    if (_samples.length > _maxSamples) _samples.removeAt(0);
    _lastAcceptedLocalUs = localReceivedUs;

    final ranked = List<_ClockSample>.of(_samples)
      ..sort((a, b) => a.roundTripUs.compareTo(b.roundTripUs));
    final selected =
        ranked.take(math.max(1, (ranked.length + 1) ~/ 2)).toList();
    final offsets = selected.map((sample) => sample.offsetUs).toList()..sort();
    final robustOffset = offsets.length.isOdd
        ? offsets[offsets.length ~/ 2]
        : (offsets[offsets.length ~/ 2 - 1] + offsets[offsets.length ~/ 2]) / 2;
    final robustRtt = selected
            .map((sample) => sample.roundTripUs.toDouble())
            .reduce((a, b) => a + b) /
        selected.length;
    final deviations = selected
        .map((sample) => (sample.offsetUs - robustOffset).abs())
        .toList()
      ..sort();
    final robustJitter = deviations[deviations.length ~/ 2];
    final alpha = _samples.length <= 2 ? 1.0 : .22;
    _offsetUs += (robustOffset - _offsetUs) * alpha;
    _roundTripUs += (robustRtt - _roundTripUs) * alpha;
    _jitterUs += (robustJitter - _jitterUs) * alpha;
  }

  int partnerToLocalUs(int partnerTimestampUs) =>
      partnerTimestampUs - _offsetUs.round();

  int sharedNowUs(int localNowUs) => localNowUs + (_offsetUs / 2).round();
}

/// Learns both tempos, then glides toward their midpoint. A stale partner does
/// not stop the beat: the last shared cadence continues locally.
class SharedRhythmReconciler {
  SharedRhythmReconciler({
    Duration initialInterval = const Duration(milliseconds: 1600),
  }) : _intervalUs = initialInterval.inMicroseconds.toDouble();

  static const double _minimumIntervalUs = 700000;
  static const double _maximumIntervalUs = 2400000;

  double _intervalUs;
  double? _localIntervalUs;
  double? _partnerIntervalUs;
  int? _lastLocalUs;
  int? _lastPartnerLocalUs;
  int? _sharedAnchorUs;

  bool get hasObservation =>
      _lastLocalUs != null || _lastPartnerLocalUs != null;
  Duration get interval => Duration(microseconds: _intervalUs.round());
  Duration? get localInterval => _localIntervalUs == null
      ? null
      : Duration(microseconds: _localIntervalUs!.round());
  Duration? get partnerInterval => _partnerIntervalUs == null
      ? null
      : Duration(microseconds: _partnerIntervalUs!.round());

  void observeLocalTap(int localUs) {
    _localIntervalUs =
        _observeInterval(_lastLocalUs, localUs, _localIntervalUs);
    _lastLocalUs = localUs;
    _reconcile(localUs);
  }

  void observePartnerTap(int partnerTapInLocalUs) {
    _partnerIntervalUs = _observeInterval(
      _lastPartnerLocalUs,
      partnerTapInLocalUs,
      _partnerIntervalUs,
    );
    _lastPartnerLocalUs = partnerTapInLocalUs;
    _reconcile(partnerTapInLocalUs);
  }

  double? _observeInterval(int? previous, int now, double? estimate) {
    if (previous == null || now <= previous) return estimate;
    final raw = (now - previous).toDouble();
    if (raw < _minimumIntervalUs * .55 || raw > _maximumIntervalUs * 1.8) {
      return estimate;
    }
    var candidate = raw;
    if (candidate < _minimumIntervalUs) candidate *= 2;
    if (candidate > _maximumIntervalUs) candidate /= 2;
    candidate = candidate.clamp(_minimumIntervalUs, _maximumIntervalUs);
    return estimate == null ? candidate : estimate * .68 + candidate * .32;
  }

  void _reconcile(int observationUs) {
    final candidates = <double>[
      if (_localIntervalUs != null) _localIntervalUs!,
      if (_partnerIntervalUs != null) _partnerIntervalUs!,
    ];
    if (candidates.isNotEmpty) {
      final target = candidates.reduce((a, b) => a + b) / candidates.length;
      final maximumStep = _intervalUs * .07;
      final delta = (target - _intervalUs).clamp(-maximumStep, maximumStep);
      _intervalUs = (_intervalUs + delta * .48)
          .clamp(_minimumIntervalUs, _maximumIntervalUs);
    }
    final local = _lastLocalUs;
    final partner = _lastPartnerLocalUs;
    final desiredAnchor = local != null && partner != null
        ? ((local + partner) / 2).round()
        : local ?? partner ?? observationUs;
    _sharedAnchorUs = _sharedAnchorUs == null
        ? desiredAnchor
        : (_sharedAnchorUs! * .72 + desiredAnchor * .28).round();
  }

  int nextBeatAfterUs(int localNowUs) {
    final anchor = _sharedAnchorUs ?? localNowUs;
    final interval = _intervalUs.round();
    if (anchor > localNowUs) return anchor;
    final elapsed = localNowUs - anchor;
    return anchor + (elapsed ~/ interval + 1) * interval;
  }
}

/// V2 adds an epoch and sequence so duplicates and reordered packets are safe.
abstract final class SyncProtocol {
  static const int version = 2;

  static Map<String, Object> envelope({
    required int epoch,
    required int sequence,
    required int sentAtUs,
    Map<String, Object> data = const {},
  }) =>
      <String, Object>{
        'v': version,
        'epoch': epoch,
        'seq': sequence,
        'sentAtUs': sentAtUs,
        ...data,
      };

  static String? eventKey(Map<String, dynamic> data) {
    final epoch = (data['epoch'] as num?)?.toInt();
    final sequence = (data['seq'] as num?)?.toInt();
    if (epoch == null || sequence == null) return null;
    return '$epoch:$sequence';
  }
}

class SyncEventDeduplicator {
  SyncEventDeduplicator({this.capacity = 96});

  final int capacity;
  final Set<String> _seen = <String>{};
  final List<String> _order = <String>[];
  final Map<int, int> _highestSequenceByEpoch = <int, int>{};

  bool accept(Map<String, dynamic> data) {
    final key = SyncProtocol.eventKey(data);
    if (key == null) return true;
    final epoch = (data['epoch'] as num).toInt();
    final sequence = (data['seq'] as num).toInt();
    final highest = _highestSequenceByEpoch[epoch];
    if (highest != null && sequence <= highest) return false;
    if (!_seen.add(key)) return false;
    _highestSequenceByEpoch[epoch] = sequence;
    _order.add(key);
    if (_order.length > capacity) _seen.remove(_order.removeAt(0));
    return true;
  }
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
