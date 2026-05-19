import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/capabilities/domain/device_capability.dart';

void main() {
  group('DeviceCapabilities', () {
    test('reports has() for present capabilities', () {
      const caps = DeviceCapabilities({
        DeviceCapability.microphone,
        DeviceCapability.vibration,
      });
      expect(caps.has(DeviceCapability.microphone), isTrue);
      expect(caps.has(DeviceCapability.flashlight), isFalse);
    });

    test('hasAll() returns true only when every required cap is present', () {
      const caps = DeviceCapabilities({
        DeviceCapability.microphone,
        DeviceCapability.vibration,
      });
      expect(
        caps.hasAll({DeviceCapability.microphone}),
        isTrue,
      );
      expect(
        caps.hasAll({
          DeviceCapability.microphone,
          DeviceCapability.vibration,
        }),
        isTrue,
      );
      expect(
        caps.hasAll({DeviceCapability.microphone, DeviceCapability.flashlight}),
        isFalse,
      );
    });

    test('missing() reports only the absent caps', () {
      const caps = DeviceCapabilities({DeviceCapability.microphone});
      final missing = caps.missing({
        DeviceCapability.microphone,
        DeviceCapability.vibration,
        DeviceCapability.flashlight,
      });
      expect(missing, {
        DeviceCapability.vibration,
        DeviceCapability.flashlight,
      });
    });

    test('none() exposes empty set and reports everything missing', () {
      const caps = DeviceCapabilities.none();
      for (final c in DeviceCapability.values) {
        expect(caps.has(c), isFalse);
      }
      expect(
        caps.missing(DeviceCapability.values).length,
        DeviceCapability.values.length,
      );
    });

    test('all is unmodifiable', () {
      const caps = DeviceCapabilities({DeviceCapability.microphone});
      expect(() => caps.all.add(DeviceCapability.flashlight),
          throwsA(isA<UnsupportedError>()));
    });
  });
}
