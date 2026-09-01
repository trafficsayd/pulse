import 'knock_models.dart';

class KnockSeriesController {
  KnockSeriesController({
    required String Function() idFactory,
    this.idleWindowMs = 900,
    this.maxHits = 16,
    this.maxDurationMs = 12000,
  }) : _idFactory = idFactory;

  final String Function() _idFactory;
  final int idleWindowMs;
  final int maxHits;
  final int maxDurationMs;

  String? _seriesId;
  int? _startedAtMs;
  int? _lastHitAtMs;
  int _sequence = 0;

  String? get activeSeriesId => _seriesId;
  int get hitCount => _sequence;

  bool shouldStartNew(int nowMs) =>
      _seriesId == null ||
      _startedAtMs == null ||
      _lastHitAtMs == null ||
      nowMs - _lastHitAtMs! > idleWindowMs ||
      nowMs - _startedAtMs! > maxDurationMs ||
      _sequence >= maxHits;

  KnockHit add({
    required int nowMs,
    required double x,
    required double y,
    required KnockCharacter character,
    String? replyToSeriesId,
  }) {
    if (shouldStartNew(nowMs)) {
      _seriesId = _idFactory();
      _startedAtMs = nowMs;
      _lastHitAtMs = null;
      _sequence = 0;
    }
    final seriesId = _seriesId!;
    final hit = KnockHit(
      id: _idFactory(),
      seriesId: seriesId,
      sequence: _sequence,
      x: x.clamp(0.0, 1.0).toDouble(),
      y: y.clamp(0.0, 1.0).toDouble(),
      relativeOffsetMs: nowMs - _startedAtMs!,
      character: character,
      replyToSeriesId: replyToSeriesId,
    );
    _sequence++;
    _lastHitAtMs = nowMs;
    return hit;
  }

  bool isIdleAt(int nowMs) =>
      _lastHitAtMs != null && nowMs - _lastHitAtMs! >= idleWindowMs;

  String? end() {
    final ended = _seriesId;
    _seriesId = null;
    _startedAtMs = null;
    _lastHitAtMs = null;
    _sequence = 0;
    return ended;
  }
}
