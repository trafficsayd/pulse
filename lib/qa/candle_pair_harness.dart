import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/scheduler.dart';

import '../features/capabilities/application/capability_providers.dart';
import '../features/capabilities/data/capability_detector.dart';
import '../features/capabilities/domain/device_capability.dart';
import '../features/modes/presentation/modes/candle_mode_screen.dart';
import '../features/modes/primitives/haptic_pattern_player.dart';
import '../features/session/application/mode_event.dart';
import '../features/session/application/mode_event_bus.dart';
import '../l10n/app_localizations.dart';

const _relayUrl = String.fromEnvironment(
  'PULSE_CANDLE_QA_RELAY',
  defaultValue: 'ws://10.0.2.2:21987',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installFrameDiagnostics();
  // Process-lived resources are intentional in this isolated QA entrypoint.
  // ignore: close_sinks
  final incoming = StreamController<ModeEvent>.broadcast();
  // ignore: close_sinks
  final socket = await WebSocket.connect(_relayUrl);
  socket.listen((message) {
    if (message is! List<int>) return;
    final event = ModeEvent.tryDecode(Uint8List.fromList(message));
    if (event != null) incoming.add(event);
  });
  final bus = ModeEventBus.testing(
    incoming.stream,
    onSend: (event) => socket.add(event.encode()),
  );

  runApp(
    ProviderScope(
      overrides: [
        capabilityDetectorProvider.overrideWithValue(
          const FakeCapabilityDetector({DeviceCapability.accelerometer}),
        ),
        modeEventBusProvider.overrideWithValue(bus),
      ],
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: Locale('ru'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CandleModeScreen(
          hapticEngine: NullHapticEngine(),
          calibrationDuration: Duration.zero,
        ),
      ),
    ),
  );
}

void _installFrameDiagnostics() {
  final totals = <double>[];
  final rasters = <double>[];
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final timing in timings) {
      totals.add(timing.totalSpan.inMicroseconds / 1000);
      rasters.add(timing.rasterDuration.inMicroseconds / 1000);
    }
    if (totals.length < 180) return;
    totals.sort();
    rasters.sort();
    final totalAverage = totals.reduce((a, b) => a + b) / totals.length;
    final p90Index = ((totals.length - 1) * .90).floor();
    debugPrint(
      'CANDLE_QA_FRAME frames=${totals.length} '
      'totalAvgMs=${totalAverage.toStringAsFixed(2)} '
      'totalP90Ms=${totals[p90Index].toStringAsFixed(2)} '
      'rasterP90Ms=${rasters[p90Index].toStringAsFixed(2)}',
    );
    totals.clear();
    rasters.clear();
  });
}
