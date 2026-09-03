import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/thunder/thunder_audio_engine.dart';
import 'package:pulse/features/modes/application/thunder/thunder_models.dart';
import 'package:pulse/features/modes/application/thunder/thunder_protocol.dart';
import 'package:pulse/features/modes/presentation/modes/thunder_mode_screen.dart';
import 'package:pulse/features/modes/primitives/flashlight_controller.dart';
import 'package:pulse/features/modes/primitives/haptic_pattern_player.dart';
import 'package:pulse/features/session/application/mode_event.dart';
import 'package:pulse/features/session/application/mode_event_bus.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets('gesture sends v2 strike and works without a flashlight',
      (tester) async {
    final incoming = StreamController<ModeEvent>.broadcast(sync: true);
    final sent = <ModeEvent>[];
    final bus = ModeEventBus.testing(incoming.stream, onSend: sent.add);
    final backend = _RecordingFlashlight(available: false);
    final haptics = RecordingHapticEngine();
    final audio = _RecordingAudio();
    addTearDown(bus.dispose);
    addTearDown(incoming.close);
    await _pump(tester, bus, backend, haptics, audio);

    final gesture = await tester.startGesture(const Offset(90, 350));
    await tester.pump(const Duration(milliseconds: 90));
    await gesture.moveTo(const Offset(340, 170));
    await tester.pump(const Duration(milliseconds: 90));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 320));

    expect(sent, hasLength(1));
    final strike = ThunderProtocol.tryParse(sent.single);
    expect(strike, isNotNull);
    expect(strike!.directionX, greaterThan(0));
    expect(strike.directionY, lessThan(0));
    expect(haptics.played, hasLength(2));
    expect(audio.played, hasLength(1));
    expect(backend.onCalls, 0);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('remote duplicate plays once and never echoes', (tester) async {
    final incoming = StreamController<ModeEvent>.broadcast(sync: true);
    final sent = <ModeEvent>[];
    final bus = ModeEventBus.testing(incoming.stream, onSend: sent.add);
    final backend = _RecordingFlashlight(available: true);
    final haptics = RecordingHapticEngine();
    final audio = _RecordingAudio();
    addTearDown(bus.dispose);
    addTearDown(incoming.close);
    await _pump(tester, bus, backend, haptics, audio);

    final event = ThunderProtocol.strike(ThunderStrike(
      id: 'remote',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      originX: .3,
      originY: .4,
      directionX: 1,
      directionY: 0,
      intensity: .55,
      velocity: .7,
      seed: 77,
      handoffMs: 0,
    ));
    incoming
      ..add(event)
      ..add(event);
    await tester.pump(const Duration(milliseconds: 500));

    expect(sent, isEmpty);
    expect(audio.played, hasLength(1));
    expect(haptics.played, hasLength(2));
    expect(backend.onCalls, 1);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'backgrounding cancels pending effects and resume does not replay',
      (tester) async {
    final incoming = StreamController<ModeEvent>.broadcast(sync: true);
    final sent = <ModeEvent>[];
    final bus = ModeEventBus.testing(incoming.stream, onSend: sent.add);
    final backend = _RecordingFlashlight(available: true);
    final haptics = _LifecycleHaptics();
    final audio = _RecordingAudio();
    addTearDown(bus.dispose);
    addTearDown(incoming.close);
    await _pump(tester, bus, backend, haptics, audio);

    final gesture = await tester.startGesture(const Offset(90, 350));
    await gesture.moveTo(const Offset(340, 170));
    await gesture.up();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 600));

    expect(backend.onCalls, 0);
    expect(backend.offCalls, 1);
    expect(haptics.played, isEmpty);
    expect(haptics.cancelCalls, 1);
    expect(audio.played, isEmpty);
    expect(audio.stopCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 600));
    expect(backend.onCalls, 0);
    expect(haptics.played, isEmpty);
    expect(audio.played, isEmpty);

    await tester.pumpWidget(const SizedBox());
  });
}

class _RecordingFlashlight extends FlashlightBackend {
  _RecordingFlashlight({required this.available});
  final bool available;
  int onCalls = 0;
  int offCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> turnOn() async => onCalls++;

  @override
  Future<void> turnOff() async => offCalls++;
}

class _RecordingAudio implements ThunderAudioEngine {
  final List<ThunderStrike> played = <ThunderStrike>[];
  int stopCalls = 0;

  @override
  Future<void> play(ThunderStrike strike, {required int durationMs}) async {
    played.add(strike);
  }

  @override
  Future<void> stop() async => stopCalls++;
}

class _LifecycleHaptics extends RecordingHapticEngine {
  int cancelCalls = 0;

  @override
  Future<void> cancel() async => cancelCalls++;
}

Future<void> _pump(
  WidgetTester tester,
  ModeEventBus bus,
  FlashlightBackend backend,
  HapticEngine haptics,
  ThunderAudioEngine audio,
) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [modeEventBusProvider.overrideWithValue(bus)],
    child: MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: ThunderModeScreen(
        flashlight: FlashlightController(backend: backend),
        hapticEngine: haptics,
        audioEngine: audio,
        idFactory: () => 'local-strike',
      ),
    ),
  ));
  await tester.pump();
}
