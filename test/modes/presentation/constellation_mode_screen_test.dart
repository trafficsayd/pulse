import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/presentation/modes/constellation_mode_screen.dart';
import 'package:pulse/features/modes/primitives/painting_canvas.dart';
import 'package:pulse/features/session/application/mode_event.dart';
import 'package:pulse/features/session/application/mode_event_bus.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'tapping places a local star on the canvas',
    (tester) async {
      final key = GlobalKey<PaintingCanvasState>();

      await _pump(
        tester,
        ConstellationModeScreen(
          canvasKey: key,
          random: math.Random(7),
        ),
      );

      // Tap somewhere inside the canvas.
      await tester.tapAt(const Offset(120, 240));
      await tester.pump();

      final strokes = key.currentState!.strokes;
      // One local star recorded.
      expect(strokes.length, 1, reason: 'tap must record a local star');
      expect(strokes.first.points.length, 1);
      // Local star colour is the canonical lavender used by the screen.
      expect(strokes.first.color, const Color(0xFFB39CFF));
    },
  );

  testWidgets(
    'idle for 3s after at least 2 stars triggers the connector animation',
    (tester) async {
      final key = GlobalKey<PaintingCanvasState>();

      await _pump(
        tester,
        ConstellationModeScreen(
          canvasKey: key,
          random: math.Random(7),
          idleBeforeConnect: const Duration(seconds: 3),
        ),
      );

      await tester.tapAt(const Offset(80, 80));
      await tester.pump();
      await tester.tapAt(const Offset(240, 200));
      await tester.pump();
      // Two local strokes recorded.
      expect(key.currentState!.strokes.length, 2);

      // Fast-forward past the idle window. Idle timer fires → connector
      // animates → the painter starts drawing the bezier line.
      await tester.pump(const Duration(seconds: 3, milliseconds: 50));
      // Drive the animation forward.
      await tester.pump(const Duration(milliseconds: 500));
      // No assertion-friendly hook on the painter — just verify the
      // screen survived the idle elapsed without rebuild errors.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('partner star joins the shared constellation', (tester) async {
    final key = GlobalKey<PaintingCanvasState>();
    final source = StreamController<ModeEvent>.broadcast(sync: true);
    final bus = ModeEventBus.testing(source.stream);
    addTearDown(bus.dispose);
    addTearDown(source.close);

    await _pump(
      tester,
      ConstellationModeScreen(
        canvasKey: key,
        idleBeforeConnect: const Duration(milliseconds: 100),
      ),
      overrides: <Override>[
        modeEventBusProvider.overrideWithValue(bus),
      ],
    );

    source.add(const ModeEvent(type: 'star', data: {'x': 0.25, 'y': 0.4}));
    await tester.pump(const Duration(milliseconds: 150));
    expect(key.currentState!.strokes.length, 1);

    await tester.tapAt(const Offset(240, 280));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 300));
    expect(key.currentState!.strokes.length, 2);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const <Override>[],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
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
}
