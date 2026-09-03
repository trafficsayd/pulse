import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/sandbox/sand_haptics.dart';
import 'package:pulse/features/modes/application/sandbox/sand_models.dart';
import 'package:pulse/features/modes/application/sandbox/sand_simulation.dart';

void main() {
  SandCommand command({
    required String id,
    required SandTool tool,
    int seed = 1,
    List<SandPoint> points = const [SandPoint(.5, .2)],
  }) =>
      SandCommand(
        id: id,
        createdAtMs: 1,
        tool: tool,
        material: SandMaterial.amethyst,
        points: points,
        intensity: .7,
        seed: seed,
      );

  test('same command sequence produces the same deterministic world', () {
    final first = SandSimulation();
    final second = SandSimulation();
    final commands = [
      command(
        id: 'paint',
        tool: SandTool.paint,
        seed: 11,
        points: const [SandPoint(.2, .2), SandPoint(.8, .32)],
      ),
      command(id: 'pour', tool: SandTool.pour, seed: 27),
      command(
        id: 'erase',
        tool: SandTool.erase,
        seed: 31,
        points: const [SandPoint(.45, .78), SandPoint(.58, .78)],
      ),
    ];
    for (final value in commands) {
      expect(first.enqueue(value), isTrue);
      expect(second.enqueue(value), isTrue);
    }
    first.drain();
    second.drain();

    expect(first.world.digest(), second.world.digest());
    expect(first.world.cells, orderedEquals(second.world.cells));
  });

  test('pour falls and erase removes bounded grid material', () {
    final simulation = SandSimulation(world: SandWorld(columns: 20, rows: 30));
    simulation.enqueue(command(id: 'pour', tool: SandTool.pour, seed: 9));
    simulation.drain();
    final afterPour = simulation.world.filledCells;
    expect(afterPour, greaterThan(0));
    expect(simulation.world.cells.length, 600);

    simulation.enqueue(command(
      id: 'erase',
      tool: SandTool.erase,
      points: const [SandPoint(.5, .93)],
    ));
    simulation.drain();
    expect(simulation.world.filledCells, lessThan(afterPour));
    expect(simulation.world.filledCells, lessThanOrEqualTo(600));
  });

  test('queue and per-tick work are hard bounded', () {
    final simulation = SandSimulation(maxQueue: 4);
    for (var i = 0; i < 4; i++) {
      expect(
          simulation.enqueue(command(id: '$i', tool: SandTool.paint)), isTrue);
    }
    expect(simulation.enqueue(command(id: 'overflow', tool: SandTool.paint)),
        isFalse);
    final moves = simulation.world.step(seed: 1, maxMoves: 5);
    expect(moves, lessThanOrEqualTo(5));
  });

  test('material and tool semantics produce distinct bounded haptics', () {
    final paint = SandHaptics.beatFor(
      command(id: 'p', tool: SandTool.paint),
      remote: false,
    );
    final pour = SandHaptics.beatFor(
      command(id: 'f', tool: SandTool.pour),
      remote: false,
    );
    final remote = SandHaptics.beatFor(
      command(id: 'r', tool: SandTool.pour),
      remote: true,
    );
    expect(pour.amplitude, greaterThan(paint.amplitude));
    expect(remote.amplitude, lessThan(pour.amplitude));
    expect(pour.amplitude, inInclusiveRange(1, 220));
  });
}
