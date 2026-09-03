import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/mode_registry.dart';
import 'package:pulse/features/modes/domain/pulse_mode.dart';

void main() {
  test('fallback-capable modes have no hard capability gate', () {
    for (final id in const [
      PulseModeId.balance,
      PulseModeId.breath,
      PulseModeId.goosebumps,
      PulseModeId.thunder,
    ]) {
      expect(
        findMode(id)!.requiredCapabilities,
        isEmpty,
        reason: '$id must remain usable through its built-in fallback',
      );
    }
  });
}
