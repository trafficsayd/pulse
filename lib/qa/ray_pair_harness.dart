import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/modes/presentation/modes/ray_sketch_mode_screen.dart';
import '../features/session/application/mode_event.dart';
import '../features/session/application/mode_event_bus.dart';
import '../features/session/application/session_provider.dart';
import '../features/transport/transport.dart';
import '../l10n/app_localizations.dart';

const _relayUrl = String.fromEnvironment(
  'PULSE_RAY_QA_RELAY',
  defaultValue: 'ws://10.0.2.2:21988',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installFrameDiagnostics();
  // Process-lived resources are intentional in this isolated QA entrypoint.
  // ignore: close_sinks
  final incoming = StreamController<ModeEvent>.broadcast();
  WebSocket? socket;
  final bus = ModeEventBus.testing(
    incoming.stream,
    onSend: (event) {
      final active = socket;
      if (active?.readyState == WebSocket.open) active?.add(event.encode());
    },
  );

  runApp(
    ProviderScope(
      overrides: [
        modeEventBusProvider.overrideWithValue(bus),
        transportStateProvider.overrideWith(
          (ref) => Stream.value(TransportKind.relay),
        ),
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
        home: RaySketchModeScreen(),
      ),
    ),
  );

  unawaited(_maintainRelay(
    incoming: incoming,
    onSocket: (value) => socket = value,
  ));
}

Future<void> _maintainRelay({
  required StreamController<ModeEvent> incoming,
  required ValueChanged<WebSocket?> onSocket,
}) async {
  while (true) {
    WebSocket? socket;
    try {
      socket = await WebSocket.connect(_relayUrl);
      onSocket(socket);
      socket.add(const ModeEvent(
        type: 'ray_state_request',
        data: {'v': 2, 'owner': 'qa-reconnect'},
      ).encode());
      await for (final message in socket) {
        if (message is! List<int>) continue;
        final event = ModeEvent.tryDecode(Uint8List.fromList(message));
        if (event != null) incoming.add(event);
      }
    } catch (error) {
      debugPrint('RAY_QA_RECONNECT $error');
    } finally {
      onSocket(null);
      await socket?.close();
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
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
    final average = totals.reduce((a, b) => a + b) / totals.length;
    final p90 = ((totals.length - 1) * .90).floor();
    debugPrint(
      'RAY_QA_FRAME frames=${totals.length} '
      'totalAvgMs=${average.toStringAsFixed(2)} '
      'totalP90Ms=${totals[p90].toStringAsFixed(2)} '
      'rasterP90Ms=${rasters[p90].toStringAsFixed(2)}',
    );
    totals.clear();
    rasters.clear();
  });
}
