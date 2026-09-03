import '../../../session/application/mode_event.dart';
import 'goosebumps_wave.dart';

abstract final class GoosebumpsProtocol {
  static const eventType = 'goosebumps_wave';

  static ModeEvent wave(GoosebumpsWave wave) => ModeEvent(
        type: eventType,
        data: {'v': GoosebumpsWave.protocolVersion, ...wave.toMap()},
      );

  static GoosebumpsWave? tryParse(ModeEvent event, {int? nowMs}) {
    if (event.type != eventType) return null;
    final version = event.data['v'];
    if (version == GoosebumpsWave.protocolVersion) {
      return GoosebumpsWave.tryFromMap(event.data);
    }
    // Compatibility with the original tap-only implementation.
    final x = event.data['x'];
    final y = event.data['y'];
    if (version != null || x is! num || y is! num) return null;
    if (x < 0 || x > 1 || y < 0 || y > 1) return null;
    final timestamp = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return GoosebumpsWave(
      id: 'legacy-$timestamp-${x.toStringAsFixed(3)}-${y.toStringAsFixed(3)}',
      createdAtMs: timestamp,
      startX: x.toDouble(),
      startY: y.toDouble(),
      directionX: 0,
      directionY: -1,
      speed: .45,
      intensity: .5,
      travelMs: 760,
      handoffMs: 0,
    );
  }

  static bool isVersioned(ModeEvent event) =>
      event.type == eventType &&
      event.data['v'] == GoosebumpsWave.protocolVersion;
}
