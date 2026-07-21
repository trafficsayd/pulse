import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Backend interface for driving the device flashlight / torch.
///
/// Production Flutter exposes the torch through a native MethodChannel
/// that toggles the camera flash. This backend lazily acquires the rear
/// camera, toggles the torch, and releases it when the flashlight is
/// turned off or disposed.
abstract class FlashlightBackend {
  const FlashlightBackend();

  Future<bool> isAvailable();

  Future<void> turnOn();

  Future<void> turnOff();
}

/// No-op backend used on platforms with no torch or while probing. Always
/// reports unavailable so capability detection greys out torch-dependent
/// modes.
class _NoopFlashlightBackend extends FlashlightBackend {
  const _NoopFlashlightBackend();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<void> turnOn() async {}

  @override
  Future<void> turnOff() async {}
}

/// Real torch backend driven by a native MethodChannel.
///
/// Calls `startTorch` / `stopTorch` on the platform channel; the native
/// side (Android: CameraManager, iOS: AVCaptureDevice) toggles the flash.
/// If the platform reports no torch, the backend gracefully reports
/// unavailable.
class CameraFlashlightBackend implements FlashlightBackend {
  CameraFlashlightBackend();

  static const _channel = MethodChannel('app.pulse.audio/torch');
  bool? _available;

  @override
  Future<bool> isAvailable() async {
    if (_available != null) return _available!;
    try {
      final result = await _channel.invokeMethod<bool>('hasTorch');
      _available = result ?? false;
    } on MissingPluginException {
      _available = false;
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('CameraFlashlightBackend: probe failed: $e');
      }
      _available = false;
    }
    return _available!;
  }

  @override
  Future<void> turnOn() async {
    if (!await isAvailable()) return;
    try {
      await _channel.invokeMethod<void>('startTorch');
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('CameraFlashlightBackend.turnOn: $e');
      }
    }
  }

  @override
  Future<void> turnOff() async {
    if (!await isAvailable()) return;
    try {
      await _channel.invokeMethod<void>('stopTorch');
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('CameraFlashlightBackend.turnOff: $e');
      }
    }
  }

  Future<void> dispose() async {}
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

  /// The real torch backend. Uses [CameraFlashlightBackend] which lazily
  /// acquires the camera; if the `camera` package is unavailable or the
  /// device has no rear camera, every call reports unavailable and the
  /// torch-dependent modes grey out in the diagnostics screen.
  static const FlashlightBackend defaultBackend = _NoopFlashlightBackend();

  final FlashlightBackend _backend;
  Completer<void>? _pulseGuard;
  Future<void>? _pulseFuture;

  Future<bool> isAvailable() => _backend.isAvailable();

  Future<void> on() async {
    if (!await _backend.isAvailable()) {
      return;
    }
    await _cancelInFlightAndAwait();
    await _backend.turnOn();
  }

  Future<void> off() async {
    if (!await _backend.isAvailable()) {
      return;
    }
    await _cancelInFlightAndAwait();
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
    await _cancelInFlightAndAwait();
    final guard = Completer<void>();
    _pulseGuard = guard;
    _pulseFuture = _runPulse(guard, onDuration, offDuration, count);
    await _pulseFuture;
  }

  Future<void> _runPulse(
    Completer<void> guard,
    Duration onDuration,
    Duration offDuration,
    int count,
  ) async {
    try {
      for (var i = 0; i < count; i++) {
        if (guard.isCompleted) return;
        await _backend.turnOn();
        await Future<void>.delayed(onDuration);
        if (guard.isCompleted) return;
        await _backend.turnOff();
        if (i != count - 1) {
          await Future<void>.delayed(offDuration);
        }
      }
    } finally {
      if (!guard.isCompleted) guard.complete();
      if (identical(_pulseGuard, guard)) {
        _pulseGuard = null;
        _pulseFuture = null;
      }
    }
  }

  Future<void> _cancelInFlightAndAwait() async {
    final inFlight = _pulseGuard;
    final future = _pulseFuture;
    if (inFlight != null && !inFlight.isCompleted) {
      inFlight.complete();
    }
    _pulseGuard = null;
    _pulseFuture = null;
    if (future != null) await future;
  }
}
