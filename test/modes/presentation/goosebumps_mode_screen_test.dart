import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/capabilities/application/capability_providers.dart';
import 'package:pulse/features/capabilities/data/capability_detector.dart';
import 'package:pulse/features/capabilities/domain/device_capability.dart';
import 'package:pulse/features/modes/presentation/modes/goosebumps_mode_screen.dart';
import 'package:pulse/features/modes/presentation/modes/unsupported_mode_screen.dart';
import 'package:pulse/features/modes/primitives/haptic_pattern_player.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'dragging emits a 12ms haptic beat per pan update',
    (tester) async {
      final engine = RecordingHapticEngine();

      await _pump(
        tester,
        capabilities: const {
          DeviceCapability.vibration,
          DeviceCapability.vibrationAmplitude,
        },
        child: GoosebumpsModeScreen(hapticEngine: engine),
      );

      final gesture = await tester.startGesture(const Offset(120, 240));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        engine.played,
        isNotEmpty,
        reason: 'drag updates must produce haptic beats',
      );
      // Every beat is the 12ms amplitude-modulated short pulse.
      expect(
        engine.played.every(
          (b) => b.duration == const Duration(milliseconds: 12),
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'falls back to the fixed-amplitude whisper beat when amplitude '
    'control is missing',
    (tester) async {
      final engine = RecordingHapticEngine(hasAmplitudeControl: false);

      await _pump(
        tester,
        // Vibration only — no amplitude control.
        capabilities: const {DeviceCapability.vibration},
        child: GoosebumpsModeScreen(hapticEngine: engine),
      );

      final gesture = await tester.startGesture(const Offset(80, 80));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      // Whisper fallback beats are 500ms long — pump past the player
      // delay so no in-flight timer leaks into widget tear-down.
      await tester.pump(HapticPatterns.whisper.totalDuration);
      await tester.pump(const Duration(milliseconds: 50));

      expect(engine.played, isNotEmpty);
      final fallback = HapticPatterns.whisper.beats.first;
      // Every beat is the whisper-fallback beat, not the dynamic 12ms.
      expect(
        engine.played.every((b) => b.duration == fallback.duration),
        isTrue,
        reason: 'fallback path must reuse HapticPatterns.whisper.beats.first',
      );
      expect(
        engine.played.every((b) => b.amplitude == fallback.amplitude),
        isTrue,
      );
    },
  );

  testWidgets(
    'unsupported when there is no vibrator at all',
    (tester) async {
      await _pump(
        tester,
        capabilities: const <DeviceCapability>{},
        child: const GoosebumpsModeScreen(),
      );
      expect(find.byType(UnsupportedModeScreen), findsOneWidget);
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
