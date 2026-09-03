import 'dart:math' as math;

import 'firework_models.dart';

/// Peer-to-peer convergent state for a shared firework show.
class FireworkEngine {
  FireworkEngine({
    required this.localAuthorId,
    this.maxContributions = 48,
    this.simultaneousWindowMs = 2600,
  });

  final String localAuthorId;
  final int maxContributions;
  final int simultaneousWindowMs;
  final Map<String, FireworkContribution> _byId = {};
  int _nextSequence = 0;

  FireworkContribution addLocal({
    required String id,
    required double x,
    required double y,
    required int authoredAtMs,
    required int seed,
    required int palette,
    String? replyToId,
  }) {
    final contribution = FireworkContribution(
      id: id,
      authorId: localAuthorId,
      x: x,
      y: y,
      authoredAtMs: authoredAtMs,
      sequence: _nextSequence++,
      seed: seed,
      palette: palette,
      replyToId: replyToId,
    ).normalized();
    merge([contribution]);
    return _byId[id] ?? contribution;
  }

  int merge(Iterable<FireworkContribution> records) {
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
    _prune();
    return changed;
  }

  FireworkSnapshot get snapshot {
    final contributions = _sorted();
    final culminations = _buildCulminations(contributions);
    return FireworkSnapshot(
      contributions: List.unmodifiable(contributions),
      culminations: List.unmodifiable(culminations),
      fingerprint: _fingerprint(contributions),
    );
  }

  List<FireworkContribution> _sorted() {
    return _byId.values.toList(growable: false)
      ..sort((a, b) {
        var result = a.authoredAtMs.compareTo(b.authoredAtMs);
        if (result != 0) return result;
        result = a.authorId.compareTo(b.authorId);
        if (result != 0) return result;
        result = a.sequence.compareTo(b.sequence);
        if (result != 0) return result;
        return a.id.compareTo(b.id);
      });
  }

  void _prune() {
    final ordered = _sorted();
    final overflow = ordered.length - maxContributions;
    for (var i = 0; i < overflow; i++) {
      _byId.remove(ordered[i].id);
    }
  }

  List<FireworkCulmination> _buildCulminations(
    List<FireworkContribution> contributions,
  ) {
    final candidates = <_JointCandidate>[];
    for (var i = 0; i < contributions.length; i++) {
      for (var j = i + 1; j < contributions.length; j++) {
        final a = contributions[i];
        final b = contributions[j];
        if (a.authorId == b.authorId) continue;
        final causal = a.replyToId == b.id || b.replyToId == a.id;
        final closeInTime =
            (a.authoredAtMs - b.authoredAtMs).abs() <= simultaneousWindowMs;
        if (!causal && !closeInTime) continue;
        candidates.add(
          _JointCandidate(
            a: a,
            b: b,
            priority: causal ? 0 : 1,
          ),
        );
      }
    }
    candidates.sort((a, b) {
      var result = a.priority.compareTo(b.priority);
      if (result != 0) return result;
      result = a.time.compareTo(b.time);
      if (result != 0) return result;
      return a.key.compareTo(b.key);
    });

    final used = <String>{};
    final result = <FireworkCulmination>[];
    for (final candidate in candidates) {
      if (used.contains(candidate.a.id) || used.contains(candidate.b.id)) {
        continue;
      }
      used
        ..add(candidate.a.id)
        ..add(candidate.b.id);
      final first = candidate.a.id.compareTo(candidate.b.id) <= 0
          ? candidate.a
          : candidate.b;
      final second = identical(first, candidate.a) ? candidate.b : candidate.a;
      result.add(
        FireworkCulmination(
          id: 'joint-${first.id}-${second.id}',
          firstId: first.id,
          secondId: second.id,
          x: ((first.x + second.x) / 2).clamp(.08, .92).toDouble(),
          y: ((first.y + second.y) / 2 - .08).clamp(.12, .72).toDouble(),
          seed: _mix(first.seed, second.seed, candidate.key),
          paletteA: first.palette,
          paletteB: second.palette,
          authoredAtMs: math.max(first.authoredAtMs, second.authoredAtMs),
        ),
      );
    }
    result.sort((a, b) {
      final order = a.authoredAtMs.compareTo(b.authoredAtMs);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
    return result;
  }

  int _mix(int a, int b, String key) {
    var value = (a ^ (b * 1664525)) & 0x7fffffff;
    for (final unit in key.codeUnits) {
      value = ((value ^ unit) * 16777619) & 0x7fffffff;
    }
    return value;
  }

  int _fingerprint(List<FireworkContribution> contributions) {
    var value = 0x811c9dc5;
    for (final unit in contributions
        .map((item) => item.canonicalSignature)
        .join('~')
        .codeUnits) {
      value = ((value ^ unit) * 16777619) & 0xffffffff;
    }
    return value;
  }
}

class _JointCandidate {
  const _JointCandidate({
    required this.a,
    required this.b,
    required this.priority,
  });

  final FireworkContribution a;
  final FireworkContribution b;
  final int priority;

  int get time => math.max(a.authoredAtMs, b.authoredAtMs);
  String get key =>
      a.id.compareTo(b.id) <= 0 ? '${a.id}|${b.id}' : '${b.id}|${a.id}';
}
