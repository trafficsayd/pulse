import '../../../session/application/mode_event.dart';
import 'knock_models.dart';

abstract final class KnockProtocol {
  static const version = 2;
  static const supportedTypes = {
    'tap',
    'knock_begin',
    'knock_hit',
    'knock_end',
    'knock_reply',
    'knock_receipt',
  };

  static ModeEvent begin(String seriesId) => ModeEvent(
        type: 'knock_begin',
        data: {'v': version, 'seriesId': seriesId},
      );

  static ModeEvent hit(KnockHit hit, {bool reply = false}) => ModeEvent(
        type: reply ? 'knock_reply' : 'knock_hit',
        data: {'v': version, ...hit.toMap()},
      );

  static ModeEvent end(String seriesId, int count) => ModeEvent(
        type: 'knock_end',
        data: {'v': version, 'seriesId': seriesId, 'count': count},
      );

  static ModeEvent receipt(String seriesId, String eventId) => ModeEvent(
        type: 'knock_receipt',
        data: {
          'v': version,
          'seriesId': seriesId,
          'eventId': eventId,
        },
      );

  static KnockHit? tryParseHit(ModeEvent event) {
    if (event.type == 'tap') {
      final x = event.data['x'];
      final y = event.data['y'];
      if (x is! num || y is! num || x < 0 || x > 1 || y < 0 || y > 1) {
        return null;
      }
      return KnockHit(
        id: 'legacy-${x.toStringAsFixed(4)}-${y.toStringAsFixed(4)}',
        seriesId: 'legacy',
        sequence: 0,
        x: x.toDouble(),
        y: y.toDouble(),
        relativeOffsetMs: 0,
        character: const KnockCharacter.legacy(),
      );
    }
    if (event.type != 'knock_hit' && event.type != 'knock_reply') return null;
    if (event.data['v'] != version) return null;
    return KnockHit.tryFromMap(event.data);
  }
}

class KnockDeduplicator {
  KnockDeduplicator({this.capacity = 128});

  final int capacity;
  final Set<String> _seen = {};
  final List<String> _order = [];

  bool accept(String id) {
    if (!_seen.add(id)) return false;
    _order.add(id);
    if (_order.length > capacity) {
      _seen.remove(_order.removeAt(0));
    }
    return true;
  }
}
