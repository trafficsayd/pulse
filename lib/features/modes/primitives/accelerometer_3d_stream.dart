import 'dart:async';
import 'dart:math' as math;

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
