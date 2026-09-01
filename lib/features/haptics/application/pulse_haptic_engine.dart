import '../../modes/application/tap_tap/knock_models.dart';

abstract interface class PulseHapticEngine {
  Future<void> playKnock(KnockCharacter character);

  Future<void> playReply();
}

class SilentPulseHapticEngine implements PulseHapticEngine {
  const SilentPulseHapticEngine();

  @override
  Future<void> playKnock(KnockCharacter character) async {}

  @override
  Future<void> playReply() async {}
}
