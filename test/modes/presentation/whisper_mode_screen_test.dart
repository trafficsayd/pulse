import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/capabilities/application/capability_providers.dart';
import 'package:pulse/features/capabilities/data/capability_detector.dart';
import 'package:pulse/features/capabilities/domain/device_capability.dart';
import 'package:pulse/features/modes/application/whisper/whisper_feeling.dart';
import 'package:pulse/features/modes/application/whisper/whisper_protocol.dart';
import 'package:pulse/features/modes/presentation/modes/unsupported_mode_screen.dart';
import 'package:pulse/features/modes/presentation/modes/whisper_mode_screen.dart';
import 'package:pulse/features/modes/primitives/haptic_pattern_player.dart';
import 'package:pulse/features/modes/primitives/mic_level_stream.dart';
import 'package:pulse/features/session/application/mode_event.dart';
import 'package:pulse/features/session/application/mode_event_bus.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets('renders private Audio-to-Feeling surface', (tester) async {
    final mic = FakeMicLevelStream();
    await _pump(
      tester,
      capabilities: const {
        DeviceCapability.microphone,
        DeviceCapability.vibration,
      },
      child: WhisperModeScreen(
        micLevelStream: mic,
        hapticEngine: RecordingHapticEngine(),
      ),
    );

    expect(find.byKey(const Key('whisper-privacy-badge')), findsOneWidget);
    expect(find.byKey(const Key('whisper-feeling-canvas')), findsOneWidget);
    expect(find.byKey(const Key('whisper-fallback-control')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await mic.dispose();
  });

  testWidgets('incoming feeling fires haptic after two strong frames',
      (tester) async {
    final incoming = StreamController<ModeEvent>.broadcast();
    final bus = ModeEventBus.testing(incoming.stream);
    final mic = FakeMicLevelStream();
    final engine = RecordingHapticEngine();
    await _pump(
      tester,
      capabilities: const {
        DeviceCapability.microphone,
        DeviceCapability.vibration,
      },
      bus: bus,
      child: WhisperModeScreen(
        micLevelStream: mic,
        hapticEngine: engine,
      ),
    );

    incoming
      ..add(WhisperProtocol.encode(const WhisperFeeling(
        sequence: 1,
        capturedAtMs: 100,
        intensity: 0.6,
        breathiness: 0.9,
        proximity: 0.7,
      )))
      ..add(WhisperProtocol.encode(const WhisperFeeling(
        sequence: 2,
        capturedAtMs: 180,
        intensity: 0.7,
        breathiness: 0.85,
        proximity: 0.8,
      )));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(HapticPatterns.whisper.totalDuration);
    await tester.pump(const Duration(milliseconds: 10));

    expect(engine.played.length, HapticPatterns.whisper.beats.length);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await mic.dispose();
    unawaited(bus.dispose());
    unawaited(incoming.close());
  });

  testWidgets('microphone-free hold sends fallback feeling', (tester) async {
    final sent = <ModeEvent>[];
    final bus = ModeEventBus.testing(
      const Stream<ModeEvent>.empty(),
      onSend: sent.add,
    );
    await _pump(
      tester,
      capabilities: const {DeviceCapability.vibration},
      bus: bus,
      child: WhisperModeScreen(hapticEngine: RecordingHapticEngine()),
    );

    expect(find.byType(UnsupportedModeScreen), findsNothing);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('whisper-fallback-control'))),
    );
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump();

    expect(sent, isNotEmpty);
    final feelings =
        sent.map(WhisperProtocol.tryDecode).whereType<WhisperFeeling>();
    expect(feelings.any((frame) => frame.isFallback), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    unawaited(bus.dispose());
  });

  testWidgets('shows unsupported state only when vibration is absent',
      (tester) async {
    await _pump(
      tester,
      capabilities: const {DeviceCapability.microphone},
      child: const WhisperModeScreen(),
    );
    expect(find.byType(UnsupportedModeScreen), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required Set<DeviceCapability> capabilities,
  required Widget child,
  ModeEventBus? bus,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        capabilityDetectorProvider
            .overrideWithValue(FakeCapabilityDetector(capabilities)),
        if (bus != null) modeEventBusProvider.overrideWithValue(bus),
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
