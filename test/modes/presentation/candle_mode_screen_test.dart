import 'dart:async';

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
import 'package:pulse/features/session/application/mode_event.dart';
import 'package:pulse/features/session/application/mode_event_bus.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets('weak breath bends the flame without extinguishing it',
      (tester) async {
    final mic = FakeMicLevelStream();
    await _pump(tester, mic);

    await tester.tapAt(const Offset(200, 360));
    await tester.pump();
    expect(find.text('Breathe — the flame can feel you'), findsOneWidget);

    mic.add(0.35);
    await tester.pump();
    expect(find.text('Breathe — the flame can feel you'), findsOneWidget,
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
    expect(find.text('Breathe — the flame can feel you'), findsOneWidget);

    mic.add(0.85);
    await tester.pump();
    expect(find.text('Touch to light the flame'), findsOneWidget);

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

  testWidgets('shows room calibration before accepting breath', (tester) async {
    final mic = FakeMicLevelStream();
    await _pump(
      tester,
      mic,
      calibrationDuration: const Duration(seconds: 1),
    );

    expect(find.text('Listening to the room…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await _finish(tester, mic);
  });

  testWidgets('loud periodic speech does not extinguish the flame',
      (tester) async {
    final mic = FakeMicLevelStream();
    await _pump(tester, mic);
    await tester.tapAt(const Offset(200, 360));
    await tester.pump();

    for (var i = 0; i < 5; i++) {
      mic.add(.92, noiseLikeness: .04);
    }
    await tester.pump();

    expect(find.text('Breathe — the flame can feel you'), findsOneWidget);
    await _finish(tester, mic);
  });

  testWidgets('Promise waits for both people before lighting', (tester) async {
    final mic = FakeMicLevelStream();
    final incoming = StreamController<ModeEvent>();
    final sent = <ModeEvent>[];
    final bus = ModeEventBus.testing(
      incoming.stream,
      onSend: sent.add,
    );
    await _pump(tester, mic, bus: bus);
    await tester.tap(find.byKey(const ValueKey('candle-style-violet')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tapAt(const Offset(200, 360));
    await tester.pump();

    expect(find.text("Waiting for your close one's touch…"), findsOneWidget);
    expect(sent.last.data['intent'], isTrue);

    incoming.add(const ModeEvent(
      type: 'candle_light',
      data: {'style': 2, 'intent': true},
    ));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Breathe — the flame can feel you'), findsOneWidget);

    await _finish(tester, mic);
    await incoming.close();
  });

  testWidgets('holding the screen protects the flame and sends state',
      (tester) async {
    final mic = FakeMicLevelStream();
    final sent = <ModeEvent>[];
    final incoming = StreamController<ModeEvent>();
    final bus = ModeEventBus.testing(incoming.stream, onSend: sent.add);
    await _pump(tester, mic, bus: bus);
    await tester.tapAt(const Offset(200, 360));
    await tester.pump();
    await tester.longPressAt(const Offset(200, 360));
    await tester.pump();

    expect(
      sent.where((event) => event.type == 'candle_shield'),
      isNotEmpty,
    );
    await _finish(tester, mic);
    await incoming.close();
  });

  testWidgets('a held palm prevents strong breath from extinguishing',
      (tester) async {
    final mic = FakeMicLevelStream();
    await _pump(tester, mic);
    await tester.tapAt(const Offset(200, 360));
    await tester.pump();

    final gesture = await tester.startGesture(const Offset(200, 360));
    await tester.pump(const Duration(milliseconds: 650));
    for (var i = 0; i < 4; i++) {
      mic.add(.96);
    }
    await tester.pump();
    expect(find.text('Breathe — the flame can feel you'), findsOneWidget);
    await gesture.up();

    await _finish(tester, mic);
  });

  testWidgets('two-screen portal waits for and then joins the partner',
      (tester) async {
    final mic = FakeMicLevelStream();
    final sent = <ModeEvent>[];
    final incoming = StreamController<ModeEvent>();
    final bus = ModeEventBus.testing(incoming.stream, onSend: sent.add);
    await _pump(tester, mic, bus: bus);
    await tester.tap(find.byKey(const ValueKey('candle-portal')));
    await tester.pump();
    expect(find.text('Turn the mode on on the second phone'), findsOneWidget);
    final localToken = sent.last.data['token'] as int;

    incoming.add(ModeEvent(
      type: 'candle_portal',
      data: {'enabled': true, 'token': localToken + 1},
    ));
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      find.text('Place the glowing edges of the phones together'),
      findsOneWidget,
    );

    await _finish(tester, mic);
    await incoming.close();
  });

  testWidgets('a private wish can be sealed from the candle', (tester) async {
    final mic = FakeMicLevelStream();
    final sent = <ModeEvent>[];
    final incoming = StreamController<ModeEvent>();
    final bus = ModeEventBus.testing(incoming.stream, onSend: sent.add);
    await _pump(tester, mic, bus: bus);
    await tester.tap(find.byKey(const ValueKey('candle-wish')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(
      find.byKey(const ValueKey('candle-wish-field')),
      'Meet under the same sky',
    );
    tester.testTextInput.hide();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.ensureVisible(find.byKey(const ValueKey('candle-seal-wish')));
    await tester.tap(find.byKey(const ValueKey('candle-seal-wish')));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Your wish is sealed'), findsOneWidget);
    expect(
      sent.any((event) =>
          event.type == 'candle_wish' && event.data['sealed'] == true),
      isTrue,
    );
    await _finish(tester, mic);
    await incoming.close();
  });
}

Future<void> _pump(
  WidgetTester tester,
  FakeMicLevelStream mic, {
  Duration calibrationDuration = Duration.zero,
  ModeEventBus? bus,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        capabilityDetectorProvider.overrideWithValue(
          const FakeCapabilityDetector({DeviceCapability.microphone}),
        ),
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
        home: CandleModeScreen(
          micLevelStream: mic,
          hapticEngine: const NullHapticEngine(),
          calibrationDuration: calibrationDuration,
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
