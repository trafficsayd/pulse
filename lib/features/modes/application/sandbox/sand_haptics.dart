import '../../primitives/haptic_pattern_player.dart';
import 'sand_models.dart';

abstract final class SandHaptics {
  static HapticBeat beatFor(SandCommand command, {required bool remote}) {
    final materialBias = switch (command.material) {
      SandMaterial.amethyst => 12,
      SandMaterial.rose => 22,
      SandMaterial.moonlight => 5,
    };
    final base = switch (command.tool) {
      SandTool.paint => 34,
      SandTool.pour => 58,
      SandTool.erase => 76,
    };
    final amplitude =
        (base + materialBias + command.intensity * 88).round().clamp(1, 220);
    return HapticBeat(
      duration: Duration(
        milliseconds: switch (command.tool) {
          SandTool.paint => remote ? 30 : 24,
          SandTool.pour => remote ? 48 : 42,
          SandTool.erase => 34,
        },
      ),
      amplitude: remote ? (amplitude * .82).round() : amplitude,
    );
  }
}
