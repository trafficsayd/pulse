import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/application/sandbox/sand_models.dart';
import 'package:pulse/features/modes/application/sandbox/sand_protocol.dart';
import 'package:pulse/features/modes/presentation/modes/sandbox_mode_screen.dart';
import 'package:pulse/features/modes/primitives/haptic_pattern_player.dart';
import 'package:pulse/features/session/application/mode_event.dart';
import 'package:pulse/features/session/application/mode_event_bus.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets('paint gesture sends bounded versioned material commands',
      (tester) async {
    final fixture = await _Fixture.create(tester);
    final gesture = await tester.startGesture(const Offset(80, 330));
    await tester.pump(const Duration(milliseconds: 90));
    await gesture.moveTo(const Offset(330, 210));
    await tester.pump(const Duration(milliseconds: 90));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 160));

    expect(fixture.sent, isNotEmpty);
    for (final event in fixture.sent) {
      final command = SandProtocol.tryParse(event);
      expect(command, isNotNull);
      expect(command!.tool, SandTool.paint);
      expect(command.points.length, lessThanOrEqualTo(SandCommand.maxPoints));
    }
    expect(fixture.haptics.played, isNotEmpty);
    await fixture.dispose(tester);
  });

  testWidgets('pour and erase controls change transmitted semantics',
      (tester) async {
    final fixture = await _Fixture.create(tester);
    await tester.tap(find.text('Пересыпать'));
    await tester.pump();
    await tester.tapAt(const Offset(220, 260));
    await tester.pump(const Duration(milliseconds: 120));
    expect(SandProtocol.tryParse(fixture.sent.last)?.tool, SandTool.pour);

    await tester.tap(find.text('Стереть'));
    await tester.pump();
    await tester.tapAt(const Offset(220, 260));
    await tester.pump(const Duration(milliseconds: 120));
    expect(SandProtocol.tryParse(fixture.sent.last)?.tool, SandTool.erase);
    await fixture.dispose(tester);
  });

  testWidgets('remote duplicate is replayed once without echo', (tester) async {
    final fixture = await _Fixture.create(tester);
    final event = SandProtocol.command(SandCommand(
      id: 'remote-command',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      tool: SandTool.pour,
      material: SandMaterial.moonlight,
      points: const [SandPoint(.4, .2)],
      intensity: .8,
      seed: 91,
    ));
    fixture.incoming
      ..add(event)
      ..add(event);
    await tester.pump(const Duration(milliseconds: 240));

    expect(fixture.sent, isEmpty);
    expect(fixture.haptics.played, hasLength(1));
    expect(tester.takeException(), isNull);
    await fixture.dispose(tester);
  });
}

class _Fixture {
  _Fixture(this.incoming, this.sent, this.haptics);
  final StreamController<ModeEvent> incoming;
  final List<ModeEvent> sent;
  final RecordingHapticEngine haptics;

  static Future<_Fixture> create(WidgetTester tester) async {
    final incoming = StreamController<ModeEvent>.broadcast(sync: true);
    final sent = <ModeEvent>[];
    final bus = ModeEventBus.testing(incoming.stream, onSend: sent.add);
    final haptics = RecordingHapticEngine();
    addTearDown(bus.dispose);
    addTearDown(incoming.close);
    var id = 0;
    await tester.pumpWidget(ProviderScope(
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
        home: SandboxModeScreen(
          hapticEngine: haptics,
          idFactory: () => 'command-${id++}',
        ),
      ),
    ));
    await tester.pump();
    return _Fixture(incoming, sent, haptics);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }
}
