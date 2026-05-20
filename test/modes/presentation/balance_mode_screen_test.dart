import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/capabilities/application/capability_providers.dart';
import 'package:pulse/features/capabilities/data/capability_detector.dart';
import 'package:pulse/features/capabilities/domain/device_capability.dart';
import 'package:pulse/features/modes/presentation/modes/balance_mode_screen.dart';
import 'package:pulse/features/modes/presentation/modes/unsupported_mode_screen.dart';
import 'package:pulse/features/modes/primitives/accelerometer_3d_stream.dart';
import 'package:pulse/features/modes/primitives/haptic_pattern_player.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'ball reaching the rim fires a single tap haptic',
    (tester) async {
      final accel = FakeAccelerometer3DStream();
      // Quiescent partner stream: pushes a single zero sample so the
      // simulated ramp does not interfere with the assertion.
      final partner = FakeAccelerometer3DStream();
      final engine = RecordingHapticEngine();
      final start = DateTime(2024, 1, 1, 12);

      await _pump(
        tester,
        capabilities: const {DeviceCapability.accelerometer},
        child: BalanceModeScreen(
          accelerometerStream: accel,
          partnerStream: partner,
          hapticEngine: engine,
        ),
      );

      // First sample seeds the timestamp (dt = 0).
      accel.push(2.0, 0, 0, at: start);
      await tester.pump();
      // Second sample one second later → position += 2.0 * 1.0 = 2.0,
      // clamped to 1.0, which crosses the 0.9 edge threshold.
      accel.push(2.0, 0, 0, at: start.add(const Duration(seconds: 1)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        engine.played.length,
        HapticPatterns.tap.beats.length,
        reason: 'crossing the rim must fire exactly one tap pattern',
      );

      await accel.dispose();
      await partner.dispose();
    },
  );

  testWidgets(
    'unsupported on devices without an accelerometer',
    (tester) async {
      await _pump(
        tester,
        capabilities: const <DeviceCapability>{},
        child: const BalanceModeScreen(),
      );
      expect(find.byType(UnsupportedModeScreen), findsOneWidget);
    },
  );

  testWidgets(
    'staying centred does not fire any rim haptic',
    (tester) async {
      final accel = FakeAccelerometer3DStream();
      final partner = FakeAccelerometer3DStream();
      final engine = RecordingHapticEngine();
      final start = DateTime(2024, 1, 1, 12);

      await _pump(
        tester,
        capabilities: const {DeviceCapability.accelerometer},
        child: BalanceModeScreen(
          accelerometerStream: accel,
          partnerStream: partner,
          hapticEngine: engine,
        ),
      );

      accel.push(0, 0, 0, at: start);
      await tester.pump();
      accel.push(
        0,
        0,
        0,
        at: start.add(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(engine.played, isEmpty);

      await accel.dispose();
      await partner.dispose();
    },
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required Set<DeviceCapability> capabilities,
  required Widget child,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        capabilityDetectorProvider
            .overrideWithValue(FakeCapabilityDetector(capabilities)),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}
