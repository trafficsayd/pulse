import 'dart:math' as math;

enum KnockDepth { soft, clear, deep }

enum KnockContactClass { tip, soft, broad }

double _unit(num value) => value.toDouble().clamp(0.0, 1.0);

class KnockCharacter {
  const KnockCharacter({
    required this.intensity,
    required this.sharpness,
    required this.durationMs,
    required this.contactClass,
    required this.confidence,
  });

  const KnockCharacter.legacy()
      : intensity = 0.5,
        sharpness = 0.58,
        durationMs = 80,
        contactClass = KnockContactClass.tip,
        confidence = 0.35;

  final double intensity;
  final double sharpness;
  final int durationMs;
  final KnockContactClass contactClass;
  final double confidence;

  KnockDepth get depth => switch (intensity) {
        < 0.34 => KnockDepth.soft,
        < 0.68 => KnockDepth.clear,
        _ => KnockDepth.deep,
      };

  Map<String, Object> toMap() => {
        'intensity': intensity,
        'sharpness': sharpness,
        'durationMs': durationMs,
        'contactClass': contactClass.name,
        'confidence': confidence,
      };

  static KnockCharacter? tryFromMap(Object? raw) {
    if (raw is! Map) return null;
    final intensity = raw['intensity'];
    final sharpness = raw['sharpness'];
    final duration = raw['durationMs'];
    final contact = raw['contactClass'];
    final confidence = raw['confidence'];
    if (intensity is! num ||
        sharpness is! num ||
        duration is! num ||
        contact is! String ||
        confidence is! num) {
      return null;
    }
    if (intensity < 0 ||
        intensity > 1 ||
        sharpness < 0 ||
        sharpness > 1 ||
        duration < 1 ||
        duration > 1500 ||
        confidence < 0 ||
        confidence > 1) {
      return null;
    }
    KnockContactClass? contactClass;
    for (final value in KnockContactClass.values) {
      if (value.name == contact) {
        contactClass = value;
        break;
      }
    }
    if (contactClass == null) return null;
    return KnockCharacter(
      intensity: _unit(intensity),
      sharpness: _unit(sharpness),
      durationMs: duration.toInt(),
      contactClass: contactClass,
      confidence: _unit(confidence),
    );
  }
}

class KnockHit {
  const KnockHit({
    required this.id,
    required this.seriesId,
    required this.sequence,
    required this.x,
    required this.y,
    required this.relativeOffsetMs,
    required this.character,
    this.replyToSeriesId,
  });

  final String id;
  final String seriesId;
  final int sequence;
  final double x;
  final double y;
  final int relativeOffsetMs;
  final KnockCharacter character;
  final String? replyToSeriesId;

  Map<String, Object> toMap() => {
        'id': id,
        'seriesId': seriesId,
        'sequence': sequence,
        'x': x,
        'y': y,
        'relativeOffsetMs': relativeOffsetMs,
        'character': character.toMap(),
        if (replyToSeriesId != null) 'replyToSeriesId': replyToSeriesId!,
      };

  static KnockHit? tryFromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final seriesId = raw['seriesId'];
    final sequence = raw['sequence'];
    final x = raw['x'];
    final y = raw['y'];
    final offset = raw['relativeOffsetMs'];
    final replyTo = raw['replyToSeriesId'];
    final character = KnockCharacter.tryFromMap(raw['character']);
    if (id is! String ||
        id.isEmpty ||
        id.length > 96 ||
        seriesId is! String ||
        seriesId.isEmpty ||
        seriesId.length > 96 ||
        sequence is! num ||
        sequence < 0 ||
        sequence > 1024 ||
        x is! num ||
        x < 0 ||
        x > 1 ||
        y is! num ||
        y < 0 ||
        y > 1 ||
        offset is! num ||
        offset < 0 ||
        offset > 12000 ||
        character == null ||
        (replyTo != null && replyTo is! String)) {
      return null;
    }
    return KnockHit(
      id: id,
      seriesId: seriesId,
      sequence: sequence.toInt(),
      x: _unit(x),
      y: _unit(y),
      relativeOffsetMs: offset.toInt(),
      character: character,
      replyToSeriesId: replyTo as String?,
    );
  }
}

class KnockVisualHit {
  const KnockVisualHit({
    required this.hit,
    required this.createdAt,
    required this.isLocal,
  });

  final KnockHit hit;
  final DateTime createdAt;
  final bool isLocal;

  double progress(DateTime now, {int lifetimeMs = 1050}) =>
      math.min(1, now.difference(createdAt).inMilliseconds / lifetimeMs);
}
