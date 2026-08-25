import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse/features/transport/transport.dart';
import 'package:pulse/features/transport/webrtc/ice_servers.dart';
import 'package:pulse/features/transport/webrtc/native_peer.dart';
import 'package:pulse/features/transport/webrtc/signaling_client.dart';
import 'package:pulse/features/transport/webrtc_transport.dart';

void main() {
  group('WebRtcTransport', () {
    test('starts disconnected and reports relay kind', () {
      final transport = WebRtcTransport();
      expect(transport.kind, TransportKind.relay);
      expect(transport.isConnected, isFalse);
    });

    test('connect without signaling token stays in searching state', () async {
      final transport = WebRtcTransport();
      final state = transport.state.first;
      await transport.connect(reconnectTokens: const <String, String>{});
      expect(await state, TransportKind.searching);
      expect(transport.isConnected, isFalse);
    });

    test('send while disconnected is a safe no-op', () async {
      final transport = WebRtcTransport();
      await transport.send(TransportPacket(
        kind: 'test',
        payload: Uint8List.fromList(<int>[1, 2, 3]),
      ));
    });

    test('upgrades from HTTP fallback to a DataChannel', () async {
      final server = _SignalingServer();
      final hub = _FakePeerHub();
      final a = WebRtcTransport(
        signalingClient: server.client(),
        peerFactory: hub.createPeer,
        negotiationTimeout: const Duration(seconds: 2),
      );
      final b = WebRtcTransport(
        signalingClient: server.client(),
        peerFactory: hub.createPeer,
        negotiationTimeout: const Duration(seconds: 2),
      );
      addTearDown(a.disconnect);
      addTearDown(b.disconnect);

      final aOpen = a.state.firstWhere((s) => s == TransportKind.relay);
      final bOpen = b.state.firstWhere((s) => s == TransportKind.relay);
      await a.connect(reconnectTokens: const <String, String>{
        'signalingToken': 'pair-token',
      });
      await b.connect(reconnectTokens: const <String, String>{
        'signalingToken': 'pair-token',
      });
      await Future.wait(<Future<TransportKind>>[aOpen, bOpen])
          .timeout(const Duration(seconds: 2));
      await _waitFor(() => hub.channelsOpen);

      final received = b.incoming.first;
      await a.send(TransportPacket(
        kind: 'sealed',
        payload: Uint8List.fromList(<int>[1, 3, 5, 7]),
      ));
      final packet = await received.timeout(const Duration(seconds: 1));

      expect(packet.kind, 'sealed');
      expect(packet.payload, <int>[1, 3, 5, 7]);
      expect(server.messageRelayRequests, 0);
      expect(hub.lastIceServers, hasLength(2));
      expect(hub.lastIceServers.every((s) => s.urls.single.startsWith('stun:')),
          isTrue);
    });

    test('keeps packets flowing through HTTP when the DataChannel cannot open',
        () async {
      final server = _SignalingServer();
      final hub = _FakePeerHub(openOnAnswer: false);
      final a = WebRtcTransport(
        signalingClient: server.client(),
        peerFactory: hub.createPeer,
        negotiationTimeout: const Duration(milliseconds: 150),
      );
      final b = WebRtcTransport(
        signalingClient: server.client(),
        peerFactory: hub.createPeer,
        negotiationTimeout: const Duration(milliseconds: 150),
      );
      addTearDown(a.disconnect);
      addTearDown(b.disconnect);

      await a.connect(reconnectTokens: const <String, String>{
        'signalingToken': 'fallback-token',
      });
      await b.connect(reconnectTokens: const <String, String>{
        'signalingToken': 'fallback-token',
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final received = b.incoming.first;
      await a.send(TransportPacket(
        kind: 'sealed',
        payload: Uint8List.fromList(<int>[2, 4, 6]),
      ));
      final packet = await received.timeout(const Duration(seconds: 1));

      expect(packet.kind, 'sealed');
      expect(packet.payload, <int>[2, 4, 6]);
      expect(server.messageRelayRequests, 1);
      expect(a.isConnected, isTrue);
      expect(b.isConnected, isTrue);
    });

    test('passes short-lived TURN credentials into the peer configuration',
        () async {
      final server = _SignalingServer(includeTurn: true);
      final hub = _FakePeerHub();
      final transport = WebRtcTransport(
        signalingClient: server.client(),
        peerFactory: hub.createPeer,
        negotiationTimeout: const Duration(milliseconds: 100),
      );
      addTearDown(transport.disconnect);
      await transport.connect(reconnectTokens: const <String, String>{
        'signalingToken': 'only-one-peer',
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        hub.lastIceServers.any((s) => s.urls.first.startsWith('turn:')),
        isTrue,
      );
    });
  });
}

class _SignalingServer {
  _SignalingServer({this.includeTurn = false});

  final bool includeTurn;
  final Map<String, String> _sessions = <String, String>{};
  final Map<String, Map<String, Object?>> _offers =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> _answers =
      <String, Map<String, Object?>>{};
  final List<Map<String, Object?>> _messages = <Map<String, Object?>>[];
  int messageRelayRequests = 0;

  SignalingClient client() => SignalingClient(
        httpClient: MockClient(_handle),
        baseUrl: 'https://signal.test',
        longPollTimeout: const Duration(milliseconds: 50),
        shortGetTimeout: const Duration(milliseconds: 50),
      );

  Future<http.Response> _handle(http.Request request) async {
    if (request.method == 'POST' && request.url.path == '/session') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final code = body['pairingCode']! as String;
      final existing = _sessions[code];
      final id = existing ?? 'abcdef${_sessions.length}';
      _sessions[code] = id;
      return _json(<String, Object?>{
        'sessionId': id,
        'token': 'tok-$id',
        'expiresAt': 9_999_999_999_999,
        'isInitiator': existing == null,
      }, 201);
    }

    final match = RegExp(r'^/session/([^/]+)/(offer|answer|ice|turn|messages)$')
        .firstMatch(request.url.path);
    if (match == null) return http.Response('not found', 404);
    final id = match.group(1)!;
    final resource = match.group(2)!;
    if (resource == 'messages') {
      if (request.method == 'POST') {
        messageRelayRequests++;
        final body = jsonDecode(request.body) as Map<String, Object?>;
        _messages.add(<String, Object?>{
          ...body,
          'storedAt': DateTime.now().millisecondsSinceEpoch,
        });
        return _json(<String, Object?>{'ok': true}, 200);
      }
      final since =
          int.tryParse(request.url.queryParameters['since'] ?? '0') ?? 0;
      if (since >= _messages.length) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return http.Response('', 204);
      }
      return _json(<String, Object?>{
        'messages': _messages.skip(since).toList(),
        'cursor': _messages.length,
      }, 200);
    }
    if (resource == 'turn') {
      if (!includeTurn) return http.Response('', 204);
      return _json(<String, Object?>{
        'iceServers': <Object?>[
          <String, Object?>{
            'urls': <String>['turn:turn.cloudflare.com:3478?transport=udp'],
            'username': 'short-user',
            'credential': 'short-secret',
          },
        ],
      }, 200);
    }
    if (resource == 'ice') {
      if (request.method == 'POST') {
        return _json(<String, Object?>{'ok': true, 'cursor': 1}, 200);
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return http.Response('', 204);
    }
    final store = resource == 'offer' ? _offers : _answers;
    if (request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      store[id] = <String, Object?>{
        ...body,
        'type': resource,
        'storedAt': DateTime.now().millisecondsSinceEpoch,
      };
      return _json(<String, Object?>{'ok': true}, 200);
    }
    final value = store[id];
    return value == null ? http.Response('', 204) : _json(value, 200);
  }

  http.Response _json(Map<String, Object?> body, int status) => http.Response(
        jsonEncode(body),
        status,
        headers: <String, String>{'content-type': 'application/json'},
      );
}

class _FakePeerHub {
  _FakePeerHub({this.openOnAnswer = true});

  final bool openOnAnswer;
  final List<_FakePeer> _peers = <_FakePeer>[];
  List<IceServer> lastIceServers = const <IceServer>[];
  _FakeChannel? _initiatorChannel;
  _FakeChannel? _responderChannel;
  bool _responderClaimed = false;

  bool get channelsOpen =>
      _initiatorChannel?._open == true && _responderChannel?._open == true;

  Future<WebRtcPeer> createPeer(List<IceServer> iceServers) async {
    lastIceServers = iceServers;
    final peer = _FakePeer(this);
    _peers.add(peer);
    return peer;
  }

  WebRtcDataChannel createChannel() {
    if (!_responderClaimed &&
        _initiatorChannel != null &&
        _responderChannel != null) {
      _responderClaimed = true;
      return _responderChannel!;
    }
    final a = _FakeChannel();
    final b = _FakeChannel();
    a.other = b;
    b.other = a;
    _initiatorChannel = a;
    _responderChannel = b;
    return a;
  }

  void openChannels() {
    _initiatorChannel?.open();
    _responderChannel?.open();
  }
}

class _FakePeer implements WebRtcPeer {
  _FakePeer(this.hub);

  final _FakePeerHub hub;

  @override
  void Function(SignalingIceCandidate candidate)? onIceCandidate;
  @override
  void Function(WebRtcDataChannel channel)? onDataChannel;
  @override
  void Function(bool connected)? onConnectionChanged;

  @override
  Future<WebRtcDataChannel> createDataChannel() async => hub.createChannel();

  @override
  Future<SignalingSessionDescription> createOffer() async =>
      const SignalingSessionDescription(type: 'offer', sdp: 'fake-offer');

  @override
  Future<SignalingSessionDescription> createAnswer() async =>
      const SignalingSessionDescription(type: 'answer', sdp: 'fake-answer');

  @override
  Future<void> setLocalDescription(SignalingSessionDescription value) async {}

  @override
  Future<void> setRemoteDescription(SignalingSessionDescription value) async {
    if (value.type != 'offer' && hub.openOnAnswer) {
      hub.openChannels();
      onConnectionChanged?.call(true);
    }
  }

  @override
  Future<void> addCandidate(SignalingIceCandidate candidate) async {}

  @override
  Future<void> close() async {}
}

class _FakeChannel implements WebRtcDataChannel {
  _FakeChannel? other;
  bool _open = false;

  @override
  bool get isOpen => _open;
  @override
  void Function(bool open)? onStateChanged;
  @override
  void Function(Uint8List bytes)? onMessage;

  void open() {
    _open = true;
    onStateChanged?.call(true);
  }

  @override
  Future<void> send(Uint8List bytes) async {
    if (!_open) throw StateError('channel is closed');
    other?.onMessage?.call(Uint8List.fromList(bytes));
  }

  @override
  Future<void> close() async {
    _open = false;
  }
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  if (!condition()) throw TimeoutException('condition was not reached');
}
