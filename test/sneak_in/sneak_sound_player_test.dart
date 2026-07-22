import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/sneak_in/presentation/sneak_signal_catalogue.dart';
import 'package:pulse/features/sneak_in/presentation/sneak_sound_player.dart';

/// Records every call so tests can assert the exact asset paths played.
class _RecordingBackend implements SneakAudioBackend {
  final List<String> played = [];
  int configured = 0;
  int disposed = 0;

  @override
  Future<void> configure() async {
    configured++;
  }

  @override
  Future<void> play(String assetPath) async {
    played.add(assetPath);
  }

  @override
  Future<void> dispose() async {
    disposed++;
  }
}

/// Simulates a host without the audio plugin (unit tests, desktop dev
/// runs) — every call explodes the way a missing platform channel would.
class _ThrowingBackend implements SneakAudioBackend {
  @override
  Future<void> configure() async => throw StateError('no platform');

  @override
  Future<void> play(String assetPath) async => throw StateError('no platform');

  @override
  Future<void> dispose() async => throw StateError('no platform');
}

void main() {
  group('SneakSoundPlayer', () {
    test('plays the catalogue asset for a known signal id', () async {
      final backend = _RecordingBackend();
      final player = SneakSoundPlayer(backend: backend);

      final signal = kSneakSignals.first;
      await player.playSignal(signal.id);

      expect(backend.configured, 1);
      expect(backend.played, ['sounds/sneak/${signal.id}.m4a']);
    });

    test('configures the backend only once across plays', () async {
      final backend = _RecordingBackend();
      final player = SneakSoundPlayer(backend: backend);

      await player.playSignal(kSneakSignals.first.id);
      await player.playSignal(kSneakSignals.last.id);

      expect(backend.configured, 1);
      expect(backend.played, hasLength(2));
    });

    test('unknown signal id is a silent no-op', () async {
      final backend = _RecordingBackend();
      final player = SneakSoundPlayer(backend: backend);

      await player.playSignal('definitely-not-a-signal');

      expect(backend.configured, 0);
      expect(backend.played, isEmpty);
    });

    test('backend errors never escape (fail-soft policy)', () async {
      final player = SneakSoundPlayer(backend: _ThrowingBackend());

      // Must complete without throwing: sound is an additive layer on top
      // of the guaranteed vibration + bubble feedback.
      await player.playSignal(kSneakSignals.first.id);
      await player.dispose();
    });

    test('dispose reaches the backend', () async {
      final backend = _RecordingBackend();
      final player = SneakSoundPlayer(backend: backend);

      await player.dispose();

      expect(backend.disposed, 1);
    });
  });

  group('sneak signal catalogue', () {
    test('every entry maps to an .m4a under assets/sounds/sneak/', () {
      for (final signal in kSneakSignals) {
        expect(signal.assetPath, startsWith('assets/sounds/sneak/'));
        expect(signal.assetPath, endsWith('.m4a'));
      }
    });

    test('findSneakSignal resolves every catalogue id and rejects unknowns',
        () {
      for (final signal in kSneakSignals) {
        expect(findSneakSignal(signal.id), same(signal));
      }
      expect(findSneakSignal('nope'), isNull);
    });
  });
}
