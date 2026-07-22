import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

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

/// Production implementation backed by `package:record`.
///
/// Implements the same cold-stream contract as [FakeMicLevelStream]: the
/// recorder only starts when the first listener subscribes to [levels]
/// and is fully stopped when the last listener unsubscribes. This keeps
/// the OS microphone indicator dark whenever no mode is actively reading
/// the level, matching the energy/privacy contract documented on
/// [MicLevelStream].
///
/// If the app lacks microphone permission the stream stays silent
/// (no samples, no error) rather than throwing — callers already treat
/// "no data" as "nothing to react to".
class RealMicLevelStream implements MicLevelStream {
  RealMicLevelStream();

  final AudioRecorder _rec = AudioRecorder();

  StreamController<MicLevel>? _controller;
  StreamSubscription<Uint8List>? _rawSub;

  @override
  Stream<MicLevel> get levels {
    _controller ??= StreamController<MicLevel>.broadcast(
      onListen: _startRecording,
      onCancel: _stopRecording,
    );
    return _controller!.stream;
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;
    final hasPermission = await _rec.hasPermission();
    if (!hasPermission) {
      // Graceful: stay silent rather than crash or emit garbage.
      return;
    }
    if (controller.isClosed) return;
    final raw = await _rec.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        numChannels: 1,
        sampleRate: 16000,
      ),
    );
    _rawSub = raw.listen(_onChunk);
  }

  void _onChunk(Uint8List chunk) {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;
    controller.add(
      MicLevel(level01: _rmsOf(chunk), timestamp: DateTime.now()),
    );
  }

  /// Root-mean-square amplitude of a little-endian PCM16 chunk,
  /// normalized to `[0.0, 1.0]`.
  static double _rmsOf(Uint8List bytes) {
    final sampleCount = bytes.length ~/ 2;
    if (sampleCount == 0) return 0.0;
    final data = ByteData.sublistView(bytes);
    var sumSquares = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final sample = data.getInt16(i * 2, Endian.little);
      sumSquares += sample * sample;
    }
    final rms = math.sqrt(sumSquares / sampleCount);
    return (rms / 32768.0).clamp(0.0, 1.0);
  }

  Future<void> _stopRecording() async {
    await _rawSub?.cancel();
    _rawSub = null;
    await _rec.stop();
  }

  @override
  Future<void> dispose() async {
    await _stopRecording();
    await _rec.dispose();
    await _controller?.close();
  }
}
