import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse/features/transport/transport.dart';
import 'package:pulse/features/transport/webrtc/signaling_client.dart';
import 'package:pulse/features/transport/webrtc_transport.dart';

void main() {
  group('WebRtcTransport', () {
    test('kind is relay', () {
      final transport = WebRtcTransport();
      expect(transport.kind, TransportKind.relay);
    });

    test('isConnected is initially false', () {
      final transport = WebRtcTransport();
      expect(transport.isConnected, isFalse);
    });

    test('connect without signalingToken emits searching', () async {
      final transport = WebRtcTransport();
      final states = <TransportKind>[];
      transport.state.listen(states.add);

      await transport.connect(reconnectTokens: {});
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(states, contains(TransportKind.searching));
      expect(transport.isConnected, isFalse);
    });

    test('send does not throw when disconnected', () async {
      final transport = WebRtcTransport();
      // Should not throw.
      await transport.send(TransportPacket(
        kind: 'test',
        payload: Uint8List.fromList([1, 2, 3]),
      ));
    });

    test('disconnect resets connected state', () async {
      final transport = WebRtcTransport();
      await transport.disconnect();
      expect(transport.isConnected, isFalse);
    });

    test('incoming stream is broadcast', () async {
      final transport = WebRtcTransport();
      // Should be able to listen multiple times without error.
      final sub1 = transport.incoming.listen((_) {});
      final sub2 = transport.incoming.listen((_) {});
      await sub1.cancel();
      await sub2.cancel();
    });

    test('relays packets between two peers through signaling messages',
        () async {
      final server = _RelayServer();
      final a = WebRtcTransport(signalingClient: server.client());
      final b = WebRtcTransport(signalingClient: server.client());
      addTearDown(a.disconnect);
      addTearDown(b.disconnect);

      await a.connect(reconnectTokens: <String, String>{
        'signalingToken': 'pair-token',
      });
      await b.connect(reconnectTokens: <String, String>{
        'signalingToken': 'pair-token',
      });

      final received = b.incoming.first;
      await a.send(TransportPacket(
        kind: 'sealed',
        payload: Uint8List.fromList(<int>[1, 3, 5, 7]),
      ));

      final packet = await received.timeout(const Duration(seconds: 2));
      expect(packet.kind, 'sealed');
      expect(packet.payload, <int>[1, 3, 5, 7]);
    });
  });
}

class _RelayServer {
  final Map<String, String> _sessionsByCode = <String, String>{};
  final Map<String, List<Map<String, Object?>>> _messages =
      <String, List<Map<String, Object?>>>{};

  int _nextSession = 0;

  SignalingClient client() => SignalingClient(
        httpClient: MockClient(_handle),
        baseUrl: 'https://relay.test',
        longPollTimeout: const Duration(milliseconds: 200),
      );

  Future<http.Response> _handle(http.Request request) async {
    if (request.method == 'POST' && request.url.path == '/session') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final code = body['pairingCode']! as String;
      final sessionId = _sessionsByCode.putIfAbsent(
        code,
        () => 'abc${_nextSession++}',
      );
      _messages.putIfAbsent(sessionId, () => <Map<String, Object?>>[]);
      return _json(<String, Object?>{
        'sessionId': sessionId,
        'token': 'tok-$sessionId',
        'expiresAt': 9_999_999_999_999,
      }, 201);
    }

    final match =
        RegExp(r'^/session/([^/]+)/messages$').firstMatch(request.url.path);
    if (match == null) {
      return http.Response('not found', 404);
    }
    final sessionId = match.group(1)!;
    final list = _messages.putIfAbsent(
      sessionId,
      () => <Map<String, Object?>>[],
    );

    if (request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      list.add(<String, Object?>{
        'senderId': body['senderId'],
        'kind': body['kind'],
        'payload': body['payload'],
        'storedAt': DateTime.now().millisecondsSinceEpoch,
      });
      return _json(<String, Object?>{'ok': true, 'cursor': list.length}, 200);
    }

    if (request.method == 'GET') {
      final since =
          int.tryParse(request.url.queryParameters['since'] ?? '0') ?? 0;
      if (since >= list.length) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response('', 204);
      }
      return _json(<String, Object?>{
        'messages': list.skip(since).toList(),
        'cursor': list.length,
      }, 200);
    }

    return http.Response('method not allowed', 405);
  }

  http.Response _json(Map<String, Object?> body, int status) => http.Response(
        jsonEncode(body),
        status,
        headers: <String, String>{'content-type': 'application/json'},
      );
}
