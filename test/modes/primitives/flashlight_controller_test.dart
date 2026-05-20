import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/primitives/flashlight_controller.dart';

void main() {
  group('FlashlightController', () {
    test('defaultBackend reports unavailable so callers can grey out modes',
        () async {
      final controller = FlashlightController();
      expect(await controller.isAvailable(), isFalse);
    });

    test('on/off are no-ops when the backend is unavailable', () async {
      final controller = FlashlightController();
      await controller.on();
      await controller.off();
      // Surviving without exception is the contract here.
    });

    test('pulse drives the backend the requested number of times', () async {
      final backend = _RecordingBackend(available: true);
      final controller = FlashlightController(backend: backend);
      await controller.pulse(
        const Duration(milliseconds: 1),
        const Duration(milliseconds: 1),
        3,
      );
      expect(backend.onCalls, 3);
      expect(backend.offCalls, 3);
      expect(backend.transcript.first, 'on');
      expect(backend.transcript.last, 'off');
    });

    test('pulse short-circuits when count <= 0', () async {
      final backend = _RecordingBackend(available: true);
      final controller = FlashlightController(backend: backend);
      await controller.pulse(
        const Duration(milliseconds: 1),
        const Duration(milliseconds: 1),
        0,
      );
      expect(backend.onCalls, 0);
      expect(backend.offCalls, 0);
    });

    test('pulse short-circuits when the device has no torch', () async {
      final backend = _RecordingBackend(available: false);
      final controller = FlashlightController(backend: backend);
      await controller.pulse(
        const Duration(milliseconds: 1),
        const Duration(milliseconds: 1),
        5,
      );
      expect(backend.onCalls, 0);
      expect(backend.offCalls, 0);
    });
  });
}

/// Records each on/off call on a fake torch so the test can assert the
/// exact sequence the controller drives.
class _RecordingBackend extends FlashlightBackend {
  _RecordingBackend({required this.available});

  final bool available;
  int onCalls = 0;
  int offCalls = 0;
  final List<String> transcript = <String>[];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> turnOn() async {
    onCalls += 1;
    transcript.add('on');
  }

  @override
  Future<void> turnOff() async {
    offCalls += 1;
    transcript.add('off');
  }
}
