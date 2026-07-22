import 'dart:async';
import 'dart:math' as math;

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

/// Production implementation backed by `package:sensors_plus`.
///
/// Implements the same cold-stream contract as
/// [FakeAccelerometer3DStream]: the platform sensor subscription only
/// opens when the first listener subscribes to [events] and is
/// cancelled when the last listener unsubscribes, so no mode leaves a
/// sensor channel running in the background once it's no longer on
/// screen.
class RealAccelerometer3DStream implements Accelerometer3DStream {
  RealAccelerometer3DStream();

  StreamController<Accel3>? _controller;
  StreamSubscription<AccelerometerEvent>? _sensorSub;

  @override
  Stream<Accel3> get events {
    _controller ??= StreamController<Accel3>.broadcast(
      onListen: _startListening,
      onCancel: _stopListening,
    );
    return _controller!.stream;
  }

  void _startListening() {
    _sensorSub = accelerometerEventStream().listen(_onEvent);
  }

  void _onEvent(AccelerometerEvent event) {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;
    controller.add(
      Accel3(event.x, event.y, event.z, timestamp: DateTime.now()),
    );
  }

  Future<void> _stopListening() async {
    await _sensorSub?.cancel();
    _sensorSub = null;
  }

  @override
  Future<void> dispose() async {
    await _stopListening();
    await _controller?.close();
  }
}
