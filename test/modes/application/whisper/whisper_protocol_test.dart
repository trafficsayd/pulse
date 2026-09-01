import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/whisper/audio_feeling_controller.dart';
import 'package:pulse/features/modes/application/whisper/whisper_feeling.dart';
import 'package:pulse/features/modes/application/whisper/whisper_protocol.dart';
import 'package:pulse/features/session/application/mode_event.dart';

void main() {
  test('round trips a privacy-safe feeling without audio fields', () {
    const feeling = WhisperFeeling(
      sequence: 7,
      capturedAtMs: 42,
      intensity: 0.4567,
      breathiness: 0.8123,
      proximity: 0.6333,
    );
    final event = WhisperProtocol.encode(feeling);
    final decoded = WhisperProtocol.tryDecode(event)!;

    expect(event.type, 'whisper_level');
    expect(event.data.keys, isNot(contains('audio')));
    expect(event.data.keys, isNot(contains('pcm')));
    expect(event.data.keys, isNot(contains('text')));
    expect(decoded.sequence, 7);
    expect(decoded.intensity, closeTo(0.457, 0.001));
  });

  test('decodes the legacy level payload', () {
    final decoded = WhisperProtocol.tryDecode(
      const ModeEvent(type: 'whisper_level', data: {'level': 0.4}),
    );
    expect(decoded?.intensity, 0.4);
    expect(decoded?.breathiness, 0.72);
  });

  test('rejects malformed frames and duplicate ordered frames', () {
    expect(
      WhisperProtocol.tryDecode(
        const ModeEvent(type: 'whisper_level', data: {'intensity': 'loud'}),
      ),
      isNull,
    );
    final receiver = WhisperReceiver();
    const frame = WhisperFeeling(
      sequence: 2,
      capturedAtMs: 10,
      intensity: 0.5,
      breathiness: 0.7,
      proximity: 0.6,
    );
    expect(receiver.accept(frame), isTrue);
    expect(receiver.accept(frame), isFalse);
  });
}
