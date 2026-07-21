import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Normalized microphone level emitted by [MicLevelStream].
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

/// Real microphone level stream backed by a native MethodChannel.
///
/// Opens a 22 kHz mono PCM stream via the platform channel and computes
/// the RMS amplitude of each chunk, normalised to `[0, 1]`. The broadcast
/// is cold: the recorder starts on first subscription and stops when the
/// last listener goes away, so the mic is only active while a mode is
/// on-screen.
class RealMicLevelStream implements MicLevelStream {
  RealMicLevelStream();

  static const _channel = MethodChannel('app.pulse.audio/mic');
  static const _eventChannel = EventChannel('app.pulse.audio/micStream');
  StreamController<MicLevel>? _controller;
  StreamSubscription<dynamic>? _audioSub;
  bool _started = false;

  @override
  Stream<MicLevel> get levels {
    _controller ??= StreamController<MicLevel>.broadcast(
      onListen: _start,
      onCancel: _stopIfNoListeners,
    );
    return _controller!.stream;
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    try {
      // Start the native audio recorder; it streams Uint8List PCM chunks.
      _audioSub = _eventChannel.receiveBroadcastStream().listen(
        _onAudioData,
        onError: (Object e) {
          if (kDebugMode) {
            debugPrint('RealMicLevelStream: stream error: $e');
          }
        },
      );
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('RealMicLevelStream: failed to start: $e');
      }
      _controller?.addError(e);
      _started = false;
    }
  }

  void _onAudioData(dynamic data) {
    if (data is! List<int>) return;
    if (data.length < 2) return;
    final sampleCount = data.length ~/ 2;
    var sumSquares = 0.0;
    final byteData = ByteData.sublistView(
      data is Uint8List ? data : Uint8List.fromList(data),
    );
    for (var i = 0; i < sampleCount; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      final normalised = sample / 32768.0;
      sumSquares += normalised * normalised;
    }
    final rms = math.sqrt(sumSquares / sampleCount);
    // Compress and gamma-correct so soft whispers are still visible.
    final level = _compress(rms).clamp(0.0, 1.0);
    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      controller.add(MicLevel(level01: level, timestamp: DateTime.now()));
    }
  }

  /// Perceptual compression: RMS → [0,1] with a curve that makes quiet
  /// sounds more visible and clips loud ones at 1.0.
  static double _compress(double rms) {
    if (rms <= 0) return 0;
    // sqrt lifts the quiet end; *4 scales typical speech to ~0.3–0.7.
    final boosted = math.sqrt(rms) * 4;
    return boosted.clamp(0.0, 1.0);
  }

  void _stopIfNoListeners() {
    final controller = _controller;
    if (controller != null && controller.hasListener) return;
    _stop();
  }

  Future<void> _stop() async {
    await _audioSub?.cancel();
    _audioSub = null;
    if (_started) {
      try {
        await _channel.invokeMethod('stopMic');
      } on Object {
        // Recorder may already be stopped.
      }
    }
    _started = false;
  }

  @override
  Future<void> dispose() async {
    await _stop();
    await _controller?.close();
    _controller = null;
  }
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
