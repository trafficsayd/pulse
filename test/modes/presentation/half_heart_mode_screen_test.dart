import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/half_heart/heart_presence_models.dart';
import 'package:pulse/features/modes/application/half_heart/heart_presence_protocol.dart';
import 'package:pulse/features/modes/presentation/modes/half_heart_mode_screen.dart';
import 'package:pulse/features/modes/primitives/haptic_pattern_player.dart';
import 'package:pulse/features/session/application/mode_event.dart';
import 'package:pulse/features/session/application/mode_event_bus.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets('hold sends ordered v2 start, keepalive and end', (tester) async {
    final harness = await _pump(tester);
    final gesture = await tester.startGesture(const Offset(180, 360));
    await tester.pump();

    expect(harness.sent, isNotEmpty);
    expect(harness.sent.first.type, 'hold_start');
    expect(harness.sent.first.data['v'], HeartPresenceProtocol.version);
    final firstHoldId = harness.sent.first.data['holdId'];

    await tester.pump(const Duration(milliseconds: 460));
    expect(harness.sent.where((event) => event.type == 'hold_start').length, 2);
    expect(harness.sent[1].data['holdId'], firstHoldId);
    expect(harness.sent[1].data['seq'], 1);

    await gesture.up();
    await tester.pump();
    expect(harness.sent.last.type, 'hold_end');
    expect(harness.sent.last.data['holdId'], firstHoldId);
  });

  testWidgets('partner hold and local hold converge to united state',
      (tester) async {
    var now = DateTime.fromMillisecondsSinceEpoch(1000);
    final harness = await _pump(tester, now: () => now);
    final gesture = await tester.startGesture(const Offset(180, 360));
    await tester.pump();
    harness.incoming.add(
      HeartPresenceProtocol.encode(
        const HeartHoldSignal(
          eventId: 'remote-event',
          holdId: 'remote-hold',
          sequence: 0,
          sentAtMs: 1000,
          held: true,
          strength: .7,
          x: .5,
          y: .5,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        find.byKey(const ValueKey('half-heart-approaching')), findsOneWidget);

    now = DateTime.fromMillisecondsSinceEpoch(1600);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('half-heart-united')), findsOneWidget);
    expect(harness.haptics.played, isNotEmpty);
    await gesture.up();
  });

  testWidgets('remote presence times out gracefully', (tester) async {
    var now = DateTime.fromMillisecondsSinceEpoch(1000);
    final harness = await _pump(tester, now: () => now);
    harness.incoming.add(const ModeEvent(type: 'hold_start'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(const ValueKey('half-heart-partnerSeeking')),
      findsOneWidget,
    );

    now = DateTime.fromMillisecondsSinceEpoch(2600);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('half-heart-waiting')), findsOneWidget);
  });

  testWidgets('touch surface exposes an accessible hold action',
      (tester) async {
    await _pump(tester);
    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('half-heart-touch-surface')),
    );
    expect(semantics.label, contains('Удерживай'));
    expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  });
}

class _Harness {
  const _Harness(this.incoming, this.sent, this.haptics);

  final StreamController<ModeEvent> incoming;
  final List<ModeEvent> sent;
  final RecordingHapticEngine haptics;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  DateTime Function()? now,
}) async {
  final incoming = StreamController<ModeEvent>.broadcast(sync: true);
  final sent = <ModeEvent>[];
  final bus = ModeEventBus.testing(incoming.stream, onSend: sent.add);
  final haptics = RecordingHapticEngine();
  var id = 0;
  addTearDown(bus.dispose);
  addTearDown(incoming.close);
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
        home: HalfHeartModeScreen(
          hapticEngine: haptics,
          now: now,
          idFactory: () => 'id-${id++}',
        ),
      ),
    ),
  );
  await tester.pump();
  return _Harness(incoming, sent, haptics);
}
