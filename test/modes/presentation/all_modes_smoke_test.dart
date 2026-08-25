import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/capabilities/application/capability_providers.dart';
import 'package:pulse/features/capabilities/data/capability_detector.dart';
import 'package:pulse/features/capabilities/domain/device_capability.dart';
import 'package:pulse/features/modes/application/mode_registry.dart';
import 'package:pulse/features/modes/primitives/accelerometer_3d_stream.dart';
import 'package:pulse/features/modes/primitives/flashlight_controller.dart';
import 'package:pulse/features/modes/primitives/haptic_pattern_player.dart';
import 'package:pulse/features/modes/primitives/mic_level_stream.dart';
import 'package:pulse/features/modes/primitives/primitive_providers.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets('all registered modes render with supported capabilities',
      (tester) async {
    final mic = FakeMicLevelStream();
    final accelerometer = FakeAccelerometer3DStream();

    for (final mode in kAllModes) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            capabilityDetectorProvider.overrideWithValue(
              FakeCapabilityDetector(DeviceCapability.values.toSet()),
            ),
            micLevelStreamProvider.overrideWithValue(mic),
            accelerometerStreamProvider.overrideWithValue(accelerometer),
            flashlightControllerProvider
                .overrideWithValue(FlashlightController()),
            hapticEngineProvider.overrideWithValue(const NullHapticEngine()),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(builder: mode.builder),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(Scaffold), findsOneWidget,
          reason: '${mode.id.name} did not render its root screen');
      expect(tester.takeException(), isNull,
          reason: '${mode.id.name} threw while rendering');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    await mic.dispose();
    await accelerometer.dispose();
  });
}
