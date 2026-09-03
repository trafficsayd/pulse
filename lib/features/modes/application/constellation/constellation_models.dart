/// A normalized point contributed by one participant to the shared sky.
///
/// The model deliberately has no Flutter dependency so merge/reconciliation
/// can be verified without a renderer or frame clock.
class ConstellationStar {
  const ConstellationStar({
    required this.id,
    required this.authorId,
    required this.x,
    required this.y,
    required this.authoredAtMs,
    required this.sequence,
    this.energy = .72,
  });

  final String id;
  final String authorId;
  final double x;
  final double y;
  final int authoredAtMs;
  final int sequence;
  final double energy;

  ConstellationStar normalized() => ConstellationStar(
        id: id,
        authorId: authorId,
        x: x.clamp(0.0, 1.0).toDouble(),
        y: y.clamp(0.0, 1.0).toDouble(),
        authoredAtMs: authoredAtMs,
        sequence: sequence < 0 ? 0 : sequence,
        energy: energy.clamp(.12, 1.0).toDouble(),
      );

  String get canonicalSignature =>
      '$authoredAtMs|$authorId|$sequence|$id|${x.toStringAsFixed(6)}|'
      '${y.toStringAsFixed(6)}|${energy.toStringAsFixed(4)}';
}

class ConstellationEdge {
  const ConstellationEdge({
    required this.fromId,
    required this.toId,
    required this.weight,
    required this.pauseMs,
    required this.crossesStory,
    required this.bridgesPeople,
  });

  final String fromId;
  final String toId;
  final double weight;
  final int pauseMs;
  final bool crossesStory;
  final bool bridgesPeople;
}

class ConstellationSnapshot {
  const ConstellationSnapshot({
    required this.stars,
    required this.edges,
    required this.fingerprint,
  });

  final List<ConstellationStar> stars;
  final List<ConstellationEdge> edges;

  /// Stable across peers that have received the same records, regardless of
  /// packet order or duplicate delivery.
  final int fingerprint;
}
