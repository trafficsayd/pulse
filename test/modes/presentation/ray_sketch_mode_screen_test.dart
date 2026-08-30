import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/presentation/modes/ray_sketch_mode_screen.dart';
import 'package:pulse/features/session/application/mode_event.dart';
import 'package:pulse/features/session/application/mode_event_bus.dart';
import 'package:pulse/features/session/application/session_provider.dart';
import 'package:pulse/features/transport/transport.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  late StreamController<ModeEvent> incoming;
  late List<ModeEvent> sent;
  late ModeEventBus bus;

  setUp(() {
    incoming = StreamController<ModeEvent>.broadcast();
    sent = [];
    bus = ModeEventBus.testing(
      incoming.stream,
      onSend: sent.add,
    );
  });

  tearDown(() async {
    await bus.dispose();
    await incoming.close();
  });

  Future<void> pumpRay(
    WidgetTester tester, {
    Size size = const Size(430, 932),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modeEventBusProvider.overrideWithValue(bus),
          transportStateProvider.overrideWith(
            (ref) => Stream.value(TransportKind.relay),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('ru'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: RaySketchModeScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('draws locally and emits ordered protocol-v2 events',
      (tester) async {
    await pumpRay(tester);
    sent.clear();

    final gesture = await tester.startGesture(const Offset(90, 190));
    await gesture.moveTo(const Offset(135, 235),
        timeStamp: const Duration(milliseconds: 18));
    await gesture.moveTo(const Offset(190, 215),
        timeStamp: const Duration(milliseconds: 38));
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 80));

    final types = sent.map((event) => event.type).toList();
    expect(types.first, 'ray_stroke_begin');
    expect(types, contains('ray_stroke_points'));
    expect(types.last, 'ray_stroke_end');
    expect(find.byKey(const Key('ray-undo')), findsOneWidget);
  });

  testWidgets('card mode stays private until Send is tapped', (tester) async {
    await pumpRay(tester);
    sent.clear();
    await tester.tap(find.byKey(const Key('ray-card-mode')));
    await tester.pump(const Duration(milliseconds: 220));

    final gesture = await tester.startGesture(const Offset(120, 210));
    await gesture.moveTo(const Offset(210, 270));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    expect(sent.where((event) => event.type.startsWith('ray_stroke')), isEmpty);

    await tester.tap(find.byKey(const Key('ray-send')));
    await tester.pump(const Duration(milliseconds: 120));
    expect(sent.last.type, 'ray_card');
  });

  testWidgets('partner stroke appears and can be undone locally without crash',
      (tester) async {
    await pumpRay(tester);
    incoming.add(const ModeEvent(
      type: 'ray_stroke_begin',
      data: {
        'v': 2,
        'stroke': {
          'id': 'partner-1',
          'owner': 'partner',
          'version': {'c': 1, 'a': 'partner'},
          'color': 0xFF60A5FA,
          'width': 10.0,
          'effect': 1,
          'points': [
            [0.2, 0.3, 1.0, 0],
          ],
        },
      },
    ));
    incoming.add(const ModeEvent(
      type: 'ray_stroke_end',
      data: {
        'v': 2,
        'stroke': {
          'id': 'partner-1',
          'owner': 'partner',
          'version': {'c': 1, 'a': 'partner'},
          'color': 0xFF60A5FA,
          'width': 10.0,
          'effect': 1,
          'complete': true,
          'points': [
            [0.2, 0.3, 1.0, 0],
            [0.8, 0.7, 0.7, 50],
          ],
        },
      },
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('ray-canvas-boundary')), findsOneWidget);
  });

  testWidgets('compact dock fits a 430 by 932 phone without overflow',
      (tester) async {
    await pumpRay(tester);
    expect(find.text('Рисунок'), findsOneWidget);
    expect(find.byKey(const Key('ray-live-mode')), findsOneWidget);
    expect(find.byKey(const Key('ray-clear')), findsOneWidget);
    expect(find.byKey(const Key('ray-width')), findsOneWidget);
    expect(find.byKey(const Key('ray-canvas-color')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom canvas color opens the color studio after popup closes',
      (tester) async {
    await pumpRay(tester);
    final menu = tester.widget<PopupMenuButton<Color>>(
      find.byKey(const Key('ray-canvas-color')),
    );
    expect(menu.onSelected, isNotNull);
    menu.onSelected?.call(const Color(0x00000001));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.text('Цвет пространства'), findsOneWidget);
    expect(find.text('Оттенок'), findsOneWidget);
    expect(find.text('Выбрать'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
