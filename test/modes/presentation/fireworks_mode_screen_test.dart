import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/presentation/modes/fireworks/shared_fireworks_painter.dart';
import 'package:pulse/features/modes/presentation/modes/fireworks_mode_screen.dart';
import 'package:pulse/features/modes/primitives/haptic_pattern_player.dart';
import 'package:pulse/features/session/application/mode_event.dart';
import 'package:pulse/features/session/application/mode_event_bus.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets('tap sends a seeded v2 contribution', (tester) async {
    final sent = <ModeEvent>[];
    final source = StreamController<ModeEvent>.broadcast(sync: true);
    final bus = ModeEventBus.testing(source.stream, onSend: sent.add);
    addTearDown(source.close);
    addTearDown(bus.dispose);

    await _pump(
      tester,
      FireworksModeScreen(
        hapticEngine: const NullHapticEngine(),
        random: math.Random(1),
        now: () => DateTime.fromMillisecondsSinceEpoch(1000),
        idFactory: () => 'local-1',
        seedFactory: () => 42,
      ),
      overrides: [modeEventBusProvider.overrideWithValue(bus)],
    );
    await tester.tapAt(const Offset(180, 260));
    await tester.pump();

    expect(sent, hasLength(1));
    expect(sent.single.type, 'firework');
    expect(sent.single.data['v'], 2);
    final records = sent.single.data['records'] as List<dynamic>;
    final record = records.single as Map<String, dynamic>;
    expect(record['id'], 'local-1');
    expect(record['seed'], 42);
  });

  testWidgets('duplicate remote delivery remains one contribution',
      (tester) async {
    final source = StreamController<ModeEvent>.broadcast(sync: true);
    final bus = ModeEventBus.testing(source.stream);
    addTearDown(source.close);
    addTearDown(bus.dispose);
    await _pump(
      tester,
      FireworksModeScreen(
        hapticEngine: const NullHapticEngine(),
        random: math.Random(2),
        now: () => DateTime.fromMillisecondsSinceEpoch(1000),
      ),
      overrides: [modeEventBusProvider.overrideWithValue(bus)],
    );
    const event = ModeEvent(
      type: 'firework',
      data: {
        'v': 2,
        'records': [
          {
            'id': 'remote-1',
            'a': 'remote',
            'x': .4,
            'y': .3,
            'at': 1000,
            's': 0,
            'seed': 5,
            'p': 1,
          }
        ],
      },
    );
    source
      ..add(event)
      ..add(event);
    await tester.pump(const Duration(milliseconds: 150));

    expect(_painter(tester).snapshot.contributions, hasLength(1));
  });

  testWidgets('partner launch plus local response creates one culmination',
      (tester) async {
    final source = StreamController<ModeEvent>.broadcast(sync: true);
    final bus = ModeEventBus.testing(source.stream);
    addTearDown(source.close);
    addTearDown(bus.dispose);
    await _pump(
      tester,
      FireworksModeScreen(
        hapticEngine: const NullHapticEngine(),
        random: math.Random(3),
        now: () => DateTime.fromMillisecondsSinceEpoch(1000),
        idFactory: () => 'local-response',
        seedFactory: () => 44,
      ),
      overrides: [modeEventBusProvider.overrideWithValue(bus)],
    );
    source.add(const ModeEvent(
      type: 'firework',
      data: {
        'v': 2,
        'records': [
          {
            'id': 'partner-launch',
            'a': 'partner',
            'x': .3,
            'y': .3,
            'at': 1000,
            's': 0,
            'seed': 9,
            'p': 2,
          }
        ],
      },
    ));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tapAt(const Offset(620, 300));
    await tester.pump();

    final painter = _painter(tester);
    expect(painter.snapshot.contributions, hasLength(2));
    expect(painter.snapshot.culminations, hasLength(1));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('restored history does not replay an old culmination',
      (tester) async {
    final source = StreamController<ModeEvent>.broadcast(sync: true);
    final bus = ModeEventBus.testing(source.stream);
    final haptics = RecordingHapticEngine();
    addTearDown(source.close);
    addTearDown(bus.dispose);
    await _pump(
      tester,
      FireworksModeScreen(
        hapticEngine: haptics,
        random: math.Random(5),
        now: () => DateTime.fromMillisecondsSinceEpoch(10000),
      ),
      overrides: [modeEventBusProvider.overrideWithValue(bus)],
    );

    source.add(const ModeEvent(
      type: 'firework',
      data: {
        'v': 2,
        'newestId': 'current-a',
        'records': [
          {
            'id': 'old-a',
            'a': 'a',
            'x': .2,
            'y': .3,
            'at': 1000,
            's': 0,
            'seed': 1,
            'p': 0,
          },
          {
            'id': 'old-b',
            'a': 'b',
            'x': .8,
            'y': .4,
            'at': 1200,
            's': 0,
            'seed': 2,
            'p': 1,
          },
          {
            'id': 'current-a',
            'a': 'a',
            'x': .5,
            'y': .25,
            'at': 10000,
            's': 1,
            'seed': 3,
            'p': 2,
          },
        ],
      },
    ));
    await tester.pump(const Duration(milliseconds: 150));

    final painter = _painter(tester);
    expect(painter.snapshot.culminations, hasLength(1));
    expect(painter.activationById.keys, ['current-a']);
    expect(haptics.played, isEmpty);
  });

  testWidgets('visual activation bookkeeping follows bounded engine history',
      (tester) async {
    final source = StreamController<ModeEvent>.broadcast(sync: true);
    final bus = ModeEventBus.testing(source.stream);
    addTearDown(source.close);
    addTearDown(bus.dispose);
    await _pump(
      tester,
      FireworksModeScreen(
        hapticEngine: const NullHapticEngine(),
        random: math.Random(6),
        now: () => DateTime.fromMillisecondsSinceEpoch(20000),
      ),
      overrides: [modeEventBusProvider.overrideWithValue(bus)],
    );

    for (var index = 0; index < 60; index++) {
      source.add(ModeEvent(
        type: 'firework',
        data: {
          'v': 2,
          'newestId': 'remote-$index',
          'records': [
            {
              'id': 'remote-$index',
              'a': 'remote',
              'x': .5,
              'y': .3,
              'at': index * 10000,
              's': index,
              'seed': index,
              'p': index % 3,
            },
          ],
        },
      ));
    }
    await tester.pump(const Duration(milliseconds: 150));

    final painter = _painter(tester);
    expect(painter.snapshot.contributions, hasLength(48));
    expect(painter.activationById, hasLength(48));
    expect(
      painter.activationById.keys.toSet(),
      painter.snapshot.contributions.map((item) => item.id).toSet(),
    );
  });

  testWidgets('reduced motion freezes the one renderer ticker', (tester) async {
    await _pump(
      tester,
      FireworksModeScreen(
        hapticEngine: const NullHapticEngine(),
        random: math.Random(4),
      ),
      disableAnimations: true,
    );

    final painter = _painter(tester);
    expect(painter.reduceMotion, isTrue);
    expect(painter.ambientPhase, closeTo(.36, .001));
    final semanticWidget = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.value == '0',
      ),
    );
    expect(semanticWidget.properties.label, isNotEmpty);
    expect(semanticWidget.properties.onTap, isNotNull);
  });
}

SharedFireworksPainter _painter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is SharedFireworksPainter,
    ),
  );
  return paint.painter! as SharedFireworksPainter;
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
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
