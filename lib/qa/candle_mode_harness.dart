import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/capabilities/application/capability_providers.dart';
import '../features/capabilities/data/capability_detector.dart';
import '../features/capabilities/domain/device_capability.dart';
import '../features/modes/presentation/modes/candle_mode_screen.dart';
import '../features/modes/primitives/haptic_pattern_player.dart';
import '../features/modes/primitives/mic_level_stream.dart';
import '../features/session/application/mode_event.dart';
import '../features/session/application/mode_event_bus.dart';
import '../l10n/app_localizations.dart';

/// Debug entrypoint used for physical/emulator Candle QA without mutating a
/// real saved pair. It is never referenced by the production entrypoint.
void main() {
  // Process-lived streams are intentional in this isolated debug entrypoint.
  // ignore: close_sinks
  final partner = StreamController<ModeEvent>.broadcast();
  final mic = FakeMicLevelStream();
  late final ModeEventBus bus;
  bus = ModeEventBus.testing(
    partner.stream,
    onSend: (event) async {
      await Future<void>.delayed(const Duration(milliseconds: 110));
      switch (event.type) {
        case 'candle_light':
          partner.add(ModeEvent(type: event.type, data: {
            ...event.data,
            if (event.data['intent'] == true) 'intent': true,
          }));
        case 'candle_shield':
        case 'candle_memory':
          partner.add(event);
        case 'candle_wish':
          if (event.data['sealed'] == true) {
            partner.add(const ModeEvent(
              type: 'candle_wish',
              data: {'sealed': true},
            ));
          } else if (event.data['revealRequest'] == true) {
            partner.add(const ModeEvent(
              type: 'candle_wish',
              data: {
                'revealRequest': true,
                'revealedText': 'Пусть наш огонь всегда находит дорогу домой',
              },
            ));
          }
        case 'candle_portal':
          partner.add(ModeEvent(
            type: 'candle_portal',
            data: {
              'enabled': event.data['enabled'] ?? false,
              'token': ((event.data['token'] as num?)?.toInt() ?? 1) + 1,
            },
          ));
        case 'candle_blow':
          partner.add(ModeEvent(
            type: 'candle_blow',
            data: {...event.data, 'level': 0.22, 'extinguished': false},
          ));
      }
    },
  );
  runApp(
    ProviderScope(
      overrides: [
        capabilityDetectorProvider.overrideWithValue(
          const FakeCapabilityDetector({DeviceCapability.microphone}),
        ),
        modeEventBusProvider.overrideWithValue(bus),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ru'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CandleModeScreen(
          micLevelStream: mic,
          hapticEngine: const NullHapticEngine(),
          calibrationDuration: Duration.zero,
        ),
      ),
    ),
  );
}
