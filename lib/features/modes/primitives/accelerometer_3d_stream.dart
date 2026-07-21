import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Smoothed three-axis accelerometer sample emitted by
/// [Accelerometer3DStream]. Values are in m/s² (matching `sensors_plus`).
class Accel3 {
  const Accel3(this.x, this.y, this.z, {required this.timestamp});

  final double x;
  final double y;
  final double z;
  final DateTime timestamp;

  /// Magnitude excluding the bias of gravity (≈9.81 m/s²). Useful for
  /// "shake" detection without false positives when the phone is sitting
  /// still on a table.
  double get netMagnitude {
    const gravity = 9.81;
    final totalMag = math.sqrt(x * x + y * y + z * z);
    return (totalMag - gravity).abs();
  }
}

/// Generic 3-axis stream. The real implementation wraps `sensors_plus`;
/// tests use [FakeAccelerometer3DStream] so the test runner never has to
/// open a platform channel.
abstract class Accelerometer3DStream {
  Stream<Accel3> get events;
  Future<void> dispose();
}

/// Real accelerometer stream backed by `package:sensors_plus`.
///
/// Emits smoothed samples at the sensor's native rate. A lightweight
/// low-pass filter removes high-frequency noise so the "intensity bar"
/// in Bell mode doesn't jitter.
class RealAccelerometer3DStream implements Accelerometer3DStream {
  RealAccelerometer3DStream();

  StreamController<Accel3>? _controller;
  StreamSubscription<AccelerometerEvent>? _sub;
  bool _started = false;

  // Low-pass filter state.
  double _filtX = 0;
  double _filtY = 0;
  double _filtZ = 0;
  static const double _alpha = 0.8; // smoothing factor

  @override
  Stream<Accel3> get events {
    _controller ??= StreamController<Accel3>.broadcast(
      onListen: _start,
      onCancel: _stopIfNoListeners,
    );
    return _controller!.stream;
  }

  void _start() {
    if (_started) return;
    _started = true;
    try {
      _sub = accelerometerEventStream(
        samplingPeriod: SensorInterval.uiInterval,
      ).listen(_onSample);
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('RealAccelerometer3DStream: failed to start: $e');
      }
      _controller?.addError(e);
      _started = false;
    }
  }

  void _onSample(AccelerometerEvent event) {
    // Low-pass filter to smooth out sensor noise.
    _filtX = _alpha * _filtX + (1 - _alpha) * event.x;
    _filtY = _alpha * _filtY + (1 - _alpha) * event.y;
    _filtZ = _alpha * _filtZ + (1 - _alpha) * event.z;
    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      controller.add(
        Accel3(_filtX, _filtY, _filtZ, timestamp: DateTime.now()),
      );
    }
  }

  void _stopIfNoListeners() {
    final controller = _controller;
    if (controller != null && controller.hasListener) return;
    _stop();
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }

  @override
  Future<void> dispose() async {
    await _stop();
    await _controller?.close();
    _controller = null;
  }
}

class FakeAccelerometer3DStream implements Accelerometer3DStream {
  FakeAccelerometer3DStream();

  final StreamController<Accel3> _controller =
      StreamController<Accel3>.broadcast(sync: true);

  @override
  Stream<Accel3> get events => _controller.stream;

  void push(double x, double y, double z, {DateTime? at}) {
    _controller.add(Accel3(x, y, z, timestamp: at ?? DateTime.now()));
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
