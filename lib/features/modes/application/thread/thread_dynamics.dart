import 'dart:math' as math;

class ThreadPoint {
  const ThreadPoint(this.x, this.y);

  final double x;
  final double y;

  static const center = ThreadPoint(.5, .5);

  ThreadPoint clamp() => ThreadPoint(
        x.clamp(0.0, 1.0),
        y.clamp(0.0, 1.0),
      );

  ThreadPoint operator +(ThreadPoint other) =>
      ThreadPoint(x + other.x, y + other.y);
  ThreadPoint operator -(ThreadPoint other) =>
      ThreadPoint(x - other.x, y - other.y);
  ThreadPoint operator *(double factor) => ThreadPoint(x * factor, y * factor);

  double get magnitude => math.sqrt(x * x + y * y);

  static ThreadPoint lerp(ThreadPoint a, ThreadPoint b, double t) =>
      a + (b - a) * t.clamp(0.0, 1.0);
}

class ThreadRemoteSample {
  const ThreadRemoteSample({
    required this.point,
    required this.velocity,
    required this.sentAtUs,
    required this.receivedAtUs,
    this.active = true,
  });

  final ThreadPoint point;
  final ThreadPoint velocity;
  final int sentAtUs;
  final int receivedAtUs;
  final bool active;
}

/// Small interpolation buffer for unordered realtime delivery. It renders a
/// few milliseconds behind the newest sample and predicts only briefly.
class ThreadRemoteReconciler {
  ThreadRemoteReconciler({
    this.interpolationDelay = const Duration(milliseconds: 85),
    this.maximumPrediction = const Duration(milliseconds: 160),
  });

  final Duration interpolationDelay;
  final Duration maximumPrediction;
  final List<ThreadRemoteSample> _samples = [];
  int? _lastSentAtUs;
  int? _bestTransitUs;

  bool get hasSample => _samples.isNotEmpty;
  ThreadRemoteSample? get latest => _samples.isEmpty ? null : _samples.last;

  bool push(ThreadRemoteSample sample) {
    final lastSent = _lastSentAtUs;
    if (lastSent != null && sample.sentAtUs <= lastSent) return false;
    _lastSentAtUs = sample.sentAtUs;
    final transit = sample.receivedAtUs - sample.sentAtUs;
    _bestTransitUs =
        _bestTransitUs == null ? transit : math.min(_bestTransitUs!, transit);
    _samples.add(sample);
    _samples.sort((a, b) => a.sentAtUs.compareTo(b.sentAtUs));
    if (_samples.length > 12) _samples.removeRange(0, _samples.length - 12);
    return true;
  }

  int _presentationUs(ThreadRemoteSample sample) =>
      sample.sentAtUs + (_bestTransitUs ?? 0);

  ThreadPoint? positionAt(int nowUs) {
    if (_samples.isEmpty) return null;
    final renderUs = nowUs - interpolationDelay.inMicroseconds;
    ThreadRemoteSample? before;
    ThreadRemoteSample? after;
    for (final sample in _samples) {
      if (_presentationUs(sample) <= renderUs) before = sample;
      if (_presentationUs(sample) > renderUs) {
        after = sample;
        break;
      }
    }
    if (before != null && after != null) {
      final beforeUs = _presentationUs(before);
      final afterUs = _presentationUs(after);
      final span = afterUs - beforeUs;
      final t = span <= 0 ? 1.0 : (renderUs - beforeUs) / span;
      return ThreadPoint.lerp(before.point, after.point, t).clamp();
    }
    final newest = before ?? _samples.first;
    final ageUs = math.max(0, renderUs - _presentationUs(newest));
    final predictionUs = math.min(ageUs, maximumPrediction.inMicroseconds);
    return (newest.point + newest.velocity * (predictionUs / 1000000)).clamp();
  }

  bool isStaleAt(int nowUs) =>
      _samples.isEmpty ||
      nowUs - _presentationUs(_samples.last) >
          const Duration(seconds: 3).inMicroseconds;

  void end() {
    _samples.clear();
    _lastSentAtUs = null;
    _bestTransitUs = null;
  }
}

class ThreadPhysicsFrame {
  const ThreadPhysicsFrame({
    required this.tension,
    required this.sag,
    required this.releaseWave,
    required this.shimmerSpeed,
  });

  final double tension;
  final double sag;
  final double releaseWave;
  final double shimmerSpeed;
}

/// Deterministic tactile model. Visual amplitude and haptic weight are both
/// derived from this one state, keeping cause and feedback on the same frame.
class ThreadPhysics {
  double _tension = 0;
  double _wave = 0;
  double _waveVelocity = 0;

  double get tension => _tension;

  ThreadPhysicsFrame update({
    required ThreadPoint local,
    required ThreadPoint partner,
    required ThreadPoint localVelocity,
    required double deltaSeconds,
    bool bothActive = true,
  }) {
    final separation = (partner - local).magnitude;
    final speed = localVelocity.magnitude;
    final targetTension = bothActive
        ? ((separation - .18) / .78 + speed * .08).clamp(0.0, 1.0)
        : .08;
    final response = 1 - math.exp(-deltaSeconds.clamp(0.0, .05) * 9);
    _tension += (targetTension - _tension) * response;

    // Damped spring used by release and remote replay.
    _waveVelocity += (-_wave * 22 - _waveVelocity * 6.2) * deltaSeconds;
    _wave += _waveVelocity * deltaSeconds;
    if (_wave.abs() < .0001 && _waveVelocity.abs() < .0001) {
      _wave = 0;
      _waveVelocity = 0;
    }

    return ThreadPhysicsFrame(
      tension: _tension.clamp(0.0, 1.0),
      sag: ((1 - _tension) * .13 + _wave * .055).clamp(-.12, .18),
      releaseWave: _wave.clamp(-1.0, 1.0),
      shimmerSpeed: .35 + _tension * 1.8,
    );
  }

  double release({double? strength}) {
    final impulse = (strength ?? _tension).clamp(.12, 1.0);
    _waveVelocity += 7.5 * impulse;
    return impulse;
  }

  void replayRemoteRelease(double strength) {
    _waveVelocity += 6.2 * strength.clamp(.08, 1.0);
  }
}

abstract final class ThreadProtocol {
  static const int version = 2;

  static Map<String, Object> gesture({
    required int epoch,
    required int sequence,
    required int sentAtUs,
    required String phase,
    required ThreadPoint point,
    ThreadPoint velocity = const ThreadPoint(0, 0),
    double tension = 0,
  }) =>
      <String, Object>{
        'v': version,
        'epoch': epoch,
        'seq': sequence,
        'sentAtUs': sentAtUs,
        'phase': phase,
        'x': point.x.clamp(0.0, 1.0),
        'y': point.y.clamp(0.0, 1.0),
        'vx': velocity.x.clamp(-4.0, 4.0),
        'vy': velocity.y.clamp(-4.0, 4.0),
        'tension': tension.clamp(0.0, 1.0),
      };

  static ThreadGesturePacket? parse(Map<String, dynamic> data) {
    final x = (data['x'] as num?)?.toDouble();
    final y = (data['y'] as num?)?.toDouble();
    if (x == null || y == null || !x.isFinite || !y.isFinite) return null;
    return ThreadGesturePacket(
      version: (data['v'] as num?)?.toInt() ?? 1,
      epoch: (data['epoch'] as num?)?.toInt(),
      sequence: (data['seq'] as num?)?.toInt(),
      sentAtUs: (data['sentAtUs'] as num?)?.toInt(),
      phase: data['phase'] as String? ?? 'move',
      point: ThreadPoint(x, y).clamp(),
      velocity: ThreadPoint(
        (data['vx'] as num?)?.toDouble() ?? 0,
        (data['vy'] as num?)?.toDouble() ?? 0,
      ),
      tension: ((data['tension'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
    );
  }
}

class ThreadGesturePacket {
  const ThreadGesturePacket({
    required this.version,
    required this.epoch,
    required this.sequence,
    required this.sentAtUs,
    required this.phase,
    required this.point,
    required this.velocity,
    required this.tension,
  });

  final int version;
  final int? epoch;
  final int? sequence;
  final int? sentAtUs;
  final String phase;
  final ThreadPoint point;
  final ThreadPoint velocity;
  final double tension;

  String? get key =>
      epoch == null || sequence == null ? null : '${epoch!}:${sequence!}';
}

class ThreadPacketDeduplicator {
  final Set<String> _seen = {};
  final List<String> _order = [];
  final Map<int, int> _highestSequenceByEpoch = {};

  bool accept(ThreadGesturePacket packet) {
    final key = packet.key;
    if (key == null) return true;
    final epoch = packet.epoch!;
    final sequence = packet.sequence!;
    final highest = _highestSequenceByEpoch[epoch];
    if (highest != null && sequence <= highest) return false;
    if (!_seen.add(key)) return false;
    _highestSequenceByEpoch[epoch] = sequence;
    _order.add(key);
    if (_order.length > 96) _seen.remove(_order.removeAt(0));
    return true;
  }
}
