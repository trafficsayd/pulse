import '../../../session/application/mode_event.dart';
import 'thunder_models.dart';

abstract final class ThunderProtocol {
  static const eventType = 'thunder_strike';

  static ModeEvent strike(ThunderStrike strike) => ModeEvent(
        type: eventType,
        data: {'v': ThunderStrike.protocolVersion, ...strike.toMap()},
      );

  static ThunderStrike? tryParse(ModeEvent event, {int? nowMs}) {
    if (event.type != eventType) return null;
    final version = event.data['v'];
    if (version == ThunderStrike.protocolVersion) {
      return ThunderStrike.tryFromMap(event.data);
    }
    final x = event.data['x'];
    if (version != null || x is! num || x < 0 || x > 1) return null;
    final timestamp = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return ThunderStrike(
      id: 'legacy-$timestamp-${x.toStringAsFixed(3)}',
      createdAtMs: timestamp,
      originX: x.toDouble(),
      originY: 0,
      directionX: .12,
      directionY: .9927738917,
      intensity: .62,
      velocity: .55,
      seed: (x * 1000000).round() & 0x7fffffff,
      handoffMs: 0,
    );
  }

  static bool isVersioned(ModeEvent event) =>
      event.type == eventType &&
      event.data['v'] == ThunderStrike.protocolVersion;
}
