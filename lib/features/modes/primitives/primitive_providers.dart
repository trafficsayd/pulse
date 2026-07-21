import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'accelerometer_3d_stream.dart';
import 'flashlight_controller.dart';
import 'haptic_pattern_player.dart';
import 'mic_level_stream.dart';

/// True when running on a desktop platform (Windows/macOS/Linux).
final _isDesktop = kIsWeb
    ? false
    : (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

/// Probes and caches a [HapticEngine] for the current device.
///
/// In release / profile mode this is a [RealHapticEngine] backed by
/// `package:vibration`. In unit tests the caller overrides this provider
/// with a [RecordingHapticEngine] or [NullHapticEngine] via
/// `ProviderScope(overrides: [...])`. Desktop platforms get a
/// [NullHapticEngine] since `vibration` has no desktop backend.
final hapticEngineProvider = Provider<HapticEngine>((ref) {
  if (kDebugMode && kIsWeb) {
    return const NullHapticEngine();
  }
  if (_isDesktop) {
    return const NullHapticEngine();
  }
  return RealHapticEngine();
});

/// Lazily-constructed [MicLevelStream].
///
/// Returns a [RealMicLevelStream] on mobile; tests override with
/// a [FakeMicLevelStream]. Desktop gets [FakeMicLevelStream] since
/// `record` has no desktop backend. The stream is cold — the recorder
/// only starts when a mode subscribes, and stops when the last
/// listener unsubscribes.
final micLevelStreamProvider = Provider<MicLevelStream>((ref) {
  if (kIsWeb || _isDesktop) {
    return FakeMicLevelStream();
  }
  final stream = RealMicLevelStream();
  ref.onDispose(stream.dispose);
  return stream;
});

/// Lazily-constructed [Accelerometer3DStream].
///
/// Returns a [RealAccelerometer3DStream] on mobile; tests override
/// with a [FakeAccelerometer3DStream]. Desktop gets the fake since
/// `sensors_plus` has no desktop backend. The stream is cold — the sensor
/// subscription only starts when a mode subscribes.
final accelerometerStreamProvider = Provider<Accelerometer3DStream>((ref) {
  if (kIsWeb || _isDesktop) {
    return FakeAccelerometer3DStream();
  }
  final stream = RealAccelerometer3DStream();
  ref.onDispose(stream.dispose);
  return stream;
});

/// A single shared [FlashlightController].
///
/// Uses the real [CameraFlashlightBackend] on physical mobile devices; tests
/// override with a no-op backend. Desktop gets a no-op since `camera` has no
/// desktop torch backend. The controller is stateless across modes so sharing
/// one instance avoids re-acquiring the camera.
final flashlightControllerProvider = Provider<FlashlightController>((ref) {
  if (kIsWeb || _isDesktop) {
    return FlashlightController();
  }
  final backend = CameraFlashlightBackend();
  final controller = FlashlightController(backend: backend);
  ref.onDispose(backend.dispose);
  return controller;
});
