import '../../../session/application/mode_event.dart';
import 'sand_models.dart';

abstract final class SandProtocol {
  static const eventType = 'sandbox_particle';

  static ModeEvent command(SandCommand command) => ModeEvent(
        type: eventType,
        data: {'v': SandCommand.protocolVersion, ...command.toMap()},
      );

  static SandCommand? tryParse(ModeEvent event, {int? nowMs}) {
    if (event.type != eventType) return null;
    final version = event.data['v'];
    if (version == SandCommand.protocolVersion) {
      return SandCommand.tryFromMap(event.data);
    }
    final x = event.data['x'];
    final y = event.data['y'];
    final seed = event.data['seed'];
    if (version != null ||
        x is! num ||
        y is! num ||
        x < 0 ||
        x > 1 ||
        y < 0 ||
        y > 1) {
      return null;
    }
    final timestamp = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final safeSeed = seed is num
        ? seed.toInt().clamp(0, 0x7fffffff)
        : (x * 100000 + y * 1000).round() & 0x7fffffff;
    return SandCommand(
      id: 'legacy-$timestamp-$safeSeed',
      createdAtMs: timestamp,
      tool: SandTool.pour,
      material: SandMaterial.amethyst,
      points: [SandPoint(x.toDouble(), y.toDouble())],
      intensity: .52,
      seed: safeSeed,
    );
  }

  static bool isVersioned(ModeEvent event) =>
      event.type == eventType && event.data['v'] == SandCommand.protocolVersion;
}

class SandCommandDeduplicator {
  SandCommandDeduplicator({this.capacity = 128});

  final int capacity;
  final Set<String> _ids = <String>{};
  final List<String> _order = <String>[];

  bool accept(String id) {
    if (!_ids.add(id)) return false;
    _order.add(id);
    while (_order.length > capacity) {
      _ids.remove(_order.removeAt(0));
    }
    return true;
  }
}
