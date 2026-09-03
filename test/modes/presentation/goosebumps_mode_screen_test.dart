import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/haptics/application/pulse_haptic_engine.dart';
import 'package:pulse/features/modes/application/goosebumps/goosebumps_protocol.dart';
import 'package:pulse/features/modes/application/goosebumps/goosebumps_wave.dart';
import 'package:pulse/features/modes/application/tap_tap/knock_models.dart';
import 'package:pulse/features/modes/presentation/modes/goosebumps_mode_screen.dart';
import 'package:pulse/features/modes/presentation/modes/goosebumps/goosebumps_surface_painter.dart';
import 'package:pulse/features/session/application/mode_event.dart';
import 'package:pulse/features/session/application/mode_event_bus.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets('directional gesture sends one versioned wave', (tester) async {
    final incoming = StreamController<ModeEvent>.broadcast(sync: true);
    final sent = <ModeEvent>[];
    final haptics = _RecordingPulseHaptics();
    final bus = ModeEventBus.testing(incoming.stream, onSend: sent.add);
    addTearDown(bus.dispose);
    addTearDown(incoming.close);
    await _pump(tester, bus, haptics);

    final gesture = await tester.startGesture(const Offset(90, 350));
    await tester.pump(const Duration(milliseconds: 90));
    await gesture.moveTo(const Offset(340, 180));
    await tester.pump(const Duration(milliseconds: 90));
    await gesture.up();
    await tester.pump();

    expect(sent, hasLength(1));
    final wave = GoosebumpsProtocol.tryParse(sent.single);
    expect(wave, isNotNull);
    expect(wave!.directionX, greaterThan(0));
    expect(wave.directionY, lessThan(0));
    expect(sent.single.data['v'], GoosebumpsWave.protocolVersion);
    expect(haptics.characters, isNotEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('remote playback has no echo and duplicate is ignored',
      (tester) async {
    final incoming = StreamController<ModeEvent>.broadcast(sync: true);
    final sent = <ModeEvent>[];
    final haptics = _RecordingPulseHaptics();
    final bus = ModeEventBus.testing(incoming.stream, onSend: sent.add);
    addTearDown(bus.dispose);
    addTearDown(incoming.close);
    await _pump(tester, bus, haptics);

    final now = DateTime.now().millisecondsSinceEpoch;
    final event = GoosebumpsProtocol.wave(GoosebumpsWave(
      id: 'remote-wave',
      createdAtMs: now,
      startX: .5,
      startY: .7,
      directionX: 1,
      directionY: 0,
      speed: .8,
      intensity: .7,
      travelMs: 420,
      handoffMs: 0,
    ));
    incoming
      ..add(event)
      ..add(event);
    await tester.pump(const Duration(milliseconds: 140));

    expect(sent, isEmpty);
    expect(haptics.characters, hasLength(1));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('short tap remains intentionally silent', (tester) async {
    final incoming = StreamController<ModeEvent>.broadcast(sync: true);
    final sent = <ModeEvent>[];
    final bus = ModeEventBus.testing(incoming.stream, onSend: sent.add);
    addTearDown(bus.dispose);
    addTearDown(incoming.close);
    await _pump(tester, bus, _RecordingPulseHaptics());

    await tester.tapAt(const Offset(220, 380));
    await tester.pump();
    expect(sent, isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion is static and does not run a frame ticker',
      (tester) async {
    final incoming = StreamController<ModeEvent>.broadcast(sync: true);
    final bus = ModeEventBus.testing(incoming.stream);
    addTearDown(bus.dispose);
    addTearDown(incoming.close);
    await _pump(
      tester,
      bus,
      _RecordingPulseHaptics(),
      reduceMotion: true,
    );
    await tester.pump(const Duration(milliseconds: 120));

    final paint = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is GoosebumpsSurfacePainter,
      ),
    );
    expect((paint.painter! as GoosebumpsSurfacePainter).reduceMotion, isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(const SizedBox());
  });
}

class _RecordingPulseHaptics implements PulseHapticEngine {
  final List<KnockCharacter> characters = <KnockCharacter>[];

  @override
  Future<void> playKnock(KnockCharacter character) async {
    characters.add(character);
  }

  @override
  Future<void> playReply() async {}
}

Future<void> _pump(
  WidgetTester tester,
  ModeEventBus bus,
  PulseHapticEngine haptics, {
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
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
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: GoosebumpsModeScreen(
            hapticEngine: haptics,
            idFactory: () => 'local-wave',
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
