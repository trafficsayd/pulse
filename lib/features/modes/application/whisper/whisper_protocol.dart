import '../../../session/application/mode_event.dart';
import 'whisper_feeling.dart';

/// Versioned wire representation for the Audio-to-Feeling engine.
///
/// The established `whisper_level` event name is retained so older clients
/// and the app-wide mode router continue to recognise the mode. The payload
/// itself contains no PCM, samples, text, codec data, or recording path.
abstract final class WhisperProtocol {
  static const eventType = 'whisper_level';
  static const version = 2;

  static ModeEvent encode(WhisperFeeling feeling) {
    final value = feeling.normalized();
    return ModeEvent(type: eventType, data: {
      'v': version,
      'seq': value.sequence,
      'at': value.capturedAtMs,
      'intensity': _quantize(value.intensity),
      'breathiness': _quantize(value.breathiness),
      'proximity': _quantize(value.proximity),
      if (value.isFallback) 'fallback': true,
    });
  }

  static WhisperFeeling? tryDecode(ModeEvent event) {
    if (event.type != eventType) return null;
    final data = event.data;

    // v1 compatibility: the old screen sent only `{level}`.
    if (data['level'] case final num legacy) {
      final level = legacy.toDouble().clamp(0.0, 1.0);
      return WhisperFeeling(
        sequence: 0,
        capturedAtMs: 0,
        intensity: level,
        breathiness: 0.72,
        proximity: level,
      );
    }

    final intensity = _finiteDouble(data['intensity']);
    final breathiness = _finiteDouble(data['breathiness']);
    final proximity = _finiteDouble(data['proximity']);
    if (intensity == null || breathiness == null || proximity == null) {
      return null;
    }
    return WhisperFeeling(
      sequence: (data['seq'] as num?)?.toInt() ?? 0,
      capturedAtMs: (data['at'] as num?)?.toInt() ?? 0,
      intensity: intensity,
      breathiness: breathiness,
      proximity: proximity,
      isFallback: data['fallback'] == true,
    ).normalized();
  }

  static double _quantize(double value) =>
      (value.clamp(0.0, 1.0) * 1000).round() / 1000;

  static double? _finiteDouble(Object? value) {
    if (value is! num) return null;
    final result = value.toDouble();
    return result.isFinite ? result : null;
  }
}
