import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/ray_sketch_engine.dart';
import 'package:pulse/features/session/application/mode_event.dart';

void main() {
  const violet = 0xFF9747FF;

  RayPoint point(double x, double y, [int time = 0]) => RayPoint(
        x: x,
        y: y,
        pressure: 0.8,
        elapsedMs: time,
      );

  test('batched live stroke is repaired by the complete end event', () {
    final alice = RaySketchEngine(ownerId: 'alice', canvasColorValue: violet);
    final bob = RaySketchEngine(ownerId: 'bob', canvasColorValue: violet);

    final stroke = alice.beginLocalStroke(
      id: 'alice-1',
      colorValue: violet,
      width: 9,
      effect: RayBrushEffect.neon,
      point: point(0.1, 0.2),
    );
    expect(bob.apply(alice.beginEvent(stroke)).changed, isTrue);

    final batch = [point(0.2, 0.3, 12), point(0.3, 0.4, 24)];
    alice.appendLocalPoints(stroke.id, batch);
    // Simulate a transport failover that drops the live batch.
    final finished = alice.finishLocalStroke(stroke.id)!;
    expect(bob.apply(alice.endEvent(finished)).changed, isTrue);

    expect(bob.strokes, hasLength(1));
    expect(bob.strokes.single.points, hasLength(3));
    expect(bob.strokes.single.complete, isTrue);
  });

  test('two peers merge snapshots without overwriting each other', () {
    final alice = RaySketchEngine(ownerId: 'alice', canvasColorValue: violet);
    final bob = RaySketchEngine(ownerId: 'bob', canvasColorValue: violet);

    final a = alice.beginLocalStroke(
      id: 'a',
      colorValue: violet,
      width: 8,
      effect: RayBrushEffect.glow,
      point: point(0.1, 0.1),
    )..complete = true;
    final b = bob.beginLocalStroke(
      id: 'b',
      colorValue: 0xFF60A5FA,
      width: 12,
      effect: RayBrushEffect.watercolor,
      point: point(0.9, 0.9),
    )..complete = true;

    expect(a.ownerId, 'alice');
    expect(b.ownerId, 'bob');
    expect(alice.apply(bob.stateEvent()).changed, isTrue);
    expect(bob.apply(alice.stateEvent()).changed, isTrue);

    expect(alice.strokes.map((stroke) => stroke.id), containsAll(['a', 'b']));
    expect(bob.strokes.map((stroke) => stroke.id), containsAll(['a', 'b']));
  });

  test('undo tombstone prevents stale reconnect state resurrecting a stroke',
      () {
    final alice = RaySketchEngine(ownerId: 'alice', canvasColorValue: violet);
    final bob = RaySketchEngine(ownerId: 'bob', canvasColorValue: violet);
    final stroke = alice.beginLocalStroke(
      id: 'a',
      colorValue: violet,
      width: 8,
      effect: RayBrushEffect.clean,
      point: point(0.2, 0.2),
    )..complete = true;
    final stale = alice.stateEvent();
    bob.apply(stale);

    expect(alice.undoLastLocal(), same(stroke));
    bob.apply(alice.undoEvent(stroke.id));
    expect(bob.strokes, isEmpty);

    bob.apply(stale);
    expect(bob.strokes, isEmpty);
  });

  test('newer canvas operation wins after reconnect', () {
    final alice = RaySketchEngine(ownerId: 'alice', canvasColorValue: violet);
    final bob = RaySketchEngine(ownerId: 'bob', canvasColorValue: violet);

    bob.apply(alice.setCanvasColor(0xFF24113D));
    alice.apply(bob.setCanvasColor(0xFF101B35));
    bob.apply(alice.stateEvent());

    expect(alice.canvasColorValue, 0xFF101B35);
    expect(bob.canvasColorValue, 0xFF101B35);
  });

  test('state request replies with a bounded protocol-v2 snapshot', () {
    final alice = RaySketchEngine(ownerId: 'alice', canvasColorValue: violet);
    final bob = RaySketchEngine(ownerId: 'bob', canvasColorValue: violet);
    alice.beginLocalStroke(
      id: 'a',
      colorValue: violet,
      width: 9,
      effect: RayBrushEffect.sparkles,
      point: point(0.5, 0.5),
    );

    final result = alice.apply(bob.stateRequestEvent());
    expect(result.changed, isFalse);
    expect(result.reply?.type, 'ray_state');
    expect(result.reply?.data['v'], RaySketchEngine.protocolVersion);
  });

  test('malformed and self-authored events are ignored safely', () {
    final alice = RaySketchEngine(ownerId: 'alice', canvasColorValue: violet);
    expect(
      alice.apply(const ModeEvent(type: 'ray_stroke_begin')).changed,
      isFalse,
    );
    expect(
      alice
          .apply(const ModeEvent(type: 'ray_stroke_points', data: {
            'id': 'missing',
            'owner': 'bob',
            'points': <Object>[],
          }))
          .changed,
      isFalse,
    );
  });
}
