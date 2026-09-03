import '../../../session/application/mode_event.dart';
import 'firework_models.dart';

class FireworkPacket {
  const FireworkPacket(this.records, {required this.newestId});

  final List<FireworkContribution> records;
  final String newestId;

  FireworkContribution get newest =>
      records.firstWhere((record) => record.id == newestId);
}

abstract final class FireworkProtocol {
  static const eventType = 'firework';
  static const version = 2;
  static const maxHistoryRecords = 24;

  static ModeEvent encode(
    FireworkContribution newest, {
    Iterable<FireworkContribution> history = const [],
  }) {
    final records = [
      ...history.where((item) => item.id != newest.id),
      newest,
    ];
    final tail = records.length <= maxHistoryRecords
        ? records
        : records.sublist(records.length - maxHistoryRecords);
    return ModeEvent(
      type: eventType,
      data: {
        'v': version,
        'newestId': newest.id,
        'records': tail.map(_encodeRecord).toList(growable: false),
      },
    );
  }

  static FireworkPacket? tryDecode(
    ModeEvent event, {
    required int receivedAtMs,
  }) {
    if (event.type != eventType) return null;
    final rawRecords = event.data['records'];
    if (rawRecords is List) {
      final records = <FireworkContribution>[];
      for (final raw in rawRecords) {
        if (raw is! Map) continue;
        final decoded = _decodeRecord(Map<String, dynamic>.from(raw));
        if (decoded != null) records.add(decoded);
      }
      if (records.isEmpty) return null;
      final requestedNewest = event.data['newestId'];
      final newestId = requestedNewest is String &&
              records.any((record) => record.id == requestedNewest)
          ? requestedNewest
          : records.last.id;
      return FireworkPacket(records, newestId: newestId);
    }

    final x = _finite(event.data['x']);
    final y = _finite(event.data['y']);
    if (x == null || y == null) return null;
    final rawColor = (event.data['color'] as num?)?.toInt() ?? 0x9747ff;
    final legacy = FireworkContribution(
      id: 'legacy-$receivedAtMs-${x.toStringAsFixed(4)}-${y.toStringAsFixed(4)}',
      authorId: 'partner-legacy',
      x: x,
      y: y,
      authoredAtMs: receivedAtMs,
      sequence: 0,
      seed: rawColor ^ receivedAtMs,
      palette: rawColor,
    ).normalized();
    return FireworkPacket([legacy], newestId: legacy.id);
  }

  static Map<String, Object?> _encodeRecord(FireworkContribution item) => {
        'id': item.id,
        'a': item.authorId,
        'x': item.x,
        'y': item.y,
        'at': item.authoredAtMs,
        's': item.sequence,
        'seed': item.seed,
        'p': item.palette,
        if (item.replyToId != null) 'reply': item.replyToId,
      };

  static FireworkContribution? _decodeRecord(Map<String, dynamic> raw) {
    final id = raw['id'];
    final author = raw['a'];
    final x = _finite(raw['x']);
    final y = _finite(raw['y']);
    final at = raw['at'];
    final sequence = raw['s'];
    final seed = raw['seed'];
    final palette = raw['p'];
    final reply = raw['reply'];
    if (id is! String ||
        id.isEmpty ||
        author is! String ||
        author.isEmpty ||
        x == null ||
        y == null ||
        at is! num ||
        sequence is! num ||
        seed is! num ||
        palette is! num ||
        (reply != null && reply is! String)) {
      return null;
    }
    return FireworkContribution(
      id: id,
      authorId: author,
      x: x,
      y: y,
      authoredAtMs: at.toInt(),
      sequence: sequence.toInt(),
      seed: seed.toInt(),
      palette: palette.toInt(),
      replyToId: reply as String?,
    ).normalized();
  }

  static double? _finite(Object? raw) {
    if (raw is! num) return null;
    final value = raw.toDouble();
    return value.isFinite ? value : null;
  }
}
