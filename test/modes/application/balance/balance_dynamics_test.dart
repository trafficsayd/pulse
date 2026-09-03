import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/balance/balance_dynamics.dart';

void main() {
  test('sensor normalizer calibrates rest and smooths a real tilt', () {
    final normalizer = BalanceSensorNormalizer(calibrationSamples: 3);
    expect(normalizer.add(1, -2).magnitude, 0);
    expect(normalizer.add(1, -2).magnitude, 0);
    expect(normalizer.add(1, -2).magnitude, 0);

    final tilt = normalizer.add(6.2, -2);
    expect(normalizer.calibrated, isTrue);
    expect(tilt.x, greaterThan(.2));
    expect(tilt.y.abs(), lessThan(.01));
  });

  test('opposing phone tilts balance while matching tilts move the mass', () {
    final balanced = CooperativeBalancePhysics();
    final moving = CooperativeBalancePhysics();
    CooperativeBalanceFrame? balancedFrame;
    CooperativeBalanceFrame? movingFrame;
    for (var i = 0; i < 90; i++) {
      balancedFrame = balanced.step(
        localIntent: const BalanceVector(.8, 0),
        partnerIntent: const BalanceVector(-.8, 0),
        partnerWeight: 1,
        deltaSeconds: 1 / 60,
      );
      movingFrame = moving.step(
        localIntent: const BalanceVector(.8, 0),
        partnerIntent: const BalanceVector(.8, 0),
        partnerWeight: 1,
        deltaSeconds: 1 / 60,
      );
    }

    expect(balancedFrame!.position.magnitude, lessThan(.02));
    expect(movingFrame!.position.x, greaterThan(.5));
    expect(movingFrame.position.magnitude, lessThanOrEqualTo(1));
  });

  test('reconciliation is gradual and never teleports', () {
    final physics = CooperativeBalancePhysics();
    physics.reconcile(
      remotePosition: const BalanceVector(1, 0),
      remoteVelocity: BalanceVector.zero,
      confidence: 1,
    );

    expect(physics.position.x, greaterThan(0));
    expect(physics.position.x, lessThan(.05));
  });

  test('stale remote intent safely decays to zero', () {
    final remote = BalanceRemoteReconciler();
    remote.push(const BalanceRemoteSample(
      intent: BalanceVector(1, 0),
      position: BalanceVector(.2, 0),
      velocity: BalanceVector(.1, 0),
      sentAtUs: 900_000,
      receivedAtUs: 1_000_000,
    ));

    expect(remote.resolveAt(1_100_000).weight, 1);
    expect(remote.resolveAt(3_100_001).weight, 0);
    expect(remote.resolveAt(3_100_001).intent.magnitude, 0);
  });

  test('protocol reads legacy coordinates and deduplicates v2 state', () {
    final legacy = BalanceProtocol.parse(<String, dynamic>{'x': 1, 'y': .5})!;
    expect(legacy.version, 1);
    expect(legacy.position.x, 1);

    final packet = BalanceProtocol.parse(BalanceProtocol.state(
      epoch: 8,
      sequence: 2,
      sentAtUs: 100,
      intent: const BalanceVector(.4, -.2),
      position: const BalanceVector(.1, .2),
      velocity: BalanceVector.zero,
      source: 'sensor',
    ))!;
    final deduplicator = BalancePacketDeduplicator();
    expect(deduplicator.accept(packet), isTrue);
    expect(deduplicator.accept(packet), isFalse);
  });

  test('lower sequence and older sent state cannot rewind balance', () {
    BalancePacket packet(int sequence, int sentAt, double x) =>
        BalanceProtocol.parse(BalanceProtocol.state(
          epoch: 3,
          sequence: sequence,
          sentAtUs: sentAt,
          intent: BalanceVector(x, 0),
          position: BalanceVector(x, 0),
          velocity: BalanceVector.zero,
          source: 'sensor',
        ))!;
    final deduplicator = BalancePacketDeduplicator();
    expect(deduplicator.accept(packet(5, 500, .7)), isTrue);
    expect(deduplicator.accept(packet(4, 400, -.7)), isFalse);

    final buffer = BalanceRemoteReconciler();
    expect(
      buffer.push(const BalanceRemoteSample(
        intent: BalanceVector(.7, 0),
        position: BalanceVector(.7, 0),
        velocity: BalanceVector.zero,
        sentAtUs: 500,
        receivedAtUs: 700,
      )),
      isTrue,
    );
    expect(
      buffer.push(const BalanceRemoteSample(
        intent: BalanceVector(-.7, 0),
        position: BalanceVector(-.7, 0),
        velocity: BalanceVector.zero,
        sentAtUs: 400,
        receivedAtUs: 900,
      )),
      isFalse,
    );
    expect(buffer.resolveAt(800).position.x, closeTo(.7, .001));
  });
}
