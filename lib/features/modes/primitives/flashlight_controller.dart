import 'dart:async';

/// Backend interface for driving the device flashlight / torch.
///
/// Production Flutter currently exposes the torch only through the
/// `camera` package (`CameraController.setFlashMode(FlashMode.torch)`).
/// Adding `camera` is out of scope for Track C — see
/// `TODO(track-d)` in [FlashlightController.defaultBackend]. The default
/// backend here is a graceful no-op so other primitives can land first
/// and modes that *don't* require a torch still compile.
abstract class FlashlightBackend {
  const FlashlightBackend();

  Future<bool> isAvailable();

  Future<void> turnOn();

  Future<void> turnOff();
}

/// No-op backend used until the `camera` package is wired in. Always
/// reports unavailable so capability detection greys out modes that need
/// the torch (Морзянка / Сверчок / Thunder).
class _NoopFlashlightBackend extends FlashlightBackend {
  const _NoopFlashlightBackend();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<void> turnOn() async {}

  @override
  Future<void> turnOff() async {}
}

/// High-level controller for the device torch.
///
/// Holds zero state when the backend reports unavailable — every method
/// short-circuits. `pulse` is cancel-safe: starting a new pulse train
/// while an old one is in flight cancels the in-flight train so we never
/// leak overlapping torch-on/torch-off timers.
class FlashlightController {
  FlashlightController({FlashlightBackend? backend})
      : _backend = backend ?? defaultBackend;

  // TODO(track-d): swap [defaultBackend] for a camera-package-driven
  // implementation when modes that need the torch (Морзянка / Сверчок)
  // start landing. Until then we keep the no-op so tests and analyze
  // pass without pulling in a heavy dependency.
  static const FlashlightBackend defaultBackend = _NoopFlashlightBackend();

  final FlashlightBackend _backend;
  Completer<void>? _pulseGuard;

  Future<bool> isAvailable() => _backend.isAvailable();

  Future<void> on() async {
    if (!await _backend.isAvailable()) {
      return;
    }
    await _cancelInFlight();
    await _backend.turnOn();
  }

  Future<void> off() async {
    if (!await _backend.isAvailable()) {
      return;
    }
    await _cancelInFlight();
    await _backend.turnOff();
  }

  /// Pulse the torch [count] times: turn on for [onDuration], off for
  /// [offDuration]. Returns once the train finishes (or is cancelled by
  /// another call). No-ops if the device has no torch.
  Future<void> pulse(
    Duration onDuration,
    Duration offDuration,
    int count,
  ) async {
    if (count <= 0) return;
    if (!await _backend.isAvailable()) return;
    await _cancelInFlight();
    final guard = Completer<void>();
    _pulseGuard = guard;
    try {
      for (var i = 0; i < count; i++) {
        if (guard.isCompleted) return;
        await _backend.turnOn();
        await Future<void>.delayed(onDuration);
        if (guard.isCompleted) {
          await _backend.turnOff();
          return;
        }
        await _backend.turnOff();
        if (i != count - 1) {
          await Future<void>.delayed(offDuration);
        }
      }
    } finally {
      if (!guard.isCompleted) guard.complete();
      if (identical(_pulseGuard, guard)) _pulseGuard = null;
    }
  }

  Future<void> _cancelInFlight() async {
    final inFlight = _pulseGuard;
    if (inFlight != null && !inFlight.isCompleted) {
      inFlight.complete();
      _pulseGuard = null;
    }
  }
}
