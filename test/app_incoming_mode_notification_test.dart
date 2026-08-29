import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse/app.dart';
import 'package:pulse/core/routing/routes.dart';
import 'package:pulse/core/storage/secure_key_store.dart';
import 'package:pulse/features/connections/application/connections_controller.dart';
import 'package:pulse/features/connections/data/connections_repository.dart';
import 'package:pulse/features/connections/domain/connection_status.dart';
import 'package:pulse/features/hub/presentation/hub_screen.dart';
import 'package:pulse/features/pairing/application/pairing_controller.dart';
import 'package:pulse/features/session/application/mode_event.dart';
import 'package:pulse/features/session/application/mode_event_bus.dart';
import 'package:pulse/features/sneak_in/presentation/sneak_in_incoming_screen.dart';
import 'package:pulse/features/transport/webrtc/signaling_client.dart';

void main() {
  testWidgets('does not show an incoming banner over the active mode',
      (tester) async {
    final store = SecureKeyStore();
    await ConnectionsRepository(keyStore: store).create(
      nickname: 'Saved partner',
      colorIndex: 0,
      emoji: '🌞',
      status: ConnectionStatus.active,
    );
    final source = StreamController<ModeEvent>.broadcast(sync: true);
    addTearDown(source.close);
    final bus = ModeEventBus.testing(source.stream);
    final mock = MockClient((http.Request request) async {
      if (request.method == 'POST' && request.url.path == '/session') {
        return http.Response(
          '{"sessionId":"test","token":"tok","expiresAt":9999999999999}',
          201,
        );
      }
      if (request.method == 'POST') return http.Response('{"ok":true}', 200);
      return http.Response(
        '{"type":"answer","sdp":"not-a-pairing-key"}',
        200,
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureKeyStoreProvider.overrideWithValue(store),
          modeEventBusProvider.overrideWithValue(bus),
          pairingSignalingClientProvider.overrideWith(
            (ref) => SignalingClient(
              httpClient: mock,
              baseUrl: 'https://example.test',
            ),
          ),
        ],
        child: const PulseApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200));

    final hubContext = tester.element(find.byType(HubScreen));
    final router = GoRouter.of(hubContext);
    router.push(Routes.modePath('tapTap'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Imperative push intentionally leaves the public URI on the hub.
    expect(router.routeInformationProvider.value.uri.path, Routes.hub);

    source.add(const ModeEvent(type: 'breath_level', data: {'level': 0.0}));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(SnackBar), findsNothing);

    source.add(const ModeEvent(type: 'tap'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(SnackBar), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('incoming sneak-in opens only the receiver overlay',
      (tester) async {
    final store = SecureKeyStore();
    await ConnectionsRepository(keyStore: store).create(
      nickname: 'Saved partner',
      colorIndex: 0,
      emoji: '🌞',
      status: ConnectionStatus.active,
    );
    final source = StreamController<ModeEvent>.broadcast(sync: true);
    addTearDown(source.close);
    final bus = ModeEventBus.testing(source.stream);
    final mock = MockClient((http.Request request) async {
      if (request.method == 'POST' && request.url.path == '/session') {
        return http.Response(
          '{"sessionId":"test","token":"tok","expiresAt":9999999999999}',
          201,
        );
      }
      if (request.method == 'POST') return http.Response('{"ok":true}', 200);
      return http.Response(
        '{"type":"answer","sdp":"not-a-pairing-key"}',
        200,
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureKeyStoreProvider.overrideWithValue(store),
          modeEventBusProvider.overrideWithValue(bus),
          pairingSignalingClientProvider.overrideWith(
            (ref) => SignalingClient(
              httpClient: mock,
              baseUrl: 'https://example.test',
            ),
          ),
        ],
        child: const PulseApp(),
      ),
    );
    for (var i = 0; i < 10 && find.byType(HubScreen).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(HubScreen), findsOneWidget);
    final hubContext = tester.element(find.byType(HubScreen));
    final router = GoRouter.of(hubContext);
    final container = ProviderScope.containerOf(hubContext);
    expect(container.read(connectionsControllerProvider).active, isNotNull);

    source.add(
      const ModeEvent(type: 'sneak_in', data: {'signal': '🐭'}),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      router.routeInformationProvider.value.uri.path,
      Routes.sneakInIncoming,
    );
    expect(find.byType(SneakInIncomingScreen), findsOneWidget);
    expect(find.text('🐭'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
