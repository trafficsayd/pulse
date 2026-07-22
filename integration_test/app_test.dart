// Device integration tests for Pulse.
//
// Run on a REAL device (emulators can't exercise BLE / mic / sensors):
//
//   flutter test integration_test/app_test.dart -d <device-id>
//
// These are on-device smoke checks. The full two-phone pairing / mode /
// Sneak In flows are inherently multi-device and are driven manually or via
// a device farm with two targets — see integration_test/README.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pulse/app.dart';
import 'package:pulse/features/pairing/application/pairing_controller.dart';
import 'package:pulse/features/transport/webrtc/signaling_client.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A mock signaling client so the smoke test never touches the network.
  MockClient buildMockSignaling() => MockClient((http.Request request) async {
        if (request.method == 'POST' && request.url.path == '/session') {
          return http.Response(
            '{"sessionId":"abcdef","token":"tok","expiresAt":9999999999999}',
            201,
            headers: const {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST') return http.Response('{"ok":true}', 200);
        return http.Response('', 204);
      });

  testWidgets('app boots and renders its first frame on device',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pairingSignalingClientProvider.overrideWith(
            (ref) => SignalingClient(
              httpClient: buildMockSignaling(),
              baseUrl: 'https://example.test',
            ),
          ),
        ],
        child: const PulseApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PulseApp), findsOneWidget);
  });

  testWidgets('dark theme is applied (Pulse is dark-only)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pairingSignalingClientProvider.overrideWith(
            (ref) => SignalingClient(
              httpClient: buildMockSignaling(),
              baseUrl: 'https://example.test',
            ),
          ),
        ],
        child: const PulseApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final MaterialApp app = tester.widget(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });
}
