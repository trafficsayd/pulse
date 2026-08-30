import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/modes/presentation/modes/sync_mode_screen.dart';
import '../features/session/application/mode_event.dart';
import '../features/session/application/mode_event_bus.dart';
import '../l10n/app_localizations.dart';

/// Debug-only Shared Pulse entrypoint. Each local touch receives a simulated
/// partner touch after realistic short latency, so all visual stages can be
/// inspected on one emulator without changing a saved real connection.
void main() {
  // This debug entrypoint lives for the duration of the process.
  // ignore: close_sinks
  final incoming = StreamController<ModeEvent>.broadcast(sync: true);
  var partnerTap = 0;
  late final ModeEventBus bus;
  bus = ModeEventBus.testing(
    incoming.stream,
    onSend: (event) {
      switch (event.type) {
        case 'sync_ping':
          final id = event.data['id'];
          final localSentAtUs = event.data['sentAtUs'];
          final receivedAtUs = DateTime.now().microsecondsSinceEpoch + 18_000;
          Future<void>.delayed(const Duration(milliseconds: 42), () {
            incoming.add(ModeEvent(
              type: 'sync_pong',
              data: {
                'id': id,
                'localSentAtUs': localSentAtUs,
                'partnerReceivedAtUs': receivedAtUs,
                'partnerSentAtUs': receivedAtUs + 800,
              },
            ));
          });
          break;
        case 'sync_tap':
          final progress = event.data['progress'] as num? ?? 0;
          Future<void>.delayed(const Duration(milliseconds: 82), () {
            incoming.add(ModeEvent(
              type: 'sync_tap',
              data: {
                'id': ++partnerTap,
                'sentAtUs': DateTime.now().microsecondsSinceEpoch + 18_000,
                'progress': progress.toDouble(),
              },
            ));
          });
          break;
        case 'sync_hold':
          Future<void>.delayed(const Duration(milliseconds: 90), () {
            incoming.add(event);
          });
          break;
      }
    },
  );
  runApp(
    ProviderScope(
      overrides: [modeEventBusProvider.overrideWithValue(bus)],
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
        home: SyncModeScreen(),
      ),
    ),
  );
}
