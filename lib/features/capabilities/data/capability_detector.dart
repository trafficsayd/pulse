import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';

import '../domain/device_capability.dart';

/// Interface used by the Riverpod provider so tests can stub the platform
/// probes without spinning up `sensors_plus` etc. in a unit test.
abstract class CapabilityDetector {
  Future<DeviceCapabilities> probe();
}

/// Real-device capability probe.
///
/// Strict contract:
///   * Must NOT throw — every probe is wrapped in a try/catch so a single
///     platform exception cannot kill app boot. A failed probe simply
///     means "the capability is missing".
///   * Must NOT block longer than ~2s in total. Each individual probe has
///     its own timeout; a hung Bluetooth stack on a buggy ROM should
///     never freeze the splash screen.
///   * Must NOT request runtime permissions. Detection answers the
///     question "*could* this device run that mode if the user granted
///     permission?", not "*is it permitted right now?*". The latter is
///     re-checked at mode-start.
class RealCapabilityDetector implements CapabilityDetector {
  const RealCapabilityDetector();

  static const Duration _probeTimeout = Duration(milliseconds: 500);

  @override
  Future<DeviceCapabilities> probe() async {
    final found = <DeviceCapability>{};

    // Sensors — listen to a single accelerometer event with a tight timeout.
    // sensors_plus throws on platforms that have no sensor implementation
    // (e.g. some emulators), so this is wrapped.
    final hasAccel = await _safe(_probeAccelerometer);
    if (hasAccel) found.add(DeviceCapability.accelerometer);

    // Vibration: hasVibrator() returns null on platforms without a vibrator.
    final hasVib = await _safe(() async {
      final v = await Vibration.hasVibrator();
      return v == true;
    });
    if (hasVib) {
      found.add(DeviceCapability.vibration);
      final hasAmp = await _safe(() async {
        final a = await Vibration.hasAmplitudeControl();
        return a == true;
      });
      if (hasAmp) found.add(DeviceCapability.vibrationAmplitude);
    }

    // Microphone, camera, BLE, Wi-Fi, flashlight: at the *capability*
    // layer we only assert presence on platforms that universally
    // expose them. The transport layers (Track B/F) do a deeper probe
    // before they actually claim the resource.
    //
    // We make a deliberate, conservative assumption: on iOS and Android,
    // microphone+camera+BLE+flashlight are *physically present* (Apple
    // requires them; Android phones overwhelmingly have them). If a
    // specific device is missing one, the transport probe will catch
    // it and downgrade the mode at start-time.
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      found.addAll(const [
        DeviceCapability.microphone,
        DeviceCapability.camera,
        DeviceCapability.bluetoothLe,
        DeviceCapability.localNetwork,
        DeviceCapability.flashlight,
      ]);
    }

    return DeviceCapabilities(found);
  }

  Future<bool> _probeAccelerometer() async {
    final completer = Completer<bool>();
    late final StreamSubscription<AccelerometerEvent> sub;
    sub = accelerometerEventStream().listen(
      (_) {
        if (!completer.isCompleted) completer.complete(true);
        unawaited(sub.cancel());
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete(false);
        unawaited(sub.cancel());
      },
      cancelOnError: true,
    );
    final result = await completer.future.timeout(
      _probeTimeout,
      onTimeout: () {
        unawaited(sub.cancel());
        return false;
      },
    );
    return result;
  }

  Future<bool> _safe(Future<bool> Function() probe) async {
    try {
      return await probe().timeout(_probeTimeout, onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }
}

/// Always-empty detector. Useful in widget tests where you want every mode
/// to render in its "locked / unavailable" state without pulling in any
/// platform channels.
class NullCapabilityDetector implements CapabilityDetector {
  const NullCapabilityDetector();

  @override
  Future<DeviceCapabilities> probe() async => const DeviceCapabilities.none();
}

/// Deterministic detector for unit tests — declare exactly which
/// capabilities the simulated device has.
class FakeCapabilityDetector implements CapabilityDetector {
  const FakeCapabilityDetector(this.capabilities);

  final Set<DeviceCapability> capabilities;

  @override
  Future<DeviceCapabilities> probe() async => DeviceCapabilities(capabilities);
}
