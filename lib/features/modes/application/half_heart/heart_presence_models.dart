enum HeartPresencePhase {
  waiting,
  localSeeking,
  partnerSeeking,
  approaching,
  united,
  fading,
}

double _unit(num value) => value.toDouble().clamp(0.0, 1.0);

/// A versioned, ordered sample of one person's continuous hold.
class HeartHoldSignal {
  const HeartHoldSignal({
    required this.eventId,
    required this.holdId,
    required this.sequence,
    required this.sentAtMs,
    required this.held,
    required this.strength,
    required this.x,
    required this.y,
    this.isLegacy = false,
  });

  final String eventId;
  final String holdId;
  final int sequence;
  final int sentAtMs;
  final bool held;
  final double strength;
  final double x;
  final double y;
  final bool isLegacy;

  Map<String, Object> toMap() => {
        'eventId': eventId,
        'holdId': holdId,
        'seq': sequence,
        'sentAtMs': sentAtMs,
        'held': held,
        'strength': strength,
        'x': x,
        'y': y,
      };

  static HeartHoldSignal? tryFromMap(Map<String, dynamic> raw) {
    final eventId = raw['eventId'];
    final holdId = raw['holdId'];
    final sequence = raw['seq'];
    final sentAtMs = raw['sentAtMs'];
    final held = raw['held'];
    final strength = raw['strength'];
    final x = raw['x'];
    final y = raw['y'];
    if (eventId is! String ||
        eventId.isEmpty ||
        eventId.length > 96 ||
        holdId is! String ||
        holdId.isEmpty ||
        holdId.length > 96 ||
        sequence is! num ||
        sequence < 0 ||
        sequence > 1000000 ||
        sentAtMs is! num ||
        sentAtMs < 0 ||
        held is! bool ||
        strength is! num ||
        strength < 0 ||
        strength > 1 ||
        x is! num ||
        x < 0 ||
        x > 1 ||
        y is! num ||
        y < 0 ||
        y > 1) {
      return null;
    }
    return HeartHoldSignal(
      eventId: eventId,
      holdId: holdId,
      sequence: sequence.toInt(),
      sentAtMs: sentAtMs.toInt(),
      held: held,
      strength: _unit(strength),
      x: _unit(x),
      y: _unit(y),
    );
  }
}

/// Immutable state consumed by the renderer and widget tests.
class HeartPresenceSnapshot {
  const HeartPresenceSnapshot({
    required this.phase,
    required this.localHeld,
    required this.partnerHeld,
    required this.unity,
    required this.localStrength,
    required this.partnerStrength,
    required this.localX,
    required this.localY,
    required this.partnerX,
    required this.partnerY,
  });

  final HeartPresencePhase phase;
  final bool localHeld;
  final bool partnerHeld;

  /// How far the two halves have converged, from separated to one heart.
  final double unity;
  final double localStrength;
  final double partnerStrength;
  final double localX;
  final double localY;
  final double partnerX;
  final double partnerY;

  bool get isMutual => localHeld && partnerHeld;
  bool get isUnited => phase == HeartPresencePhase.united;
}
