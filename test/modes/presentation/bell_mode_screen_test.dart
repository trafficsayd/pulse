import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/capabilities/application/capability_providers.dart';
import 'package:pulse/features/capabilities/data/capability_detector.dart';
import 'package:pulse/features/capabilities/domain/device_capability.dart';
import 'package:pulse/features/modes/application/bell/bell_models.dart';
import 'package:pulse/features/modes/application/bell/bell_protocol.dart';
import 'package:pulse/features/modes/presentation/modes/bell/bell_physical_painter.dart';
import 'package:pulse/features/modes/presentation/modes/bell_mode_screen.dart';
import 'package:pulse/features/modes/primitives/accelerometer_3d_stream.dart';
import 'package:pulse/features/modes/primitives/haptic_pattern_player.dart';
import 'package:pulse/features/session/application/mode_event.dart';
import 'package:pulse/features/session/application/mode_event_bus.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets('renders a physical bell and three selectable materials',
      (tester) async {
    await _pumpBell(tester, capabilities: const {});

    expect(
        find.byKey(const ValueKey('physical-bell-renderer')), findsOneWidget);
    expect(find.byKey(const ValueKey('bell-material-brass')), findsOneWidget);
    expect(find.byKey(const ValueKey('bell-material-crystal')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('bell-material-porcelain')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bell-material-crystal')));
    await tester.pump();
    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('physical-bell-renderer')),
    );
    expect(
        (paint.painter! as BellPhysicalPainter).material, BellMaterial.crystal);
  });

  testWidgets('without accelerometer keeps a gesture fallback instead of block',
      (tester) async {
    await _pumpBell(tester, capabilities: const {});

    expect(find.textContaining('Проведи по колокольчику'), findsOneWidget);
    expect(find.byKey(const ValueKey('bell-gesture-surface')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gesture creates a physical ring, haptic and network event',
      (tester) async {
    final haptics = RecordingHapticEngine();
    final sent = <ModeEvent>[];
    await _pumpBell(
      tester,
      capabilities: const {},
      haptics: haptics,
      onSend: sent.add,
    );

    final surface = find.byKey(const ValueKey('bell-gesture-surface'));
    await tester.fling(surface, const Offset(180, 0), 1250);
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));

    expect(haptics.played, isNotEmpty);
    expect(sent.where((event) => event.type == 'bell_ring'), isNotEmpty);
    final decoded = BellProtocol.decode(
      sent.firstWhere((event) => event.type == 'bell_ring'),
    );
    expect(decoded?.strength, inInclusiveRange(.08, 1));
  });

  testWidgets('incoming partner strike animates locally without echoing it',
      (tester) async {
    final incoming = StreamController<ModeEvent>.broadcast();
    final haptics = RecordingHapticEngine();
    final sent = <ModeEvent>[];
    await _pumpBell(
      tester,
      capabilities: const {DeviceCapability.accelerometer},
      incoming: incoming.stream,
      haptics: haptics,
      onSend: sent.add,
      accelerometer: FakeAccelerometer3DStream(),
    );

    incoming.add(BellProtocol.encode(const BellStrike(
      id: 'remote-1',
      occurredAtMs: 100,
      material: BellMaterial.porcelain,
      strength: .8,
      direction: -1,
      pitch: .68,
      resonanceSeconds: 1.9,
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.text('Он позвонил тебе'), findsOneWidget);
    expect(haptics.played, isNotEmpty);
    expect(sent, isEmpty, reason: 'remote ring must never be reflected back');
    await tester.pump(const Duration(milliseconds: 300));
    await incoming.close();
  });

  testWidgets('compact phone layout has no overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpBell(tester, capabilities: const {});
    await tester.pump(const Duration(milliseconds: 32));

    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpBell(
  WidgetTester tester, {
  required Set<DeviceCapability> capabilities,
  Stream<ModeEvent> incoming = const Stream.empty(),
  FutureOr<void> Function(ModeEvent event)? onSend,
  RecordingHapticEngine? haptics,
  Accelerometer3DStream? accelerometer,
}) async {
  final bus = ModeEventBus.testing(incoming, onSend: onSend);
  addTearDown(bus.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        capabilityDetectorProvider
            .overrideWithValue(FakeCapabilityDetector(capabilities)),
        modeEventBusProvider.overrideWithValue(bus),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: BellModeScreen(
          accelerometerStream: accelerometer,
          hapticEngine: haptics ?? RecordingHapticEngine(),
          playSystemSound: false,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}
