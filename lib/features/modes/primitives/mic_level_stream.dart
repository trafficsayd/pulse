import 'dart:async';

/// Normalized microphone level emitted by [MicLevelStream].
///
/// [level01] is **always** in `[0.0, 1.0]`. We deliberately do *not* leak
/// raw dB because every mode that listens (Whisper, Breath, Hum, Mill)
/// only cares about "loud / soft", not the absolute SPL, and clipping
/// inside the source means UI code never has to.
class MicLevel {
  const MicLevel({required this.level01, required this.timestamp});

  /// Linear amplitude in `[0.0, 1.0]`. 0.0 = silent, 1.0 = clipped.
  final double level01;
  final DateTime timestamp;
}

/// Owns the lifecycle of a microphone amplitude stream.
///
/// Why this exists as its own abstraction:
///   1. Multiple modes need the same data → DRY.
///   2. We swap the underlying recorder in tests (see [FakeMicLevelStream]).
///   3. Energy: when no mode is listening the recorder must be fully
///      stopped, not just paused — otherwise the mic icon stays lit in
///      the status bar and the user thinks the app is eavesdropping.
abstract class MicLevelStream {
  /// Broadcast stream of normalized levels. Cold — first listener starts
  /// the recorder, last unsubscribe stops it.
  Stream<MicLevel> get levels;

  /// Free any platform resources. After [dispose] the stream completes.
  Future<void> dispose();
}

/// Deterministic in-memory implementation used by widget / golden tests.
///
/// Tests push samples through [add] (synchronously) and assert that
/// downstream widgets react. Implements the same back-pressure contract
/// as the real stream: emits on demand, not on a wall clock.
class FakeMicLevelStream implements MicLevelStream {
  FakeMicLevelStream();

  final StreamController<MicLevel> _controller =
      StreamController<MicLevel>.broadcast(sync: true);

  @override
  Stream<MicLevel> get levels => _controller.stream;

  /// Pushes [level01] (clamped to `[0,1]`) to all listeners.
  void add(double level01, {DateTime? at}) {
    final clamped = level01.clamp(0.0, 1.0).toDouble();
    _controller
        .add(MicLevel(level01: clamped, timestamp: at ?? DateTime.now()));
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
