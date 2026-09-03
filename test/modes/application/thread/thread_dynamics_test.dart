import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/thread/thread_dynamics.dart';

void main() {
  test('protocol clamps coordinates and remains readable by version one', () {
    final encoded = ThreadProtocol.gesture(
      epoch: 4,
      sequence: 8,
      sentAtUs: 20,
      phase: 'move',
      point: const ThreadPoint(-1, 2),
      velocity: const ThreadPoint(10, -10),
      tension: 5,
    );
    final decoded = ThreadProtocol.parse(encoded)!;

    expect(decoded.version, 2);
    expect(decoded.point.x, 0);
    expect(decoded.point.y, 1);
    expect(decoded.velocity.x, 4);
    expect(decoded.tension, 1);
    expect(
      ThreadProtocol.parse(<String, dynamic>{'x': .2, 'y': .8})!.version,
      1,
    );
  });

  test('versioned gestures are idempotent', () {
    final packet = ThreadProtocol.parse(ThreadProtocol.gesture(
      epoch: 4,
      sequence: 1,
      sentAtUs: 20,
      phase: 'begin',
      point: ThreadPoint.center,
    ))!;
    final deduplicator = ThreadPacketDeduplicator();

    expect(deduplicator.accept(packet), isTrue);
    expect(deduplicator.accept(packet), isFalse);
  });

  test('lower sequence and late sent timestamp cannot rewind the thread', () {
    final deduplicator = ThreadPacketDeduplicator();
    final newer = ThreadProtocol.parse(ThreadProtocol.gesture(
      epoch: 7,
      sequence: 9,
      sentAtUs: 900,
      phase: 'release',
      point: const ThreadPoint(.8, .5),
    ))!;
    final older = ThreadProtocol.parse(ThreadProtocol.gesture(
      epoch: 7,
      sequence: 8,
      sentAtUs: 800,
      phase: 'move',
      point: const ThreadPoint(.2, .5),
    ))!;
    expect(deduplicator.accept(newer), isTrue);
    expect(deduplicator.accept(older), isFalse);

    final buffer = ThreadRemoteReconciler(interpolationDelay: Duration.zero);
    expect(
      buffer.push(const ThreadRemoteSample(
        point: ThreadPoint(.8, .5),
        velocity: ThreadPoint(0, 0),
        sentAtUs: 900,
        receivedAtUs: 1100,
      )),
      isTrue,
    );
    expect(
      buffer.push(const ThreadRemoteSample(
        point: ThreadPoint(.2, .5),
        velocity: ThreadPoint(0, 0),
        sentAtUs: 800,
        receivedAtUs: 1300,
      )),
      isFalse,
    );
    expect(buffer.positionAt(1500)!.x, closeTo(.8, .001));
  });

  test('remote position interpolates delayed samples and limits prediction',
      () {
    final reconciler = ThreadRemoteReconciler(
      interpolationDelay: const Duration(milliseconds: 100),
      maximumPrediction: const Duration(milliseconds: 150),
    );
    reconciler.push(const ThreadRemoteSample(
      point: ThreadPoint(.2, .3),
      velocity: ThreadPoint(1, 0),
      sentAtUs: 0,
      receivedAtUs: 1_000_000,
    ));
    reconciler.push(const ThreadRemoteSample(
      point: ThreadPoint(.6, .3),
      velocity: ThreadPoint(1, 0),
      sentAtUs: 200_000,
      receivedAtUs: 1_200_000,
    ));

    expect(reconciler.positionAt(1_200_000)!.x, closeTo(.4, .001));
    expect(reconciler.positionAt(2_000_000)!.x, closeTo(.75, .001));
    expect(reconciler.isStaleAt(5_000_001), isTrue);
  });

  test('pulling increases tension and release creates a damped wave', () {
    final physics = ThreadPhysics();
    ThreadPhysicsFrame frame = const ThreadPhysicsFrame(
      tension: 0,
      sag: 0,
      releaseWave: 0,
      shimmerSpeed: 0,
    );
    for (var i = 0; i < 20; i++) {
      frame = physics.update(
        local: const ThreadPoint(.05, .8),
        partner: const ThreadPoint(.95, .2),
        localVelocity: const ThreadPoint(.4, 0),
        deltaSeconds: 1 / 60,
      );
    }
    final looseSag = frame.sag;
    expect(frame.tension, greaterThan(.65));

    physics.release();
    frame = physics.update(
      local: const ThreadPoint(.05, .8),
      partner: const ThreadPoint(.95, .2),
      localVelocity: const ThreadPoint(0, 0),
      deltaSeconds: 1 / 60,
    );
    expect(frame.releaseWave.abs(), greaterThan(0));
    expect(frame.sag, isNot(looseSag));
  });
}
