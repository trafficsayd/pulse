import '../../../session/application/mode_event.dart';
import 'bell_models.dart';

abstract final class BellProtocol {
  static const eventType = 'bell_ring';
  static const version = 2;

  static ModeEvent encode(BellStrike strike) {
    final value = strike.normalized();
    return ModeEvent(type: eventType, data: {
      'v': version,
      'id': value.id,
      't': value.occurredAtMs,
      'material': value.material.name,
      'strength': value.strength,
      'direction': value.direction,
      'pitch': value.pitch,
      'resonance': value.resonanceSeconds,
    });
  }

  static BellStrike? decode(ModeEvent event) {
    if (event.type != eventType) return null;
    final data = event.data;
    final strength = _number(data['strength'] ?? data['intensity']);
    if (strength == null) return null;
    final materialName = data['material'] as String?;
    final material = BellMaterial.values.where(
      (value) => value.name == materialName,
    );
    final resolvedMaterial =
        material.isEmpty ? BellMaterial.brass : material.first;
    final profile = BellMaterialProfile.forMaterial(resolvedMaterial);
    final timestamp = (data['t'] as num?)?.toInt() ?? 0;
    return BellStrike(
      id: (data['id'] as String?) ?? 'legacy-$timestamp-$strength',
      occurredAtMs: timestamp,
      material: resolvedMaterial,
      strength: strength,
      direction: _number(data['direction']) ?? 1,
      pitch: _number(data['pitch']) ?? profile.pitch,
      resonanceSeconds: _number(data['resonance']) ?? profile.resonanceSeconds,
      remote: true,
    ).normalized();
  }

  static double? _number(Object? value) =>
      value is num ? value.toDouble() : null;
}

class BellStrikeDeduplicator {
  BellStrikeDeduplicator({this.capacity = 64});

  final int capacity;
  final Set<String> _seen = <String>{};
  final List<String> _order = <String>[];

  bool accept(String id) {
    if (!_seen.add(id)) return false;
    _order.add(id);
    if (_order.length > capacity) {
      _seen.remove(_order.removeAt(0));
    }
    return true;
  }
}
