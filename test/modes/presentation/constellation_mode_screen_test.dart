import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/presentation/modes/constellation_mode_screen.dart';
import 'package:pulse/features/modes/presentation/modes/constellation/constellation_sky_painter.dart';
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

  testWidgets('local star sends versioned history packet', (tester) async {
    final sent = <ModeEvent>[];
    final source = StreamController<ModeEvent>.broadcast(sync: true);
    final bus = ModeEventBus.testing(
      source.stream,
      onSend: sent.add,
    );
    addTearDown(bus.dispose);
    addTearDown(source.close);

    await _pump(
      tester,
      ConstellationModeScreen(
        random: math.Random(4),
        now: () => DateTime.fromMillisecondsSinceEpoch(500),
        idFactory: () => 'local-star',
      ),
      overrides: [modeEventBusProvider.overrideWithValue(bus)],
    );
    await tester.tapAt(const Offset(160, 260));
    await tester.pump();

    expect(sent, hasLength(1));
    expect(sent.single.type, 'star');
    expect(sent.single.data['v'], 2);
    final records = sent.single.data['records'] as List<dynamic>;
    expect(records, hasLength(1));
    expect((records.single as Map<String, dynamic>)['id'], 'local-star');
  });

  testWidgets('duplicate remote packet paints one partner star',
      (tester) async {
    final key = GlobalKey<PaintingCanvasState>();
    final source = StreamController<ModeEvent>.broadcast(sync: true);
    final bus = ModeEventBus.testing(source.stream);
    addTearDown(bus.dispose);
    addTearDown(source.close);

    await _pump(
      tester,
      ConstellationModeScreen(canvasKey: key, random: math.Random(2)),
      overrides: [modeEventBusProvider.overrideWithValue(bus)],
    );
    const event = ModeEvent(
      type: 'star',
      data: {
        'v': 2,
        'records': [
          {'id': 'remote-1', 'a': 'remote', 'x': .2, 'y': .6, 'at': 1, 's': 0}
        ],
      },
    );
    source
      ..add(event)
      ..add(event);
    await tester.pump(const Duration(milliseconds: 150));

    expect(key.currentState!.strokes, hasLength(1));
  });

  testWidgets('hidden compatibility canvas remains bounded', (tester) async {
    final key = GlobalKey<PaintingCanvasState>();
    final source = StreamController<ModeEvent>.broadcast(sync: true);
    final bus = ModeEventBus.testing(source.stream);
    addTearDown(bus.dispose);
    addTearDown(source.close);

    await _pump(
      tester,
      ConstellationModeScreen(canvasKey: key, random: math.Random(8)),
      overrides: [modeEventBusProvider.overrideWithValue(bus)],
    );
    source.add(ModeEvent(
      type: 'star',
      data: {
        'v': 2,
        'records': List.generate(
          105,
          (index) => {
            'id': 'remote-$index',
            'a': 'remote',
            'x': .2 + (index % 5) * .1,
            'y': .2 + (index % 6) * .08,
            'at': index,
            's': index,
            'e': .7,
          },
        ),
      },
    ));
    await tester.pump(const Duration(milliseconds: 150));

    expect(key.currentState!.strokes, isNotEmpty);
    expect(key.currentState!.strokes.length, lessThanOrEqualTo(96));
  });

  testWidgets('reduced motion freezes ambient renderer and stays semantic',
      (tester) async {
    await _pump(
      tester,
      ConstellationModeScreen(random: math.Random(3)),
      disableAnimations: true,
    );

    final paintFinder = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is ConstellationSkyPainter,
    );
    final paint = tester.widget<CustomPaint>(paintFinder);
    final painter = paint.painter! as ConstellationSkyPainter;
    expect(painter.reduceMotion, isTrue);
    expect(painter.phase, closeTo(.22, .001));

    final semanticWidget = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.value == '0',
      ),
    );
    expect(semanticWidget.properties.label, isNotEmpty);
    expect(semanticWidget.properties.onTap, isNotNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const <Override>[],
  bool disableAnimations = false,
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
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: child,
        ),
      ),
    ),
  );
  await tester.pump();
}
