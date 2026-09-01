import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/half_heart/heart_presence_controller.dart';
import 'package:pulse/features/modes/application/half_heart/heart_presence_models.dart';

void main() {
  late int id;
  late HeartPresenceController controller;

  setUp(() {
    id = 0;
    controller = HeartPresenceController(idFactory: () => 'id-${id++}');
  });

  HeartHoldSignal remote({
    required String eventId,
    required String holdId,
    required int sequence,
    required int sentAt,
    bool held = true,
  }) =>
      HeartHoldSignal(
        eventId: eventId,
        holdId: holdId,
        sequence: sequence,
        sentAtMs: sentAt,
        held: held,
        strength: .6,
        x: .5,
        y: .5,
      );

  test('becomes one heart only after mutual continuous holding', () {
    controller.beginLocal(nowMs: 1000);
    expect(controller.snapshot(1000).phase, HeartPresencePhase.localSeeking);

    expect(
      controller.receive(
        remote(
          eventId: 'remote-0',
          holdId: 'remote-hold',
          sequence: 0,
          sentAt: 1020,
        ),
        receivedAtMs: 1020,
      ),
      isTrue,
    );
    expect(controller.snapshot(1020).phase, HeartPresencePhase.approaching);
    expect(controller.snapshot(1540).phase, HeartPresencePhase.united);
    expect(controller.snapshot(1540).unity, 1);
  });

  test('expires remote presence without a heartbeat', () {
    controller.beginLocal(nowMs: 1000);
    controller.receive(
      remote(
        eventId: 'remote-0',
        holdId: 'remote-hold',
        sequence: 0,
        sentAt: 1000,
      ),
      receivedAtMs: 1000,
    );
    controller.snapshot(1000);

    final expired = controller.snapshot(2501);
    expect(expired.partnerHeld, isFalse);
    expect(expired.phase, HeartPresencePhase.fading);
  });

  test('ignores duplicate and out-of-order remote samples', () {
    final newest = remote(
      eventId: 'new',
      holdId: 'remote-hold',
      sequence: 4,
      sentAt: 1400,
    );
    expect(controller.receive(newest, receivedAtMs: 1400), isTrue);
    expect(controller.receive(newest, receivedAtMs: 1400), isFalse);
    expect(
      controller.receive(
        remote(
          eventId: 'old',
          holdId: 'remote-hold',
          sequence: 3,
          sentAt: 1300,
        ),
        receivedAtMs: 1410,
      ),
      isFalse,
    );
    expect(controller.partnerHeld, isTrue);
  });

  test('a delayed release cannot end a newer hold', () {
    controller.receive(
      remote(
        eventId: 'first',
        holdId: 'old-hold',
        sequence: 0,
        sentAt: 1000,
      ),
      receivedAtMs: 1000,
    );
    controller.receive(
      remote(
        eventId: 'second',
        holdId: 'new-hold',
        sequence: 0,
        sentAt: 1100,
      ),
      receivedAtMs: 1100,
    );

    final accepted = controller.receive(
      remote(
        eventId: 'late-end',
        holdId: 'old-hold',
        sequence: 1,
        sentAt: 1050,
        held: false,
      ),
      receivedAtMs: 1150,
    );
    expect(accepted, isFalse);
    expect(controller.partnerHeld, isTrue);
  });
}
