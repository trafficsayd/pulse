import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/presentation/modes/sync_mode_screen.dart';
import 'package:pulse/features/modes/primitives/haptic_pattern_player.dart';
import 'package:pulse/features/session/application/mode_event.dart';
import 'package:pulse/features/session/application/mode_event_bus.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets('matching partner touch starts the shared journey',
      (tester) async {
    final source = StreamController<ModeEvent>.broadcast(sync: true);
    final bus = ModeEventBus.testing(source.stream);
    await _pump(tester, bus);

    expect(find.text('Shared Pulse'), findsOneWidget);
    expect(find.text('Touch both screens in the same rhythm'), findsOneWidget);

    await tester.tapAt(const Offset(200, 350));
    source.add(ModeEvent(
      type: 'sync_tap',
      data: {
        'id': 1,
        'sentAtUs': DateTime.now().microsecondsSinceEpoch,
        'progress': 0,
      },
    ));
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text("Listen to each other's rhythm"), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _finish(tester, source);
  });

  testWidgets('long press sends a tactile wave without leaving the mode',
      (tester) async {
    final source = StreamController<ModeEvent>.broadcast(sync: true);
    final sent = <ModeEvent>[];
    final bus = ModeEventBus.testing(
      source.stream,
      onSend: sent.add,
    );
    final engine = RecordingHapticEngine();
    await _pump(tester, bus, engine: engine);

    final gesture = await tester.startGesture(const Offset(200, 350));
    await tester.pump(const Duration(milliseconds: 650));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 40));

    expect(sent.any((event) => event.type == 'sync_hold'), isTrue);
    expect(engine.played, isNotEmpty);
    expect(find.text('Shared Pulse'), findsOneWidget);
    await _finish(tester, source);
  });

  testWidgets('duplicate v2 partner touch is felt only once', (tester) async {
    final source = StreamController<ModeEvent>.broadcast(sync: true);
    final bus = ModeEventBus.testing(source.stream);
    final engine = RecordingHapticEngine();
    await _pump(tester, bus, engine: engine);
    final event = ModeEvent(
      type: 'sync_tap',
      data: {
        'v': 2,
        'epoch': 77,
        'seq': 3,
        'id': 1,
        'sentAtUs': DateTime.now().microsecondsSinceEpoch,
        'progress': 0,
      },
    );

    source.add(event);
    await tester.pump(const Duration(milliseconds: 90));
    source.add(event);
    await tester.pump(const Duration(milliseconds: 90));

    expect(engine.played, hasLength(1));
    await _finish(tester, source);
  });

  testWidgets('reduced motion keeps the full screen tappable and semantic',
      (tester) async {
    final source = StreamController<ModeEvent>.broadcast(sync: true);
    final bus = ModeEventBus.testing(source.stream);
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
            child: SyncModeScreen(
              hapticEngine: NullHapticEngine(),
              guideBeatDuration: Duration(hours: 1),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Shared Pulse' &&
            widget.properties.button == true,
      ),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(200, 350));
    await tester.pump();
    expect(tester.takeException(), isNull);
    semantics.dispose();
    await _finish(tester, source);
  });

  testWidgets('stale hold cannot become active after a newer release',
      (tester) async {
    final source = StreamController<ModeEvent>.broadcast(sync: true);
    final bus = ModeEventBus.testing(source.stream);
    final engine = RecordingHapticEngine();
    await _pump(tester, bus, engine: engine);

    source.add(const ModeEvent(type: 'sync_hold', data: {
      'v': 2,
      'epoch': 41,
      'seq': 7,
      'sentAtUs': 700,
      'active': false,
    }));
    source.add(const ModeEvent(type: 'sync_hold', data: {
      'v': 2,
      'epoch': 41,
      'seq': 6,
      'sentAtUs': 600,
      'active': true,
    }));
    await tester.pump(const Duration(milliseconds: 120));

    expect(engine.played, isEmpty);
    await _finish(tester, source);
  });

  testWidgets('pause stops network loops and resume restarts once',
      (tester) async {
    final source = StreamController<ModeEvent>.broadcast(sync: true);
    final sent = <ModeEvent>[];
    final bus = ModeEventBus.testing(source.stream, onSend: sent.add);
    await _pump(tester, bus);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final pausedCount = sent.length;
    await tester.pump(const Duration(seconds: 4));
    expect(sent.length, pausedCount);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 50));
    expect(sent.length, greaterThan(pausedCount));
    expect(tester.takeException(), isNull);
    await _finish(tester, source);
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
        home: SyncModeScreen(
          hapticEngine: engine,
          guideBeatDuration: const Duration(hours: 1),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 120));
}

Future<void> _finish(
  WidgetTester tester,
  StreamController<ModeEvent> source,
) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await source.close();
}
