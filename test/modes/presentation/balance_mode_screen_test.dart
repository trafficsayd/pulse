import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/presentation/modes/balance_mode_screen.dart';
import 'package:pulse/features/modes/primitives/accelerometer_3d_stream.dart';
import 'package:pulse/features/modes/primitives/haptic_pattern_player.dart';
import 'package:pulse/features/session/application/mode_event.dart';
import 'package:pulse/features/session/application/mode_event_bus.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets('gesture fallback works without an accelerometer',
      (tester) async {
    final incoming = StreamController<ModeEvent>.broadcast(sync: true);
    final sent = <ModeEvent>[];
    final bus = ModeEventBus.testing(incoming.stream, onSend: sent.add);
    final semantics = tester.ensureSemantics();
    await _pump(tester, bus, sensorAvailable: false, reducedMotion: true);

    expect(find.text('Balance'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'Balance',
      ),
      findsOneWidget,
    );
    final gesture = await tester.startGesture(const Offset(180, 360));
    await gesture.moveTo(const Offset(520, 230));
    await tester.pump(const Duration(milliseconds: 90));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 90));

    expect(sent.any((event) => event.data['v'] == 2), isTrue);
    expect(sent.any((event) => event.data['source'] == 'gesture'), isTrue);
    expect(tester.takeException(), isNull);
    semantics.dispose();
    await _finish(tester, incoming);
  });

  testWidgets('sensor input is normalized and sent as sensor state',
      (tester) async {
    final incoming = StreamController<ModeEvent>.broadcast(sync: true);
    final sent = <ModeEvent>[];
    final sensor = FakeAccelerometer3DStream();
    final bus = ModeEventBus.testing(incoming.stream, onSend: sent.add);
    await _pump(tester, bus, accelerometer: sensor);
    for (var i = 0; i < 8; i++) {
      sensor.push(1, -2, 9.5);
    }
    for (var i = 0; i < 4; i++) {
      sensor.push(6, -2, 8);
    }
    await tester.pump(const Duration(milliseconds: 180));

    expect(
      sent.any((event) =>
          event.data['source'] == 'sensor' &&
          ((event.data['ix'] as num?)?.toDouble() ?? 0) > 0),
      isTrue,
    );
    await _finish(tester, incoming);
    await sensor.dispose();
  });

  testWidgets('remote state enters reconciliation without immediate echo',
      (tester) async {
    final incoming = StreamController<ModeEvent>.broadcast(sync: true);
    final sent = <ModeEvent>[];
    final bus = ModeEventBus.testing(incoming.stream, onSend: sent.add);
    await _pump(tester, bus, sensorAvailable: false);
    final before = sent.length;

    incoming.add(const ModeEvent(type: 'balance_ball', data: {
      'v': 2,
      'epoch': 50,
      'seq': 1,
      'x': .2,
      'y': 0,
      'ix': -.4,
      'iy': 0,
      'vx': 0,
      'vy': 0,
    }));

    expect(sent.length, before);
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.takeException(), isNull);
    await _finish(tester, incoming);
  });
}

Future<void> _pump(
  WidgetTester tester,
  ModeEventBus bus, {
  Accelerometer3DStream? accelerometer,
  bool? sensorAvailable,
  bool reducedMotion = false,
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
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: BalanceModeScreen(
            accelerometer: accelerometer,
            sensorAvailable: sensorAvailable ?? accelerometer != null,
            hapticEngine: const NullHapticEngine(),
            frameDuration: const Duration(hours: 1),
            networkSendInterval: Duration.zero,
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 90));
}

Future<void> _finish(
  WidgetTester tester,
  StreamController<ModeEvent> incoming,
) async {
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await incoming.close();
}
