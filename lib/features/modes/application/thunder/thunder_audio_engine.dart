import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'thunder_models.dart';

abstract interface class ThunderAudioEngine {
  Future<void> play(ThunderStrike strike, {required int durationMs});
  Future<void> stop();
}

class PlatformThunderAudioEngine implements ThunderAudioEngine {
  const PlatformThunderAudioEngine();

  static const MethodChannel _channel =
      MethodChannel('app.pulse.audio/thunder');

  @override
  Future<void> play(ThunderStrike strike, {required int durationMs}) async {
    try {
      await _channel.invokeMethod<void>('play', {
        'intensity': strike.intensity,
        'direction': strike.directionX,
        'durationMs': durationMs,
        'seed': strike.seed,
      });
    } on MissingPluginException {
      await SystemSound.play(SystemSoundType.alert);
    } on PlatformException catch (error) {
      if (kDebugMode) debugPrint('Thunder audio failed: ${error.code}');
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // System sound fallback has no cancellable playback.
    } on PlatformException catch (error) {
      if (kDebugMode) debugPrint('Thunder audio stop failed: ${error.code}');
    }
  }
}
