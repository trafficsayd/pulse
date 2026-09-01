import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../modes/application/tap_tap/knock_models.dart';
import '../application/pulse_haptic_engine.dart';

class PlatformHapticBridge implements PulseHapticEngine {
  const PlatformHapticBridge();

  static const MethodChannel _channel = MethodChannel('app.pulse/haptics');

  @override
  Future<void> playKnock(KnockCharacter character) async {
    final effect = character.depth.name;
    final played =
        await _invoke(effect, character.intensity, character.sharpness);
    if (played) return;
    switch (character.depth) {
      case KnockDepth.soft:
        await HapticFeedback.selectionClick();
      case KnockDepth.clear:
        await HapticFeedback.lightImpact();
      case KnockDepth.deep:
        await HapticFeedback.mediumImpact();
    }
  }

  @override
  Future<void> playReply() async {
    final played = await _invoke('reply', .72, .55);
    if (!played) await HapticFeedback.mediumImpact();
  }

  Future<bool> _invoke(
      String effect, double intensity, double sharpness) async {
    try {
      return await _channel.invokeMethod<bool>('play', {
            'effect': effect,
            'intensity': intensity,
            'sharpness': sharpness,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      debugPrint('Pulse haptic failed: ${error.code}');
      return false;
    }
  }
}
