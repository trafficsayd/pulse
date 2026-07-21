import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pulse/features/capabilities/application/capability_providers.dart';
import 'package:pulse/features/capabilities/data/capability_detector.dart';
import 'package:pulse/features/capabilities/domain/device_capability.dart';
import 'package:pulse/features/modes/presentation/modes_catalog_screen.dart';
import 'package:pulse/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'full-feature device renders no "Unavailable" caption anywhere',
    (tester) async {
      await _pumpCatalog(
        tester,
        capabilities: const {
          DeviceCapability.microphone,
          DeviceCapability.accelerometer,
          DeviceCapability.vibration,
          DeviceCapability.vibrationAmplitude,
          DeviceCapability.flashlight,
          DeviceCapability.camera,
          DeviceCapability.bluetoothLe,
          DeviceCapability.localNetwork,
        },
      );
      expect(find.text('Unavailable on this device'), findsNothing);
    },
  );

  testWidgets(
    'minimal device greys out sensor-driven modes with caption',
    (tester) async {
      await _pumpCatalog(tester, capabilities: const <DeviceCapability>{});
      // Whisper needs microphone+vibration, Bell needs accelerometer —
      // both should now be marked unavailable.
      expect(find.text('Unavailable on this device'), findsWidgets);
    },
  );

  testWidgets(
    'tapping an unavailable mode shows a snackbar naming the missing capability',
    (tester) async {
      // Device has every starter capability EXCEPT microphone; tapping
      // Whisper must surface a snackbar that calls out the microphone.
      await _pumpCatalog(
        tester,
        capabilities: const {
          DeviceCapability.accelerometer,
          DeviceCapability.vibration,
        },
      );

      final whisperLabel = find.text('Whisper');
      expect(whisperLabel, findsOneWidget);
      await tester.tap(whisperLabel, warnIfMissed: false);
      await tester.pump(); // mount snackbar.
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Microphone'), findsWidgets);
    },
  );

  testWidgets(
    'error in capability probe degrades to none — modes appear unavailable',
    (tester) async {
      await _pumpCatalog(
        tester,
        detector: _FailingCapabilityDetector(),
      );
      // With DeviceCapabilities.none() fallback, sensor-driven modes
      // should show the "Unavailable" caption.
      expect(find.text('Unavailable on this device'), findsWidgets);
    },
  );

  testWidgets('capabilityLabel maps every enum value', (tester) async {
    late AppLocalizations t;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            t = AppLocalizations.of(context)!;
            return const SizedBox();
          },
        ),
      ),
    );
    for (final cap in DeviceCapability.values) {
      final label = capabilityLabel(t, cap);
      expect(label, isNotEmpty,
          reason: 'capabilityLabel must produce a non-empty string for $cap');
    }
  });
}

Future<void> _pumpCatalog(
  WidgetTester tester, {
  Set<DeviceCapability>? capabilities,
  CapabilityDetector? detector,
}) async {
  final effectiveDetector = detector ??
      FakeCapabilityDetector(capabilities ?? const <DeviceCapability>{});
  final router = GoRouter(
    initialLocation: '/modes',
    routes: [
      GoRoute(
        path: '/modes',
        builder: (_, __) => const ModesCatalogScreen(),
      ),
      GoRoute(
        path: '/subscription',
        builder: (_, __) => const SizedBox.shrink(),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        capabilityDetectorProvider.overrideWithValue(effectiveDetector),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  // First pump mounts the loading state of the FutureProvider, the second
  // resolves the future and rebuilds with caps in hand.
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

class _FailingCapabilityDetector implements CapabilityDetector {
  @override
  Future<DeviceCapabilities> probe() async =>
      throw Exception('platform channel broken');
}
