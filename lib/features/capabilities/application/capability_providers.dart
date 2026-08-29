import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/capability_detector.dart';
import '../domain/device_capability.dart';

/// The chosen [CapabilityDetector] implementation. Defaults to the real
/// probe; tests / golden tests override with a [FakeCapabilityDetector]
/// or [NullCapabilityDetector].
final capabilityDetectorProvider = Provider<CapabilityDetector>((ref) {
  return const RealCapabilityDetector();
});

/// One-shot probe of the device. Cached for the lifetime of the app.
///
/// Consumers should watch the [AsyncValue]:
///   * `loading` — splash / placeholder.
///   * `data(DeviceCapabilities)` — render carousel, mark missing modes.
///   * `error` — degrade to [DeviceCapabilities.none()] (i.e. assume
///      nothing). We deliberately do NOT keep retrying — a probe error
///      means the device's platform channel is broken, not that the
///      hardware "might turn up later".
final deviceCapabilitiesProvider = FutureProvider<DeviceCapabilities>((
  ref,
) async {
  const qaForceCapabilities = bool.fromEnvironment(
    'PULSE_QA_FORCE_CAPABILITIES',
  );
  // Desktop Android emulators do not expose a real vibrator, torch, or
  // microphone input. This debug-only override lets the complete mode UI and
  // network protocol be exercised there; release builds always use the real
  // detector below.
  if (kDebugMode && qaForceCapabilities) {
    return DeviceCapabilities(DeviceCapability.values.toSet());
  }
  final detector = ref.watch(capabilityDetectorProvider);
  return detector.probe();
});
