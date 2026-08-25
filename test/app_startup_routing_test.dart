import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse/app.dart';
import 'package:pulse/core/storage/secure_key_store.dart';
import 'package:pulse/features/connections/data/connections_repository.dart';
import 'package:pulse/features/transport/webrtc/signaling_client.dart';
import 'package:pulse/features/pairing/application/pairing_controller.dart';

void main() {
  testWidgets('restores the hub when a saved connection exists', (tester) async {
    final store = SecureKeyStore();
    await ConnectionsRepository(keyStore: store).create(
      nickname: 'Saved partner',
      colorIndex: 0,
      emoji: '🌞',
    );
    final mock = MockClient((http.Request request) async {
      if (request.method == 'POST' && request.url.path == '/session') {
        return http.Response(
          '{"sessionId":"saved","token":"tok","expiresAt":9999999999999}',
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
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Long-press a mode to start'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
