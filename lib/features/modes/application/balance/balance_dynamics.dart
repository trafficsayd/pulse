import 'dart:math' as math;

class BalanceVector {
  const BalanceVector(this.x, this.y);

  final double x;
  final double y;

  static const zero = BalanceVector(0, 0);

  BalanceVector operator +(BalanceVector other) =>
      BalanceVector(x + other.x, y + other.y);
  BalanceVector operator -(BalanceVector other) =>
      BalanceVector(x - other.x, y - other.y);
  BalanceVector operator *(double factor) =>
      BalanceVector(x * factor, y * factor);

  double get magnitude => math.sqrt(x * x + y * y);

  BalanceVector clampMagnitude([double maximum = 1]) {
    final length = magnitude;
    if (length <= maximum || length == 0) return this;
    return this * (maximum / length);
  }

  static BalanceVector lerp(BalanceVector a, BalanceVector b, double t) =>
      a + (b - a) * t.clamp(0.0, 1.0);
}

/// Calibrates against the phone's resting orientation, removes sensor noise,
/// and maps device acceleration into a stable [-1, 1] cooperative intent.
class BalanceSensorNormalizer {
  BalanceSensorNormalizer({
    this.calibrationSamples = 8,
    this.fullTiltAcceleration = 5.2,
    this.deadZone = .035,
  });

  final int calibrationSamples;
  final double fullTiltAcceleration;
  final double deadZone;
  int _samples = 0;
  double _biasX = 0;
  double _biasY = 0;
  BalanceVector _filtered = BalanceVector.zero;

  bool get calibrated => _samples >= calibrationSamples;

  BalanceVector add(double x, double y) {
    if (!x.isFinite || !y.isFinite) return _filtered;
    if (_samples < calibrationSamples) {
      _samples++;
      _biasX += (x - _biasX) / _samples;
      _biasY += (y - _biasY) / _samples;
      return BalanceVector.zero;
    }
    var raw = BalanceVector(
      (x - _biasX) / fullTiltAcceleration,
      (y - _biasY) / fullTiltAcceleration,
    ).clampMagnitude();
    if (raw.magnitude < deadZone) raw = BalanceVector.zero;
    _filtered = BalanceVector.lerp(_filtered, raw, .24);
    return _filtered;
  }
}

class CooperativeBalanceFrame {
  const CooperativeBalanceFrame({
    required this.position,
    required this.velocity,
    required this.combinedIntent,
    required this.stability,
    required this.partnerWeight,
  });

  final BalanceVector position;
  final BalanceVector velocity;
  final BalanceVector combinedIntent;
  final double stability;
  final double partnerWeight;
}

class CooperativeBalancePhysics {
  BalanceVector _position = BalanceVector.zero;
  BalanceVector _velocity = BalanceVector.zero;

  BalanceVector get position => _position;
  BalanceVector get velocity => _velocity;

  CooperativeBalanceFrame step({
    required BalanceVector localIntent,
    required BalanceVector partnerIntent,
    required double partnerWeight,
    required double deltaSeconds,
  }) {
    final dt = deltaSeconds.clamp(0.0, .05);
    final weight = partnerWeight.clamp(0.0, 1.0);
    final combined = weight > 0
        ? (localIntent + partnerIntent * weight) * (1 / (1 + weight))
        : localIntent;
    final acceleration = combined * 3.8 - _velocity * 2.15 - _position * .28;
    _velocity = (_velocity + acceleration * dt).clampMagnitude(1.8);
    _position = _position + _velocity * dt;

    final radius = _position.magnitude;
    if (radius > 1) {
      final normal = _position * (1 / radius);
      _position = normal;
      final outward = _velocity.x * normal.x + _velocity.y * normal.y;
      if (outward > 0) _velocity = _velocity - normal * (outward * 1.55);
    }
    final stability =
        (1 - _position.magnitude * .78 - _velocity.magnitude * .22)
            .clamp(0.0, 1.0);
    return CooperativeBalanceFrame(
      position: _position,
      velocity: _velocity,
      combinedIntent: combined,
      stability: stability,
      partnerWeight: weight,
    );
  }

  /// Gentle state reconciliation. Network truth influences the simulation but
  /// never teleports the shared object under the user's eyes.
  void reconcile({
    required BalanceVector remotePosition,
    required BalanceVector remoteVelocity,
    required double confidence,
  }) {
    final amount = (.035 * confidence.clamp(0.0, 1.0));
    _position =
        BalanceVector.lerp(_position, remotePosition, amount).clampMagnitude();
    _velocity = BalanceVector.lerp(_velocity, remoteVelocity, amount * .55)
        .clampMagnitude(1.8);
  }
}

class BalanceRemoteSample {
  const BalanceRemoteSample({
    required this.intent,
    required this.position,
    required this.velocity,
    required this.sentAtUs,
    required this.receivedAtUs,
  });

  final BalanceVector intent;
  final BalanceVector position;
  final BalanceVector velocity;
  final int sentAtUs;
  final int receivedAtUs;
}

class BalanceRemoteState {
  const BalanceRemoteState({
    required this.intent,
    required this.position,
    required this.velocity,
    required this.weight,
  });

  final BalanceVector intent;
  final BalanceVector position;
  final BalanceVector velocity;
  final double weight;
}

class BalanceRemoteReconciler {
  final List<BalanceRemoteSample> _samples = [];
  int? _lastSentAtUs;
  int? _bestTransitUs;

  bool push(BalanceRemoteSample sample) {
    final lastSent = _lastSentAtUs;
    if (lastSent != null && sample.sentAtUs <= lastSent) return false;
    _lastSentAtUs = sample.sentAtUs;
    final transit = sample.receivedAtUs - sample.sentAtUs;
    _bestTransitUs =
        _bestTransitUs == null ? transit : math.min(_bestTransitUs!, transit);
    _samples.add(sample);
    _samples.sort((a, b) => a.sentAtUs.compareTo(b.sentAtUs));
    if (_samples.length > 10) _samples.removeAt(0);
    return true;
  }

  int _presentationUs(BalanceRemoteSample sample) =>
      sample.sentAtUs + (_bestTransitUs ?? 0);

  BalanceRemoteState resolveAt(int nowUs) {
    if (_samples.isEmpty) {
      return const BalanceRemoteState(
        intent: BalanceVector.zero,
        position: BalanceVector.zero,
        velocity: BalanceVector.zero,
        weight: 0,
      );
    }
    final renderUs = nowUs - const Duration(milliseconds: 75).inMicroseconds;
    BalanceRemoteSample? before;
    BalanceRemoteSample? after;
    for (final sample in _samples) {
      if (_presentationUs(sample) <= renderUs) before = sample;
      if (_presentationUs(sample) > renderUs) {
        after = sample;
        break;
      }
    }
    final newest = _samples.last;
    final ageUs = math.max(0, nowUs - _presentationUs(newest));
    final weight = ageUs <= 350000
        ? 1.0
        : (1 - (ageUs - 350000) / 1700000).clamp(0.0, 1.0);
    if (before != null && after != null) {
      final beforeUs = _presentationUs(before);
      final afterUs = _presentationUs(after);
      final span = afterUs - beforeUs;
      final t = span <= 0 ? 1.0 : (renderUs - beforeUs) / span;
      return BalanceRemoteState(
        intent: BalanceVector.lerp(before.intent, after.intent, t) * weight,
        position: BalanceVector.lerp(before.position, after.position, t),
        velocity: BalanceVector.lerp(before.velocity, after.velocity, t),
        weight: weight,
      );
    }
    // Intent decays on stale state so a disconnected tilted phone cannot keep
    // pushing the common object forever.
    return BalanceRemoteState(
      intent: newest.intent * weight,
      position: newest.position,
      velocity: newest.velocity * weight,
      weight: weight,
    );
  }
}

abstract final class BalanceProtocol {
  static const int version = 2;

  static Map<String, Object> state({
    required int epoch,
    required int sequence,
    required int sentAtUs,
    required BalanceVector intent,
    required BalanceVector position,
    required BalanceVector velocity,
    required String source,
  }) =>
      <String, Object>{
        'v': version,
        'epoch': epoch,
        'seq': sequence,
        'sentAtUs': sentAtUs,
        'source': source,
        'ix': intent.x.clamp(-1.0, 1.0),
        'iy': intent.y.clamp(-1.0, 1.0),
        'x': position.x.clamp(-1.0, 1.0),
        'y': position.y.clamp(-1.0, 1.0),
        'vx': velocity.x.clamp(-1.8, 1.8),
        'vy': velocity.y.clamp(-1.8, 1.8),
      };

  static BalancePacket? parse(Map<String, dynamic> data) {
    final x = (data['x'] as num?)?.toDouble();
    final y = (data['y'] as num?)?.toDouble();
    if (x == null || y == null || !x.isFinite || !y.isFinite) return null;
    final version = (data['v'] as num?)?.toInt() ?? 1;
    // V1 sent normalized screen coordinates. Convert them to physics space.
    final position = version == 1
        ? BalanceVector((x - .5) * 2, (y - .5) * 2).clampMagnitude()
        : BalanceVector(x, y).clampMagnitude();
    return BalancePacket(
      version: version,
      epoch: (data['epoch'] as num?)?.toInt(),
      sequence: (data['seq'] as num?)?.toInt(),
      sentAtUs: (data['sentAtUs'] as num?)?.toInt(),
      intent: BalanceVector(
        (data['ix'] as num?)?.toDouble() ?? position.x,
        (data['iy'] as num?)?.toDouble() ?? position.y,
      ).clampMagnitude(),
      position: position,
      velocity: BalanceVector(
        (data['vx'] as num?)?.toDouble() ?? 0,
        (data['vy'] as num?)?.toDouble() ?? 0,
      ).clampMagnitude(1.8),
    );
  }
}

class BalancePacket {
  const BalancePacket({
    required this.version,
    required this.epoch,
    required this.sequence,
    required this.sentAtUs,
    required this.intent,
    required this.position,
    required this.velocity,
  });

  final int version;
  final int? epoch;
  final int? sequence;
  final int? sentAtUs;
  final BalanceVector intent;
  final BalanceVector position;
  final BalanceVector velocity;

  String? get key =>
      epoch == null || sequence == null ? null : '${epoch!}:${sequence!}';
}

class BalancePacketDeduplicator {
  final Set<String> _seen = {};
  final List<String> _order = [];
  final Map<int, int> _highestSequenceByEpoch = {};

  bool accept(BalancePacket packet) {
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
