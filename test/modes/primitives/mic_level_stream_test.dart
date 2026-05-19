import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/primitives/mic_level_stream.dart';

void main() {
  group('FakeMicLevelStream', () {
    test('emits samples clamped to [0, 1]', () async {
      final stream = FakeMicLevelStream();
      final received = <double>[];
      final sub = stream.levels.listen((m) => received.add(m.level01));

      stream.add(0.5);
      stream.add(-1.0);
      stream.add(2.0);
      stream.add(0.25);

      // sync controller delivers synchronously.
      expect(received, [0.5, 0.0, 1.0, 0.25]);
      await sub.cancel();
      await stream.dispose();
    });

    test('dispose closes the stream', () async {
      final stream = FakeMicLevelStream();
      final done = expectAsync0<void>(() {});
      stream.levels.listen(
        null,
        onDone: done,
      );
      await stream.dispose();
    });
  });
}
