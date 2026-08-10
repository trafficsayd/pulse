import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sneak_signal_catalogue.dart';

/// Minimal seam between [SneakSoundPlayer] and the `audioplayers` plugin so
/// unit tests can fake the audio layer — the same pattern the mode
/// primitives use for [HapticEngine].
abstract class SneakAudioBackend {
  /// One-time preparation for short sound-effect playback: mix with any
  /// other audio (a Sneak In must never interrupt an active session,
  /// spec §7) and respect the hardware silent switch.
  Future<void> configure();

  /// Play a bundled asset. [assetPath] is relative to the Flutter `assets/`
  /// root (e.g. `sounds/sneak/knock.m4a`). Restarts playback if a previous
  /// signal is still sounding.
  Future<void> play(String assetPath);

  /// Release native resources.
  Future<void> dispose();
}

/// Production backend on top of `audioplayers`.
///
/// The native player is created lazily on the first [play], so merely
/// constructing this class never touches platform channels (keeps desktop
/// dev runs and widget tests quiet).
class AudioplayersSneakBackend implements SneakAudioBackend {
  AudioPlayer? _player;

  Future<AudioPlayer> _ensurePlayer() async {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer(playerId: 'sneak_signals');
    // Low latency keeps the sound in sync with the haptic buzz; assets are
    // tiny (≤5 KB) so the SoundPool-style path is the right fit.
    await player.setPlayerMode(PlayerMode.lowLatency);
    await player.setReleaseMode(ReleaseMode.stop);
    _player = player;
    return player;
  }

  @override
  Future<void> configure() async {
    await AudioPlayer.global.setAudioContext(
      AudioContextConfig(
        focus: AudioContextConfigFocus.mixWithOthers,
        respectSilence: true,
      ).build(),
    );
  }

  @override
  Future<void> play(String assetPath) async {
    final player = await _ensurePlayer();
    await player.stop();
    await player.play(AssetSource(assetPath));
  }

  @override
  Future<void> dispose() async {
    await _player?.dispose();
    _player = null;
  }
}

/// Plays the short Sneak In signal sounds shipped under
/// `assets/sounds/sneak/`.
///
/// Failure policy: **fail soft, never rethrow.** Vibration + the visual
/// bubble are the guaranteed Sneak In feedback (the v1.0 behaviour); sound
/// is an additive layer, so a missing asset, an unloaded plugin (unit
/// tests, desktop dev runs) or a codec error must never break the flow.
class SneakSoundPlayer {
  SneakSoundPlayer({SneakAudioBackend? backend})
      : _backend = backend ?? AudioplayersSneakBackend();

  final SneakAudioBackend _backend;
  bool _configured = false;

  /// Play the sound for [signalId] — a stable id from [kSneakSignals].
  /// Unknown ids are a silent no-op; backend errors are swallowed (logged
  /// in debug builds only, per the zero-logging stance elsewhere).
  Future<void> playSignal(String signalId) async {
    final signal = findSneakSignal(signalId);
    if (signal == null) return;
    // Catalogue paths are repo-relative (`assets/...`); AssetSource resolves
    // relative to the assets root.
    const prefix = 'assets/';
    final assetPath = signal.assetPath.startsWith(prefix)
        ? signal.assetPath.substring(prefix.length)
        : signal.assetPath;
    try {
      if (!_configured) {
        _configured = true;
        await _backend.configure();
      }
      await _backend.play(assetPath);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[SneakSoundPlayer] play failed: $e');
    }
  }

  /// Release the backend. Errors are swallowed — disposal must never throw
  /// during widget teardown.
  Future<void> dispose() async {
    try {
      await _backend.dispose();
    } on Object catch (_) {}
  }
}

/// App-wide player instance: the native player is reused across the wheel
/// (selection preview, send confirmation) and the incoming overlay.
final sneakSoundPlayerProvider = Provider<SneakSoundPlayer>((ref) {
  final player = SneakSoundPlayer();
  ref.onDispose(() {
    unawaited(player.dispose());
  });
  return player;
});
