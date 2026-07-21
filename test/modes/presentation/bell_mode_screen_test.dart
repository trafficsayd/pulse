import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/capabilities/application/capability_providers.dart';
import 'package:pulse/features/capabilities/data/capability_detector.dart';
import 'package:pulse/features/capabilities/domain/device_capability.dart';
import 'package:pulse/features/modes/presentation/modes/bell_mode_screen.dart';
import 'package:pulse/features/modes/presentation/modes/unsupported_mode_screen.dart';
import 'package:pulse/features/modes/primitives/accelerometer_3d_stream.dart';
import 'package:pulse/features/modes/primitives/haptic_pattern_player.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'shake sustained beyond the window fires the triple haptic pattern',
    (tester) async {
      final accel = FakeAccelerometer3DStream();
      final engine = RecordingHapticEngine();
      final start = DateTime(2024, 1, 1, 12);

      await _pump(
        tester,
        capabilities: const {DeviceCapability.accelerometer},
        child: BellModeScreen(
          accelerometerStream: accel,
          hapticEngine: engine,
          shakeThreshold: 12.0,
          shakeWindow: const Duration(milliseconds: 100),
        ),
      );

      // Big magnitude: sqrt(15^2 * 3) ≈ 25.98 → netMagnitude ≈ 16.17
      accel.push(15, 15, 15, at: start);
      await tester.pump();
      expect(engine.played, isEmpty,
          reason: 'first sample only seeds the dwell window');

      // 150ms later — still over threshold, dwell exceeds window.
      accel.push(
        15,
        15,
        15,
        at: start.add(const Duration(milliseconds: 150)),
      );
      await tester.pump();
      // Pump the full pattern duration so every beat lands on the
      // recording engine before the widget tears down.
      await tester.pump(HapticPatterns.triple.totalDuration);
      await tester.pump(const Duration(milliseconds: 10));

      expect(engine.played, isNotEmpty,
          reason: 'sustained shake must fire triple haptic');
      expect(engine.played.length, HapticPatterns.triple.beats.length);

      await accel.dispose();
    },
  );

  testWidgets(
    'unsupported on devices without an accelerometer',
    (tester) async {
      await _pump(
        tester,
        capabilities: const <DeviceCapability>{},
        child: const BellModeScreen(),
      );
      expect(find.byType(UnsupportedModeScreen), findsOneWidget);
    },
  );

  testWidgets(
    'a single jolt below the dwell window does NOT ring the bell',
    (tester) async {
      final accel = FakeAccelerometer3DStream();
      final engine = RecordingHapticEngine();
      final start = DateTime(2024, 1, 1, 12);

      await _pump(
        tester,
        capabilities: const {DeviceCapability.accelerometer},
        child: BellModeScreen(
          accelerometerStream: accel,
          hapticEngine: engine,
        ),
      );

      // One big sample, then the stream goes calm immediately.
      accel.push(15, 15, 15, at: start);
      accel.push(0.1, 0.1, 9.8,
          at: start.add(const Duration(milliseconds: 30)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(engine.played, isEmpty);

      await accel.dispose();
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
