import '../../../session/application/mode_event.dart';
import 'constellation_models.dart';

class ConstellationPacket {
  const ConstellationPacket(this.records);

  final List<ConstellationStar> records;
}

/// Backwards-compatible `star` protocol with compact history reconciliation.
abstract final class ConstellationProtocol {
  static const eventType = 'star';
  static const version = 2;
  static const maxHistoryRecords = 32;

  static ModeEvent encode(
    ConstellationStar newest, {
    Iterable<ConstellationStar> history = const [],
  }) {
    final records = <ConstellationStar>[
      ...history.where((star) => star.id != newest.id),
      newest,
    ];
    final tail = records.length <= maxHistoryRecords
        ? records
        : records.sublist(records.length - maxHistoryRecords);
    return ModeEvent(
      type: eventType,
      data: {
        'v': version,
        'records': tail.map(_encodeStar).toList(growable: false),
      },
    );
  }

  static ConstellationPacket? tryDecode(
    ModeEvent event, {
    required int receivedAtMs,
  }) {
    if (event.type != eventType) return null;
    final rawRecords = event.data['records'];
    if (rawRecords is List) {
      final decoded = <ConstellationStar>[];
      for (final raw in rawRecords) {
        if (raw is! Map) continue;
        final record = _tryDecodeStar(Map<String, dynamic>.from(raw));
        if (record != null) decoded.add(record);
      }
      return decoded.isEmpty ? null : ConstellationPacket(decoded);
    }

    // Legacy v1 packets had coordinates only. They remain visible during a
    // rolling upgrade; receive time distinguishes intentional repeated taps.
    final x = _finiteDouble(event.data['x']);
    final y = _finiteDouble(event.data['y']);
    if (x == null || y == null) return null;
    return ConstellationPacket([
      ConstellationStar(
        id: 'legacy-$receivedAtMs-${x.toStringAsFixed(5)}-${y.toStringAsFixed(5)}',
        authorId: 'partner-legacy',
        x: x,
        y: y,
        authoredAtMs: receivedAtMs,
        sequence: 0,
        energy: .64,
      ).normalized(),
    ]);
  }

  static Map<String, Object> _encodeStar(ConstellationStar star) => {
        'id': star.id,
        'a': star.authorId,
        'x': star.x,
        'y': star.y,
        'at': star.authoredAtMs,
        's': star.sequence,
        'e': star.energy,
      };

  static ConstellationStar? _tryDecodeStar(Map<String, dynamic> raw) {
    final id = raw['id'];
    final author = raw['a'];
    final x = _finiteDouble(raw['x']);
    final y = _finiteDouble(raw['y']);
    final at = raw['at'];
    final sequence = raw['s'];
    final energy = _finiteDouble(raw['e']) ?? .72;
    if (id is! String ||
        id.isEmpty ||
        author is! String ||
        author.isEmpty ||
        x == null ||
        y == null ||
        at is! num ||
        sequence is! num) {
      return null;
    }
    return ConstellationStar(
      id: id,
      authorId: author,
      x: x,
      y: y,
      authoredAtMs: at.toInt(),
      sequence: sequence.toInt(),
      energy: energy,
    ).normalized();
  }

  static double? _finiteDouble(Object? value) {
    if (value is! num) return null;
    final result = value.toDouble();
    return result.isFinite ? result : null;
  }
}
