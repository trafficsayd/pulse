import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/tap_tap/knock_models.dart';
import 'package:pulse/features/modes/application/tap_tap/knock_protocol.dart';
import 'package:pulse/features/modes/presentation/modes/tap_tap_mode_screen.dart';
import 'package:pulse/features/session/application/mode_event.dart';
import 'package:pulse/features/session/application/mode_event_bus.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets('one touch sends a versioned knock series', (tester) async {
    final incoming = StreamController<ModeEvent>.broadcast(sync: true);
    final sent = <ModeEvent>[];
    final bus = ModeEventBus.testing(incoming.stream, onSend: sent.add);
    addTearDown(bus.dispose);
    addTearDown(incoming.close);

    await _pump(tester, bus);
    await tester.tapAt(const Offset(210, 300));
    await tester.pump();

    expect(
        sent.map((event) => event.type),
        containsAllInOrder([
          'knock_begin',
          'knock_hit',
        ]));
    final hit = KnockProtocol.tryParseHit(
      sent.firstWhere((event) => event.type == 'knock_hit'),
    );
    expect(hit, isNotNull);
    expect(hit!.x, inInclusiveRange(0, 1));
    expect(hit.y, inInclusiveRange(0, 1));

    await tester.pump(const Duration(milliseconds: 910));
    expect(sent.last.type, 'knock_end');
  });

  testWidgets('incoming knock offers a one-touch reply', (tester) async {
    final incoming = StreamController<ModeEvent>.broadcast(sync: true);
    final sent = <ModeEvent>[];
    final bus = ModeEventBus.testing(incoming.stream, onSend: sent.add);
    addTearDown(bus.dispose);
    addTearDown(incoming.close);

    await _pump(tester, bus);
    incoming.add(KnockProtocol.hit(const KnockHit(
      id: 'remote-hit',
      seriesId: 'remote-series',
      sequence: 0,
      x: .4,
      y: .45,
      relativeOffsetMs: 0,
      character: KnockCharacter.legacy(),
    )));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Коснитесь, чтобы постучать в ответ'), findsOneWidget);
    expect(sent.any((event) => event.type == 'knock_receipt'), isTrue);

    await tester.tapAt(const Offset(250, 340));
    await tester.pump();
    expect(sent.any((event) => event.type == 'knock_reply'), isTrue);
  });

  testWidgets('duplicate incoming hit is acknowledged only once visually',
      (tester) async {
    final incoming = StreamController<ModeEvent>.broadcast(sync: true);
    final sent = <ModeEvent>[];
    final bus = ModeEventBus.testing(incoming.stream, onSend: sent.add);
    addTearDown(bus.dispose);
    addTearDown(incoming.close);
    await _pump(tester, bus);

    final event = KnockProtocol.hit(const KnockHit(
      id: 'same-id',
      seriesId: 'series',
      sequence: 0,
      x: .5,
      y: .5,
      relativeOffsetMs: 0,
      character: KnockCharacter.legacy(),
    ));
    incoming
      ..add(event)
      ..add(event);
    await tester.pump(const Duration(milliseconds: 120));

    expect(sent.where((event) => event.type == 'knock_receipt'), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(WidgetTester tester, ModeEventBus bus) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [modeEventBusProvider.overrideWithValue(bus)],
      child: const MaterialApp(
        locale: Locale('ru'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: TapTapModeScreen(),
      ),
    ),
  );
  await tester.pump();
}
