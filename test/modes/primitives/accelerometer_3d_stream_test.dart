import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/primitives/accelerometer_3d_stream.dart';

void main() {
  group('Accel3', () {
    test('netMagnitude subtracts gravity from the euclidean norm', () {
      final sample = Accel3(0, 0, 9.81, timestamp: DateTime.utc(2024));
      expect(sample.netMagnitude, closeTo(0, 1e-6));
    });

    test('netMagnitude reports magnitude regardless of sign', () {
      // A shake of (3, 4, 0) has norm 5 → 5 - 9.81 = ‑4.81 → |‑4.81|.
      final sample = Accel3(3, 4, 0, timestamp: DateTime.utc(2024));
      final expected = (math.sqrt(9 + 16) - 9.81).abs();
      expect(
        sample.netMagnitude,
        closeTo(expected, 1e-6),
        reason: 'Implementation takes the absolute value so the signal '
            'reads as energy in either direction.',
      );
    });
  });

  group('FakeAccelerometer3DStream', () {
    test('pushes events through the broadcast stream', () async {
      final stream = FakeAccelerometer3DStream();
      addTearDown(stream.dispose);
      final samples = <Accel3>[];
      final sub = stream.events.listen(samples.add);
      addTearDown(sub.cancel);
      stream.push(0, 0, 9.81);
      stream.push(0.1, 0.0, 9.81);
      await Future<void>.delayed(Duration.zero);
      expect(samples, hasLength(2));
      expect(samples.last.x, closeTo(0.1, 1e-9));
    });

    test('supports multiple concurrent listeners', () async {
      final stream = FakeAccelerometer3DStream();
      addTearDown(stream.dispose);
      var a = 0, b = 0;
      final subA = stream.events.listen((_) => a++);
      final subB = stream.events.listen((_) => b++);
      addTearDown(() async {
        await subA.cancel();
        await subB.cancel();
      });
      stream.push(0, 0, 9.81);
      await Future<void>.delayed(Duration.zero);
      expect(a, 1);
      expect(b, 1);
    });

    test('dispose closes the underlying controller', () async {
      final stream = FakeAccelerometer3DStream();
      var done = false;
      stream.events.listen((_) {}, onDone: () => done = true);
      await stream.dispose();
      expect(done, isTrue);
    });
  });
}
