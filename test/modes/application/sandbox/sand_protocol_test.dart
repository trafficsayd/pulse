import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/sandbox/sand_models.dart';
import 'package:pulse/features/modes/application/sandbox/sand_protocol.dart';
import 'package:pulse/features/session/application/mode_event.dart';

void main() {
  const command = SandCommand(
    id: 'sand-v2',
    createdAtMs: 1700000000000,
    tool: SandTool.paint,
    material: SandMaterial.rose,
    points: [SandPoint(.2, .3), SandPoint(.7, .8)],
    intensity: .74,
    seed: 42,
  );

  test('versioned material command survives wire round trip', () {
    final event = ModeEvent.decode(SandProtocol.command(command).encode());
    final decoded = SandProtocol.tryParse(event);
    expect(event.data['v'], SandCommand.protocolVersion);
    expect(decoded?.id, command.id);
    expect(decoded?.tool, SandTool.paint);
    expect(decoded?.material, SandMaterial.rose);
    expect(decoded?.points, hasLength(2));
  });

  test('legacy particle becomes a compatible pour command', () {
    final decoded = SandProtocol.tryParse(
      const ModeEvent(
        type: SandProtocol.eventType,
        data: {'x': .4, 'y': .6, 'seed': 7},
      ),
      nowMs: 123,
    );
    expect(decoded, isNotNull);
    expect(decoded!.tool, SandTool.pour);
    expect(decoded.points.single.x, .4);
    expect(decoded.seed, 7);
  });

  test('oversized and malformed payloads are rejected', () {
    final tooMany = List.generate(25, (_) => [0.5, 0.5]);
    expect(
      SandProtocol.tryParse(ModeEvent(
        type: SandProtocol.eventType,
        data: {
          'v': 2,
          'id': 'large',
          'sentAtMs': 1,
          'tool': 'paint',
          'material': 'rose',
          'points': tooMany,
          'intensity': .5,
          'seed': 1,
        },
      )),
      isNull,
    );
    expect(
      SandProtocol.tryParse(const ModeEvent(
        type: SandProtocol.eventType,
        data: {'v': 2, 'id': 'broken'},
      )),
      isNull,
    );
  });
}
