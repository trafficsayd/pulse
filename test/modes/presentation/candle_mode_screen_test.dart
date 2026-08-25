import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/capabilities/application/capability_providers.dart';
import 'package:pulse/features/capabilities/data/capability_detector.dart';
import 'package:pulse/features/capabilities/domain/device_capability.dart';
import 'package:pulse/features/modes/presentation/modes/candle_mode_screen.dart';
import 'package:pulse/features/modes/primitives/haptic_pattern_player.dart';
import 'package:pulse/features/modes/primitives/mic_level_stream.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets('weak breath bends the flame without extinguishing it',
      (tester) async {
    final mic = FakeMicLevelStream();
    await _pump(tester, mic);

    await tester.tapAt(const Offset(200, 360));
    await tester.pump();
    expect(find.text('Blow to extinguish'), findsOneWidget);

    mic.add(0.35);
    await tester.pump();
    expect(find.text('Blow to extinguish'), findsOneWidget,
        reason: 'a soft breath must only move the flame');

    await _finish(tester, mic);
  });

  testWidgets('three sustained strong samples extinguish the candle',
      (tester) async {
    final mic = FakeMicLevelStream();
    await _pump(tester, mic);

    await tester.tapAt(const Offset(200, 360));
    await tester.pump();
    mic.add(0.8);
    mic.add(0.82);
    await tester.pump();
    expect(find.text('Blow to extinguish'), findsOneWidget);

    mic.add(0.85);
    await tester.pump();
    expect(find.text('Touch to light the candle'), findsOneWidget);

    await _finish(tester, mic);
  });

  testWidgets('offers three selectable candle designs', (tester) async {
    final mic = FakeMicLevelStream();
    await _pump(tester, mic);

    expect(find.byKey(const ValueKey('candle-style-classic')), findsOneWidget);
    expect(find.byKey(const ValueKey('candle-style-glass')), findsOneWidget);
    expect(find.byKey(const ValueKey('candle-style-violet')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('candle-style-violet')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);

    await _finish(tester, mic);
  });
}

Future<void> _pump(WidgetTester tester, FakeMicLevelStream mic) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        capabilityDetectorProvider.overrideWithValue(
          const FakeCapabilityDetector({DeviceCapability.microphone}),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CandleModeScreen(
          micLevelStream: mic,
          hapticEngine: const NullHapticEngine(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

Future<void> _finish(WidgetTester tester, FakeMicLevelStream mic) async {
  // Drain the short, deliberately asynchronous haptic pattern before the
  // fake clock verifies that the test left no timers behind.
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await mic.dispose();
}
