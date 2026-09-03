import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/goosebumps/goosebumps_protocol.dart';
import 'package:pulse/features/modes/application/goosebumps/goosebumps_wave.dart';
import 'package:pulse/features/session/application/mode_event.dart';

void main() {
  const sample = GoosebumpsWave(
    id: 'wave-v2',
    createdAtMs: 1700000000000,
    startX: .25,
    startY: .75,
    directionX: .8,
    directionY: -.6,
    speed: .64,
    intensity: .82,
    travelMs: 670,
    handoffMs: 430,
  );

  test('versioned wave survives event and wire round trip', () {
    final encoded = GoosebumpsProtocol.wave(sample).encode();
    final event = ModeEvent.decode(encoded);
    final decoded = GoosebumpsProtocol.tryParse(event);

    expect(event.data['v'], GoosebumpsWave.protocolVersion);
    expect(decoded?.id, sample.id);
    expect(decoded?.directionX, closeTo(.8, .0001));
    expect(decoded?.directionY, closeTo(-.6, .0001));
    expect(decoded?.speed, sample.speed);
    expect(decoded?.intensity, sample.intensity);
  });

  test('legacy point becomes a safe upward fallback wave', () {
    final wave = GoosebumpsProtocol.tryParse(
      const ModeEvent(
        type: GoosebumpsProtocol.eventType,
        data: {'x': .3, 'y': .7},
      ),
      nowMs: 1234,
    );

    expect(wave, isNotNull);
    expect(wave!.directionY, -1);
    expect(wave.handoffMs, 0);
  });

  test('malformed and unknown versions are rejected', () {
    expect(
      GoosebumpsProtocol.tryParse(const ModeEvent(
        type: GoosebumpsProtocol.eventType,
        data: {'v': 99, 'x': .5, 'y': .5},
      )),
      isNull,
    );
    expect(
      GoosebumpsProtocol.tryParse(const ModeEvent(
        type: GoosebumpsProtocol.eventType,
        data: {'v': 2, 'id': 'broken'},
      )),
      isNull,
    );
  });
}
