import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/capabilities/application/capability_providers.dart';
import 'package:pulse/features/capabilities/data/capability_detector.dart';
import 'package:pulse/features/capabilities/domain/device_capability.dart';
import 'package:pulse/features/modes/presentation/modes/thunder_mode_screen.dart';
import 'package:pulse/features/modes/presentation/modes/unsupported_mode_screen.dart';
import 'package:pulse/features/modes/primitives/flashlight_controller.dart';
import 'package:pulse/features/modes/primitives/haptic_pattern_player.dart';
import 'package:pulse/features/modes/primitives/mic_level_stream.dart';
import 'package:pulse/l10n/app_localizations.dart';

class _RecordingFlashlightBackend extends FlashlightBackend {
  _RecordingFlashlightBackend();

  final List<String> events = [];

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> turnOn() async {
    events.add('on');
  }

  @override
  Future<void> turnOff() async {
    events.add('off');
  }
}

void main() {
  testWidgets(
    'loud clap pulses the torch and buzzes three taps',
    (tester) async {
      final mic = FakeMicLevelStream();
      final engine = RecordingHapticEngine();
      final backend = _RecordingFlashlightBackend();
      final torch = FlashlightController(backend: backend);
      final start = DateTime(2024, 1, 1, 12);

      await _pump(
        tester,
        capabilities: const {
          DeviceCapability.microphone,
          DeviceCapability.flashlight,
        },
        child: ThunderModeScreen(
          micLevelStream: mic,
          hapticEngine: engine,
          flashlightController: torch,
        ),
      );

      mic.add(0.92, at: start);
      await tester.pump();
      // Drive past the 3 × (80+60ms) flashlight train and the haptic
      // beats so every side-effect has time to land before tear-down.
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        engine.played.length,
        3,
        reason: 'tap × 3 must reach the haptic engine',
      );
      // Three on/off pairs: on, off, on, off, on, off — 6 events total.
      expect(backend.events.where((e) => e == 'on').length, 3);
      expect(backend.events.where((e) => e == 'off').length,
          greaterThanOrEqualTo(3));

      await mic.dispose();
    },
  );

  testWidgets(
    'unsupported when microphone or flashlight is missing',
    (tester) async {
      await _pump(
        tester,
        capabilities: const <DeviceCapability>{},
        child: const ThunderModeScreen(),
      );
      expect(find.byType(UnsupportedModeScreen), findsOneWidget);
    },
  );

  testWidgets(
    'a quiet sample does not trigger thunder',
    (tester) async {
      final mic = FakeMicLevelStream();
      final engine = RecordingHapticEngine();
      final backend = _RecordingFlashlightBackend();
      final torch = FlashlightController(backend: backend);

      await _pump(
        tester,
        capabilities: const {
          DeviceCapability.microphone,
          DeviceCapability.flashlight,
        },
        child: ThunderModeScreen(
          micLevelStream: mic,
          hapticEngine: engine,
          flashlightController: torch,
        ),
      );

      mic.add(0.5, at: DateTime(2024, 1, 1, 12));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(engine.played, isEmpty);
      expect(backend.events, isEmpty);

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
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}
