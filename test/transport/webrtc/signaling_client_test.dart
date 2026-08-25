import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse/features/transport/webrtc/signaling_client.dart';

void main() {
  group('SignalingSession.fromJson', () {
    test('parses a well-formed payload', () {
      final SignalingSession session =
          SignalingSession.fromJson(const <String, Object?>{
        'sessionId': 'sid-abc',
        'token': 'tok.tok.tok',
        'expiresAt': 1_700_000_000_000,
      });
      expect(session.sessionId, 'sid-abc');
      expect(session.token, 'tok.tok.tok');
      expect(
        session.expiresAt.millisecondsSinceEpoch,
        1_700_000_000_000,
      );
    });

    test('throws on a missing field', () {
      expect(
        () => SignalingSession.fromJson(
            const <String, Object?>{'sessionId': 'x'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('SignalingSessionDescription / SignalingIceCandidate', () {
    test('round-trips through toJson / fromJson', () {
      const SignalingSessionDescription offer = SignalingSessionDescription(
        type: 'offer',
        sdp: 'v=0',
      );
      expect(
          SignalingSessionDescription.fromJson(offer.toJson()).type, 'offer');

      const SignalingIceCandidate candidate = SignalingIceCandidate(
        candidate: 'candidate:1 1 UDP 1 192.0.2.1 54001 typ host',
        sdpMid: '0',
        sdpMLineIndex: 0,
      );
      final SignalingIceCandidate parsed =
          SignalingIceCandidate.fromJson(candidate.toJson());
      expect(parsed.candidate, candidate.candidate);
      expect(parsed.sdpMid, '0');
      expect(parsed.sdpMLineIndex, 0);
    });
  });

  group('SignalingClient HTTP behaviour', () {
    test('createSession POSTs JSON and parses the 201 response', () async {
      late http.Request received;
      final MockClient mock = MockClient((http.Request req) async {
        received = req;
        return http.Response(
          jsonEncode(<String, Object?>{
            'sessionId': 'abc',
            'token': 'tok',
            'expiresAt': 9_999_999_999_999,
          }),
          201,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final SignalingClient client = SignalingClient(
        httpClient: mock,
        baseUrl: 'https://example.test',
      );
      final SignalingSession s = await client.createSession('1234');

      expect(s.sessionId, 'abc');
      expect(received.method, 'POST');
      expect(received.url.path, '/session');
      expect(
        jsonDecode(received.body) as Map<String, Object?>,
        equals(<String, Object?>{'pairingCode': '1234'}),
      );
    });

    test('createSession throws SignalingException on non-201', () async {
      final MockClient mock = MockClient(
        (http.Request _) async => http.Response('boom', 400),
      );
      final SignalingClient client = SignalingClient(
        httpClient: mock,
        baseUrl: 'https://example.test',
      );
      expect(
        () => client.createSession('1234'),
        throwsA(
          isA<SignalingException>().having(
            (SignalingException e) => e.statusCode,
            'statusCode',
            400,
          ),
        ),
      );
    });

    test('reads Retry-After from a rate-limit response', () async {
      final SignalingClient client = SignalingClient(
        httpClient: MockClient((http.Request _) async => http.Response(
              'slow down',
              429,
              headers: <String, String>{'retry-after': '17'},
            )),
        baseUrl: 'https://example.test',
      );

      try {
        await client.createSession('1234');
        fail('expected SignalingException');
      } on SignalingException catch (error) {
        expect(error.statusCode, 429);
        expect(error.retryAfter, const Duration(seconds: 17));
      }
    });

    test('getOffer returns null for a 204 response', () async {
      final MockClient mock = MockClient(
        (http.Request _) async => http.Response('', 204),
      );
      final SignalingClient client = SignalingClient(
        httpClient: mock,
        baseUrl: 'https://example.test',
      );
      expect(
        await client.getOffer(sessionId: 'sid', token: 'tok'),
        isNull,
      );
    });

    test('getAnswer parses an SDP payload on 200', () async {
      final MockClient mock = MockClient(
        (http.Request _) async => http.Response(
          jsonEncode(<String, Object?>{'type': 'answer', 'sdp': 'v=0\nanswer'}),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );
      final SignalingClient client = SignalingClient(
        httpClient: mock,
        baseUrl: 'https://example.test',
      );
      final SignalingSessionDescription? answer =
          await client.getAnswer(sessionId: 'sid', token: 'tok');
      expect(answer?.type, 'answer');
      expect(answer?.sdp, 'v=0\nanswer');
    });

    test('postIce sends the candidate body', () async {
      late http.Request received;
      final MockClient mock = MockClient((http.Request req) async {
        received = req;
        return http.Response(jsonEncode(<String, Object?>{'ok': true}), 200);
      });
      final SignalingClient client = SignalingClient(
        httpClient: mock,
        baseUrl: 'https://example.test/',
      );
      await client.postIce(
        sessionId: 'sid',
        token: 'tok',
        candidate: const SignalingIceCandidate(
          candidate: 'candidate:1 1 UDP 1 1.2.3.4 5000 typ host',
          sdpMid: '0',
          sdpMLineIndex: 0,
        ),
      );
      expect(received.headers['authorization'], 'Bearer tok');
      final Map<String, Object?> body =
          jsonDecode(received.body) as Map<String, Object?>;
      expect(body['candidate'], contains('candidate:'));
    });

    test('iceCandidates emits candidates from a 200 long-poll response',
        () async {
      int call = 0;
      final MockClient mock = MockClient((http.Request _) async {
        call++;
        if (call == 1) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'candidates': <Map<String, Object?>>[
                <String, Object?>{
                  'candidate': 'candidate:1 1 UDP 1 1.2.3.4 5000 typ host',
                  'sdpMid': '0',
                  'sdpMLineIndex': 0,
                },
              ],
              'cursor': 1,
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }
        // Second call: act as if no further candidates arrived. The Worker
        // returns 204 after its long-poll timeout. The test cancels the
        // subscription before this matters.
        return http.Response('', 204);
      });
      final SignalingClient client = SignalingClient(
        httpClient: mock,
        baseUrl: 'https://example.test',
      );
      final Stream<SignalingIceCandidate> stream = client.iceCandidates(
        sessionId: 'sid',
        token: 'tok',
      );

      final Completer<SignalingIceCandidate> first =
          Completer<SignalingIceCandidate>();
      late StreamSubscription<SignalingIceCandidate> sub;
      sub = stream.listen((SignalingIceCandidate c) {
        if (!first.isCompleted) {
          first.complete(c);
        }
      });
      final SignalingIceCandidate emitted = await first.future;
      expect(emitted.candidate, contains('candidate:'));
      await sub.cancel();
    });

    test('postMessage sends an encrypted relay packet', () async {
      late http.Request received;
      final MockClient mock = MockClient((http.Request req) async {
        received = req;
        return http.Response(jsonEncode(<String, Object?>{'ok': true}), 200);
      });
      final SignalingClient client = SignalingClient(
        httpClient: mock,
        baseUrl: 'https://example.test',
      );
      await client.postMessage(
        sessionId: 'sid',
        token: 'tok',
        message: SignalingRelayMessage(
          senderId: 'client-a',
          kind: 'sealed',
          payload: Uint8List.fromList(<int>[1, 2, 3]),
          storedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );

      expect(received.url.path, '/session/sid/messages');
      expect(received.headers['authorization'], 'Bearer tok');
      final Map<String, Object?> body =
          jsonDecode(received.body) as Map<String, Object?>;
      expect(body['senderId'], 'client-a');
      expect(body['kind'], 'sealed');
      expect(body['payload'], base64Encode(<int>[1, 2, 3]));
    });

    test('messages emits relay packets from a long-poll response', () async {
      int call = 0;
      final MockClient mock = MockClient((http.Request _) async {
        call++;
        if (call == 1) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'messages': <Map<String, Object?>>[
                <String, Object?>{
                  'senderId': 'client-b',
                  'kind': 'sealed',
                  'payload': base64Encode(<int>[9, 8, 7]),
                  'storedAt': 1_700_000_000_000,
                },
              ],
              'cursor': 1,
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response('', 204);
      });
      final SignalingClient client = SignalingClient(
        httpClient: mock,
        baseUrl: 'https://example.test',
      );

      final Completer<SignalingRelayMessage> first =
          Completer<SignalingRelayMessage>();
      late StreamSubscription<SignalingRelayMessage> sub;
      sub = client
          .messages(sessionId: 'sid', token: 'tok')
          .listen((SignalingRelayMessage message) {
        if (!first.isCompleted) {
          first.complete(message);
        }
      });
      final SignalingRelayMessage emitted = await first.future;
      expect(emitted.senderId, 'client-b');
      expect(emitted.kind, 'sealed');
      expect(emitted.payload, <int>[9, 8, 7]);
      await sub.cancel();
    });

    test('rejects a non-http baseUrl', () {
      expect(
        () => SignalingClient(baseUrl: 'ftp://example.test'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
