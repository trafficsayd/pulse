import 'dart:collection';

import '../../session/application/mode_event.dart';

/// Brushes shared by the Flutter canvas and the Android lock-screen renderer.
///
/// The wire index is stable. Add new brushes only at the end so older clients
/// can continue to render a sensible fallback.
enum RayBrushEffect { clean, neon, glow, watercolor, sparkles }

/// Lamport version used to order canvas-wide operations without trusting the
/// wall clocks of the two phones.
class RayVersion implements Comparable<RayVersion> {
  const RayVersion(this.clock, this.actor);

  const RayVersion.zero()
      : clock = 0,
        actor = '';

  final int clock;
  final String actor;

  @override
  int compareTo(RayVersion other) {
    final byClock = clock.compareTo(other.clock);
    return byClock != 0 ? byClock : actor.compareTo(other.actor);
  }

  Map<String, dynamic> toWire() => {'c': clock, 'a': actor};

  static RayVersion fromWire(Object? value) {
    if (value is! Map) return const RayVersion.zero();
    return RayVersion(
      _int(value['c']).clamp(0, 1 << 52),
      (value['a'] as String? ?? '').substringSafe(0, 80),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RayVersion && other.clock == clock && other.actor == actor;

  @override
  int get hashCode => Object.hash(clock, actor);
}

/// A pressure-aware point in normalized canvas coordinates.
class RayPoint {
  const RayPoint({
    required this.x,
    required this.y,
    this.pressure = 1,
    this.elapsedMs = 0,
  });

  final double x;
  final double y;
  final double pressure;
  final int elapsedMs;

  List<num> toWire() => [
        _quantize(x, 10000),
        _quantize(y, 10000),
        _quantize(pressure, 1000),
        elapsedMs.clamp(0, 600000),
      ];

  static RayPoint? fromWire(Object? value) {
    if (value is! List || value.length < 2) return null;
    final x = _doubleOrNull(value[0]);
    final y = _doubleOrNull(value[1]);
    if (x == null || y == null) return null;
    return RayPoint(
      x: x.clamp(0, 1),
      y: y.clamp(0, 1),
      pressure: (_doubleOrNull(value.length > 2 ? value[2] : null) ?? 1)
          .clamp(0.12, 1.8),
      elapsedMs: _int(value.length > 3 ? value[3] : null).clamp(0, 600000),
    );
  }
}

/// One immutable-looking stroke. [points] is kept mutable internally so live
/// input can append without allocating a whole canvas on every pointer event.
class RayStroke {
  RayStroke({
    required this.id,
    required this.ownerId,
    required this.version,
    required this.colorValue,
    required this.width,
    required this.effect,
    required List<RayPoint> points,
    this.complete = false,
  }) : points = List<RayPoint>.of(points);

  final String id;
  final String ownerId;
  final RayVersion version;
  final int colorValue;
  final double width;
  final RayBrushEffect effect;
  final List<RayPoint> points;
  bool complete;

  Map<String, dynamic> toWire({int maxPoints = 180}) {
    final sampled = _sample(points, maxPoints);
    return {
      'id': id,
      'owner': ownerId,
      'version': version.toWire(),
      'color': colorValue,
      'width': _quantize(width, 100),
      'effect': effect.index,
      'complete': complete,
      'points': sampled.map((point) => point.toWire()).toList(growable: false),
    };
  }

  static RayStroke? fromWire(Object? value, {bool complete = false}) {
    if (value is! Map) return null;
    final id = (value['id'] as String? ?? '').substringSafe(0, 120);
    final owner = (value['owner'] as String? ?? '').substringSafe(0, 80);
    final rawPoints = value['points'];
    if (id.isEmpty || owner.isEmpty || rawPoints is! List) return null;
    final points = <RayPoint>[];
    for (final raw in rawPoints.take(RaySketchEngine.maxPointsPerStroke)) {
      final point = RayPoint.fromWire(raw);
      if (point != null) points.add(point);
    }
    if (points.isEmpty) return null;
    final effectIndex = _int(value['effect']);
    return RayStroke(
      id: id,
      ownerId: owner,
      version: RayVersion.fromWire(value['version']),
      colorValue: _int(value['color'], fallback: 0xFF9747FF),
      width: (_doubleOrNull(value['width']) ?? 10).clamp(1, 32),
      effect: effectIndex >= 0 && effectIndex < RayBrushEffect.values.length
          ? RayBrushEffect.values[effectIndex]
          : RayBrushEffect.neon,
      points: points,
      complete: value['complete'] == true || complete,
    );
  }
}

class RayApplyResult {
  const RayApplyResult({this.changed = false, this.reply});

  final bool changed;
  final ModeEvent? reply;
}

/// Deterministic two-person canvas state and versioned real-time protocol.
///
/// Live points are sent in small batches, while `ray_stroke_end` contains the
/// complete sampled stroke. If a live batch is lost during a transport
/// failover, the final stroke repairs it. `ray_state_request` performs the
/// same repair after reconnecting or reopening the mode.
class RaySketchEngine {
  RaySketchEngine({
    required this.ownerId,
    required int canvasColorValue,
  }) : _canvasColorValue = canvasColorValue;

  static const int protocolVersion = 2;
  static const int maxStrokes = 64;
  static const int maxPointsPerStroke = 240;
  static const int maxTombstones = 96;

  final String ownerId;
  final LinkedHashMap<String, RayStroke> _strokes = LinkedHashMap();
  final LinkedHashMap<String, RayVersion> _removed = LinkedHashMap();
  var _clock = 0;
  var _canvasColorValue = 0;
  var _canvasVersion = const RayVersion.zero();
  var _clearVersion = const RayVersion.zero();

  int get canvasColorValue => _canvasColorValue;
  RayVersion get canvasVersion => _canvasVersion;
  RayVersion get clearVersion => _clearVersion;
  int get logicalClock => _clock;
  List<RayStroke> get strokes => List.unmodifiable(_strokes.values);
  bool get isEmpty => _strokes.isEmpty;

  RayStroke? strokeById(String id) => _strokes[id];

  RayVersion nextVersion() => RayVersion(++_clock, ownerId);

  RayStroke beginLocalStroke({
    required String id,
    required int colorValue,
    required double width,
    required RayBrushEffect effect,
    required RayPoint point,
  }) {
    final stroke = RayStroke(
      id: id,
      ownerId: ownerId,
      version: nextVersion(),
      colorValue: colorValue,
      width: width.clamp(1, 32),
      effect: effect,
      points: [point],
    );
    _put(stroke);
    return stroke;
  }

  bool appendLocalPoints(String id, Iterable<RayPoint> points) {
    final stroke = _strokes[id];
    if (stroke == null || stroke.ownerId != ownerId || stroke.complete) {
      return false;
    }
    return _append(stroke, points);
  }

  RayStroke? finishLocalStroke(String id) {
    final stroke = _strokes[id];
    if (stroke == null || stroke.ownerId != ownerId) return null;
    stroke.complete = true;
    return stroke;
  }

  RayStroke? undoLastLocal() {
    RayStroke? found;
    for (final stroke in _strokes.values) {
      if (stroke.ownerId == ownerId && stroke.complete) found = stroke;
    }
    if (found == null) return null;
    _strokes.remove(found.id);
    _recordRemoval(found.id, nextVersion());
    return found;
  }

  ModeEvent undoEvent(String strokeId) => ModeEvent(
        type: 'ray_undo',
        data: {
          'v': protocolVersion,
          'id': strokeId,
          'version': _removed[strokeId]?.toWire(),
        },
      );

  ModeEvent clearLocal() {
    _clearVersion = nextVersion();
    for (final id in _strokes.keys.toList(growable: false)) {
      _recordRemoval(id, _clearVersion);
    }
    _strokes.clear();
    return ModeEvent(
      type: 'ray_clear',
      data: {
        'v': protocolVersion,
        'version': _clearVersion.toWire(),
      },
    );
  }

  ModeEvent setCanvasColor(int colorValue) {
    _canvasColorValue = colorValue;
    _canvasVersion = nextVersion();
    return ModeEvent(
      type: 'ray_canvas',
      data: {
        'v': protocolVersion,
        'color': colorValue,
        'version': _canvasVersion.toWire(),
      },
    );
  }

  ModeEvent beginEvent(RayStroke stroke) => ModeEvent(
        type: 'ray_stroke_begin',
        data: {
          'v': protocolVersion,
          'stroke': stroke.toWire(maxPoints: 1),
        },
      );

  ModeEvent pointsEvent(String strokeId, List<RayPoint> points) => ModeEvent(
        type: 'ray_stroke_points',
        data: {
          'v': protocolVersion,
          'id': strokeId,
          'owner': ownerId,
          'points':
              points.map((point) => point.toWire()).toList(growable: false),
        },
      );

  ModeEvent endEvent(RayStroke stroke) => ModeEvent(
        type: 'ray_stroke_end',
        data: {
          'v': protocolVersion,
          'stroke': stroke.toWire(),
        },
      );

  ModeEvent stateRequestEvent() => ModeEvent(
        type: 'ray_state_request',
        data: {'v': protocolVersion, 'requester': ownerId},
      );

  ModeEvent stateEvent({String type = 'ray_state'}) => ModeEvent(
        type: type,
        data: {
          'v': protocolVersion,
          'owner': ownerId,
          'clock': _clock,
          'canvas': _canvasColorValue,
          'canvasVersion': _canvasVersion.toWire(),
          'clearVersion': _clearVersion.toWire(),
          'removed': [
            for (final entry in _removed.entries)
              {'id': entry.key, 'version': entry.value.toWire()},
          ],
          'strokes': [
            for (final stroke in _strokes.values) stroke.toWire(),
          ],
        },
      );

  RayApplyResult apply(ModeEvent event) {
    switch (event.type) {
      case 'ray_state_request':
        if (event.data['requester'] == ownerId) {
          return const RayApplyResult();
        }
        return RayApplyResult(reply: stateEvent());
      case 'ray_stroke_begin':
        final stroke = RayStroke.fromWire(event.data['stroke']);
        if (stroke == null || stroke.ownerId == ownerId) {
          return const RayApplyResult();
        }
        _observe(stroke.version);
        return RayApplyResult(changed: _put(stroke));
      case 'ray_stroke_points':
        final id = (event.data['id'] as String? ?? '').substringSafe(0, 120);
        final owner =
            (event.data['owner'] as String? ?? '').substringSafe(0, 80);
        if (id.isEmpty || owner == ownerId) return const RayApplyResult();
        final stroke = _strokes[id];
        final rawPoints = event.data['points'];
        if (stroke == null || rawPoints is! List) return const RayApplyResult();
        final points =
            rawPoints.take(32).map(RayPoint.fromWire).whereType<RayPoint>();
        return RayApplyResult(changed: _append(stroke, points));
      case 'ray_stroke_end':
        final stroke = RayStroke.fromWire(event.data['stroke'], complete: true);
        if (stroke == null || stroke.ownerId == ownerId) {
          return const RayApplyResult();
        }
        _observe(stroke.version);
        return RayApplyResult(changed: _put(stroke, replaceSameVersion: true));
      case 'ray_undo':
        return RayApplyResult(changed: _applyUndo(event.data));
      case 'ray_clear':
        return RayApplyResult(changed: _applyClear(event.data));
      case 'ray_canvas':
        return RayApplyResult(changed: _applyCanvas(event.data));
      case 'ray_state':
        return RayApplyResult(changed: _mergeState(event.data));
      case 'ray_card':
        return RayApplyResult(changed: _applyCard(event.data));
      default:
        return const RayApplyResult();
    }
  }

  bool _applyUndo(Map<String, dynamic> data) {
    final id = (data['id'] as String? ?? '').substringSafe(0, 120);
    final version = RayVersion.fromWire(data['version']);
    if (id.isEmpty || version == const RayVersion.zero()) return false;
    _observe(version);
    final previous = _removed[id];
    if (previous != null && previous.compareTo(version) >= 0) return false;
    _recordRemoval(id, version);
    return _strokes.remove(id) != null;
  }

  bool _applyClear(Map<String, dynamic> data) {
    final version = RayVersion.fromWire(data['version']);
    if (version == const RayVersion.zero()) {
      // Backward compatibility with the original unversioned clear event.
      final changed = _strokes.isNotEmpty;
      _strokes.clear();
      return changed;
    }
    _observe(version);
    if (_clearVersion.compareTo(version) >= 0) return false;
    _clearVersion = version;
    var changed = false;
    for (final entry in _strokes.entries.toList(growable: false)) {
      if (entry.value.version.compareTo(version) <= 0) {
        _recordRemoval(entry.key, version);
        _strokes.remove(entry.key);
        changed = true;
      }
    }
    return changed;
  }

  bool _applyCanvas(Map<String, dynamic> data) {
    final color = _intOrNull(data['color']);
    if (color == null) return false;
    final version = RayVersion.fromWire(data['version']);
    if (version != const RayVersion.zero()) {
      _observe(version);
      if (_canvasVersion.compareTo(version) >= 0) return false;
      _canvasVersion = version;
    }
    if (_canvasColorValue == color) return false;
    _canvasColorValue = color;
    return true;
  }

  bool _mergeState(Map<String, dynamic> data) {
    final sender = data['owner'] as String?;
    if (sender == ownerId) return false;
    final remoteClock = _int(data['clock']);
    if (remoteClock > _clock) _clock = remoteClock;
    var changed = false;

    final incomingClear = RayVersion.fromWire(data['clearVersion']);
    if (incomingClear.compareTo(_clearVersion) > 0) {
      changed = _applyClear({'version': incomingClear.toWire()}) || changed;
    }

    final rawRemoved = data['removed'];
    if (rawRemoved is List) {
      for (final raw in rawRemoved.take(maxTombstones)) {
        if (raw is! Map) continue;
        changed = _applyUndo({
              'id': raw['id'],
              'version': raw['version'],
            }) ||
            changed;
      }
    }

    final incomingCanvas = RayVersion.fromWire(data['canvasVersion']);
    if (incomingCanvas.compareTo(_canvasVersion) > 0) {
      changed = _applyCanvas({
            'color': data['canvas'],
            'version': incomingCanvas.toWire(),
          }) ||
          changed;
    }

    final rawStrokes = data['strokes'];
    if (rawStrokes is List) {
      for (final raw in rawStrokes.take(maxStrokes)) {
        final stroke = RayStroke.fromWire(raw, complete: true);
        if (stroke == null || stroke.ownerId == ownerId) continue;
        _observe(stroke.version);
        changed = _put(stroke, replaceSameVersion: true) || changed;
      }
    }
    return changed;
  }

  bool _applyCard(Map<String, dynamic> data) {
    // Protocol v2 cards carry the same mergeable state as reconnect snapshots.
    if (data['v'] == protocolVersion && data['owner'] != null) {
      return _mergeState(data);
    }

    final rawStrokes = data['strokes'];
    if (rawStrokes is! List) return false;
    const legacyOwner = 'legacy-partner';
    final incoming = <RayStroke>[];
    var index = 0;
    for (final raw in rawStrokes.take(16)) {
      if (raw is! Map) continue;
      final copy = Map<String, dynamic>.from(raw.cast<dynamic, dynamic>());
      copy['id'] = 'legacy-${_clock + 1}-${index++}';
      copy['owner'] = legacyOwner;
      copy['version'] = RayVersion(++_clock, legacyOwner).toWire();
      copy['complete'] = true;
      final stroke = RayStroke.fromWire(copy, complete: true);
      if (stroke != null) incoming.add(stroke);
    }
    if (incoming.isEmpty) return false;
    _strokes
      ..clear()
      ..addEntries(incoming.map((stroke) => MapEntry(stroke.id, stroke)));
    final canvas = _intOrNull(data['canvas']);
    if (canvas != null) _canvasColorValue = canvas;
    return true;
  }

  bool _put(RayStroke stroke, {bool replaceSameVersion = false}) {
    if (stroke.version.compareTo(_clearVersion) <= 0) return false;
    final removal = _removed[stroke.id];
    if (removal != null && removal.compareTo(stroke.version) >= 0) return false;
    final existing = _strokes[stroke.id];
    if (existing != null) {
      final ordering = existing.version.compareTo(stroke.version);
      if (ordering > 0 || (ordering == 0 && !replaceSameVersion)) return false;
      if (ordering == 0 && existing.complete && !stroke.complete) return false;
    }
    _strokes[stroke.id] = stroke;
    while (_strokes.length > maxStrokes) {
      _strokes.remove(_strokes.keys.first);
    }
    return true;
  }

  bool _append(RayStroke stroke, Iterable<RayPoint> points) {
    var changed = false;
    for (final point in points) {
      if (stroke.points.length >= maxPointsPerStroke) break;
      final last = stroke.points.isEmpty ? null : stroke.points.last;
      if (last != null &&
          (last.x - point.x).abs() < 0.0004 &&
          (last.y - point.y).abs() < 0.0004) {
        continue;
      }
      stroke.points.add(point);
      changed = true;
    }
    return changed;
  }

  void _recordRemoval(String id, RayVersion version) {
    _removed[id] = version;
    while (_removed.length > maxTombstones) {
      _removed.remove(_removed.keys.first);
    }
  }

  void _observe(RayVersion version) {
    if (version.clock > _clock) _clock = version.clock;
  }
}

List<RayPoint> _sample(List<RayPoint> points, int maxPoints) {
  if (points.length <= maxPoints) return points;
  final result = <RayPoint>[];
  final step = (points.length - 1) / (maxPoints - 1);
  for (var index = 0; index < maxPoints; index++) {
    result.add(points[(index * step).round().clamp(0, points.length - 1)]);
  }
  return result;
}

double _quantize(double value, int precision) =>
    (value * precision).round() / precision;

double? _doubleOrNull(Object? value) => value is num ? value.toDouble() : null;

int? _intOrNull(Object? value) => value is num ? value.toInt() : null;

int _int(Object? value, {int fallback = 0}) =>
    value is num ? value.toInt() : fallback;

extension on String {
  String substringSafe(int start, int end) {
    if (length <= start) return '';
    final safeEnd = end < start ? start : (end > length ? length : end);
    return substring(start, safeEnd);
  }
}
