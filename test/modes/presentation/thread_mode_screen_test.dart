import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/presentation/modes/thread_mode_screen.dart';
import 'package:pulse/features/modes/primitives/haptic_pattern_player.dart';
import 'package:pulse/features/session/application/mode_event.dart';
import 'package:pulse/features/session/application/mode_event_bus.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets('pull and release send a versioned physical gesture',
      (tester) async {
    final incoming = StreamController<ModeEvent>.broadcast(sync: true);
    final sent = <ModeEvent>[];
    final bus = ModeEventBus.testing(incoming.stream, onSend: sent.add);
    await _pump(tester, bus);

    final gesture = await tester.startGesture(const Offset(190, 390));
    await gesture.moveTo(const Offset(520, 210));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 80));

    final threadEvents = sent.where((event) => event.type == 'thread_point');
    expect(threadEvents.any((event) => event.data['phase'] == 'begin'), isTrue);
    expect(
        threadEvents.any((event) => event.data['phase'] == 'release'), isTrue);
    expect(threadEvents.every((event) => event.data['v'] == 2), isTrue);
    expect(tester.takeException(), isNull);
    await _finish(tester, incoming);
  });

  testWidgets('remote release replays once and never echoes to the network',
      (tester) async {
    final incoming = StreamController<ModeEvent>.broadcast(sync: true);
    final sent = <ModeEvent>[];
    final engine = RecordingHapticEngine();
    final bus = ModeEventBus.testing(incoming.stream, onSend: sent.add);
    await _pump(tester, bus, engine: engine);
    const remoteRelease = ModeEvent(type: 'thread_point', data: {
      'v': 2,
      'epoch': 9,
      'seq': 2,
      'sentAtUs': 100,
      'phase': 'release',
      'x': .7,
      'y': .3,
      'vx': 0,
      'vy': 0,
      'tension': .8,
    });

    incoming.add(remoteRelease);
    await tester.pump(const Duration(milliseconds: 90));
    incoming.add(remoteRelease);
    await tester.pump(const Duration(milliseconds: 90));

    expect(sent, isEmpty);
    expect(engine.played, hasLength(1));
    expect(tester.takeException(), isNull);
    await _finish(tester, incoming);
  });

  testWidgets('reduced motion exposes the mode as one semantic surface',
      (tester) async {
    final incoming = StreamController<ModeEvent>.broadcast(sync: true);
    final bus = ModeEventBus.testing(incoming.stream);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [modeEventBusProvider.overrideWithValue(bus)],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: ThreadModeScreen(
              hapticEngine: NullHapticEngine(),
              frameDuration: Duration(hours: 1),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'Thread',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
    await _finish(tester, incoming);
  });
}

Future<void> _pump(
  WidgetTester tester,
  ModeEventBus bus, {
  HapticEngine engine = const NullHapticEngine(),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [modeEventBusProvider.overrideWithValue(bus)],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ThreadModeScreen(
          hapticEngine: engine,
          frameDuration: const Duration(hours: 1),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 80));
}

Future<void> _finish(
  WidgetTester tester,
  StreamController<ModeEvent> incoming,
) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await incoming.close();
}
