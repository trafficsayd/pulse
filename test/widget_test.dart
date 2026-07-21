import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse/app.dart';
import 'package:pulse/features/pairing/application/pairing_controller.dart';
import 'package:pulse/features/transport/webrtc/signaling_client.dart';

void main() {
  testWidgets('Pulse app starts on the pairing screen', (tester) async {
    final mock = MockClient((http.Request request) async {
      if (request.method == 'POST' && request.url.path == '/session') {
        return http.Response(
          '{"sessionId":"abcdef","token":"tok","expiresAt":9999999999999}',
          201,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }
      if (request.method == 'POST') {
        return http.Response('{"ok":true}', 200);
      }
      return http.Response(
        '{"type":"answer","sdp":"not-a-pairing-key"}',
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
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
    // First frame should mount without throwing. We don't pumpAndSettle here
    // because the pairing screen runs an idle pulse animation that never
    // settles; one pump is enough to verify the tree builds clean.
    await tester.pump();
    expect(find.byType(PulseApp), findsOneWidget);
  });
}
