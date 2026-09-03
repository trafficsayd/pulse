import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/capabilities/application/capability_providers.dart';
import 'package:pulse/features/capabilities/data/capability_detector.dart';
import 'package:pulse/features/modes/presentation/modes/breath_mode_screen.dart';
import 'package:pulse/features/session/application/mode_event.dart';
import 'package:pulse/features/session/application/mode_event_bus.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets('works without microphone and emits a privacy-safe manual breath',
      (tester) async {
    final incoming = StreamController<ModeEvent>.broadcast();
    final sent = <ModeEvent>[];
    final bus = ModeEventBus.testing(incoming.stream, onSend: sent.add);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          capabilityDetectorProvider.overrideWithValue(
            const FakeCapabilityDetector({}),
          ),
          modeEventBusProvider.overrideWithValue(bus),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: BreathModeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('no microphone needed'), findsOneWidget);

    final listener = tester.widget<Listener>(
      find.byKey(const Key('breath-surface')),
    );
    listener.onPointerDown!(
      const PointerDownEvent(position: Offset(210, 300)),
    );
    await tester.pump();
    expect(sent, isNotEmpty);
    expect(sent.every((event) => event.type == 'breath_level'), isTrue);
    expect(sent.every((event) => !event.data.containsKey('audio')), isTrue);
    expect(sent.any((event) => event.data['manual'] == true), isTrue);
    listener.onPointerUp!(
      const PointerUpEvent(position: Offset(210, 300)),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 150));
    await incoming.close();
  });
}
