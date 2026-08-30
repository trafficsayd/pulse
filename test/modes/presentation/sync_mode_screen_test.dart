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
