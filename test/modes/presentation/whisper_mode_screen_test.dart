import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/capabilities/application/capability_providers.dart';
import 'package:pulse/features/capabilities/data/capability_detector.dart';
import 'package:pulse/features/capabilities/domain/device_capability.dart';
import 'package:pulse/features/modes/presentation/modes/unsupported_mode_screen.dart';
import 'package:pulse/features/modes/presentation/modes/whisper_mode_screen.dart';
import 'package:pulse/features/modes/primitives/haptic_pattern_player.dart';
import 'package:pulse/features/modes/primitives/mic_level_stream.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'fires whisper haptic when mic level exceeds threshold twice in a row',
    (tester) async {
      final mic = FakeMicLevelStream();
      final engine = RecordingHapticEngine();

      await _pump(
        tester,
        capabilities: const {
          DeviceCapability.microphone,
          DeviceCapability.vibration,
        },
        child: WhisperModeScreen(
          micLevelStream: mic,
          hapticEngine: engine,
        ),
      );

      // Below threshold: nothing fires.
      mic.add(0.05);
      mic.add(0.1);
      await tester.pump();
      expect(engine.played, isEmpty);

      // Two consecutive samples above 0.15 should fire the whisper
      // pattern exactly once.
      mic.add(0.5);
      mic.add(0.5);
      await tester.pump();
      // Pump the full whisper duration so the player's internal
      // Future.delayed timer drains before the widget unmounts.
      await tester.pump(HapticPatterns.whisper.totalDuration);
      await tester.pump(const Duration(milliseconds: 10));
      expect(engine.played, isNotEmpty,
          reason: 'two ticks over threshold must fire whisper haptic');
      expect(engine.played.length, HapticPatterns.whisper.beats.length);

      await mic.dispose();
    },
  );

  testWidgets(
    'renders unsupported screen when microphone capability is missing',
    (tester) async {
      await _pump(
        tester,
        capabilities: const <DeviceCapability>{DeviceCapability.vibration},
        child: const WhisperModeScreen(),
      );
      expect(find.byType(UnsupportedModeScreen), findsOneWidget);
    },
  );

  testWidgets(
    'single spike over threshold does NOT fire whisper haptic',
    (tester) async {
      final mic = FakeMicLevelStream();
      final engine = RecordingHapticEngine();

      await _pump(
        tester,
        capabilities: const {
          DeviceCapability.microphone,
          DeviceCapability.vibration,
        },
        child: WhisperModeScreen(
          micLevelStream: mic,
          hapticEngine: engine,
        ),
      );

      // A single spike then a quiet sample should reset the streak.
      mic.add(0.6);
      mic.add(0.02);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(engine.played, isEmpty);

      await mic.dispose();
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
  // Resolve FutureProvider for capabilities.
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}
