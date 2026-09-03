import 'dart:math' as math;

import 'constellation_models.dart';

/// Deterministic shared-state engine for the pair's constellation.
///
/// Records are sorted by authored time and stable identity. Duplicate packets
/// are idempotent, while a conflicting record with the same ID is resolved by
/// its canonical representation, so both peers converge without a host.
class ConstellationEngine {
  ConstellationEngine({required this.localAuthorId, this.maxStars = 96});

  final String localAuthorId;
  final int maxStars;
  final Map<String, ConstellationStar> _byId = {};
  int _nextSequence = 0;

  ConstellationStar addLocal({
    required String id,
    required double x,
    required double y,
    required int authoredAtMs,
    double energy = .72,
  }) {
    final star = ConstellationStar(
      id: id,
      authorId: localAuthorId,
      x: x,
      y: y,
      authoredAtMs: authoredAtMs,
      sequence: _nextSequence++,
      energy: energy,
    ).normalized();
    merge([star]);
    return _byId[id] ?? star;
  }

  /// Returns the number of IDs that were added or canonically corrected.
  int merge(Iterable<ConstellationStar> records) {
    var changed = 0;
    for (final raw in records) {
      if (raw.id.isEmpty || raw.authorId.isEmpty) continue;
      final candidate = raw.normalized();
      final current = _byId[candidate.id];
      if (current == null ||
          candidate.canonicalSignature.compareTo(current.canonicalSignature) <
              0) {
        _byId[candidate.id] = candidate;
        changed++;
      }
      if (candidate.authorId == localAuthorId) {
        _nextSequence = math.max(_nextSequence, candidate.sequence + 1);
      }
    }
    _pruneDeterministically();
    return changed;
  }

  ConstellationSnapshot get snapshot {
    final stars = _sortedStars();
    final edges = _buildEdges(stars);
    return ConstellationSnapshot(
      stars: List.unmodifiable(stars),
      edges: List.unmodifiable(edges),
      fingerprint: _fingerprint(stars),
    );
  }

  List<ConstellationStar> _sortedStars() {
    final result = _byId.values.toList(growable: false)
      ..sort((a, b) {
        var order = a.authoredAtMs.compareTo(b.authoredAtMs);
        if (order != 0) return order;
        order = a.authorId.compareTo(b.authorId);
        if (order != 0) return order;
        order = a.sequence.compareTo(b.sequence);
        if (order != 0) return order;
        return a.id.compareTo(b.id);
      });
    return result;
  }

  void _pruneDeterministically() {
    final ordered = _sortedStars();
    final overflow = ordered.length - maxStars;
    if (overflow <= 0) return;
    for (var i = 0; i < overflow; i++) {
      _byId.remove(ordered[i].id);
    }
  }

  List<ConstellationEdge> _buildEdges(List<ConstellationStar> stars) {
    if (stars.length < 2) return const [];
    final edges = <ConstellationEdge>[];
    for (var i = 1; i < stars.length; i++) {
      final current = stars[i];
      final previous = stars[i - 1];
      _appendEdge(edges, stars, previous, current);

      // A close point from the other person creates a second, softer bridge.
      // It turns proximity and intersection into part of the pair's history.
      ConstellationStar? nearestOther;
      var nearestDistance = double.infinity;
      for (var p = 0; p < i - 1; p++) {
        final candidate = stars[p];
        if (candidate.authorId == current.authorId) continue;
        final distance = _distance(candidate, current);
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearestOther = candidate;
        }
      }
      if (nearestOther != null &&
          nearestDistance < .34 &&
          nearestOther.id != previous.id) {
        _appendEdge(edges, stars, nearestOther, current);
      }
    }
    return edges;
  }

  void _appendEdge(
    List<ConstellationEdge> edges,
    List<ConstellationStar> stars,
    ConstellationStar from,
    ConstellationStar to,
  ) {
    final distance = _distance(from, to);
    final pause = (to.authoredAtMs - from.authoredAtMs).abs();
    final pauseFactor = 1 - math.min(pause / 12000, 1);
    final weight = (.38 + (1 - math.min(distance, 1)) * .38 + pauseFactor * .24)
        .clamp(.28, 1.0)
        .toDouble();
    final crosses = edges.any((edge) {
      final a = stars.firstWhere((star) => star.id == edge.fromId);
      final b = stars.firstWhere((star) => star.id == edge.toId);
      if (a.id == from.id ||
          a.id == to.id ||
          b.id == from.id ||
          b.id == to.id) {
        return false;
      }
      return _segmentsCross(a, b, from, to);
    });
    edges.add(
      ConstellationEdge(
        fromId: from.id,
        toId: to.id,
        weight: weight,
        pauseMs: pause,
        crossesStory: crosses,
        bridgesPeople: from.authorId != to.authorId,
      ),
    );
  }

  double _distance(ConstellationStar a, ConstellationStar b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  bool _segmentsCross(
    ConstellationStar a,
    ConstellationStar b,
    ConstellationStar c,
    ConstellationStar d,
  ) {
    double orient(
            ConstellationStar p, ConstellationStar q, ConstellationStar r) =>
        (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y);
    final o1 = orient(a, b, c);
    final o2 = orient(a, b, d);
    final o3 = orient(c, d, a);
    final o4 = orient(c, d, b);
    return o1 * o2 < 0 && o3 * o4 < 0;
  }

  int _fingerprint(List<ConstellationStar> stars) {
    var hash = 0x811c9dc5;
    for (final codeUnit
        in stars.map((star) => star.canonicalSignature).join('~').codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}
