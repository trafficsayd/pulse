import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// Compile-time-configurable signaling Worker base URL.
///
/// Override at build time with `--dart-define=SIGNALING_BASE_URL=...`.
const String _kSignalingBaseUrl = String.fromEnvironment(
  'SIGNALING_BASE_URL',
  defaultValue: 'https://pulse-signaling.example.workers.dev',
);

/// Default per-call HTTP timeouts. POSTs are short because the Worker is
/// supposed to write to KV and return immediately; the ICE long-poll GET is
/// 30s so it can absorb the Worker's 25s long-poll plus a little jitter.
const Duration _kDefaultPostTimeout = Duration(seconds: 5);
const Duration _kDefaultShortGetTimeout = Duration(seconds: 5);
const Duration _kDefaultLongPollTimeout = Duration(seconds: 30);

/// Result of `POST /session`. Mirrors the Worker's wire shape exactly.
@immutable
class SignalingSession {
  const SignalingSession({
    required this.sessionId,
    required this.token,
    required this.expiresAt,
  });

  factory SignalingSession.fromJson(Map<String, Object?> json) {
    final Object? sessionId = json['sessionId'];
    final Object? token = json['token'];
    final Object? expiresAt = json['expiresAt'];
    if (sessionId is! String || token is! String || expiresAt is! num) {
      throw const FormatException('malformed signaling session response');
    }
    return SignalingSession(
      sessionId: sessionId,
      token: token,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt.toInt()),
    );
  }

  final String sessionId;
  final String token;
  final DateTime expiresAt;
}

/// Lightweight SDP description that we own end-to-end inside Pulse.
///
/// Once Track F3 lands `flutter_webrtc`, we expose conversions to / from
/// `RTCSessionDescription` instead of replacing this type — keeping the
/// signaling client decoupled from the native WebRTC plugin makes the
/// client testable without a real `MediaStream` available.
@immutable
class SignalingSessionDescription {
  const SignalingSessionDescription({
    required this.type,
    required this.sdp,
  });

  factory SignalingSessionDescription.fromJson(Map<String, Object?> json) {
    final Object? type = json['type'];
    final Object? sdp = json['sdp'];
    if (type is! String || sdp is! String) {
      throw const FormatException('malformed SDP payload');
    }
    return SignalingSessionDescription(type: type, sdp: sdp);
  }

  /// `'offer'` or `'answer'`.
  final String type;

  /// Raw SDP string.
  final String sdp;

  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        'sdp': sdp,
      };
}

/// Trickle-ICE candidate envelope.
@immutable
class SignalingIceCandidate {
  const SignalingIceCandidate({
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
    this.usernameFragment,
  });

  factory SignalingIceCandidate.fromJson(Map<String, Object?> json) {
    final Object? candidate = json['candidate'];
    if (candidate is! String) {
      throw const FormatException('malformed ICE candidate');
    }
    final Object? sdpMid = json['sdpMid'];
    final Object? sdpMLineIndex = json['sdpMLineIndex'];
    final Object? ufrag = json['usernameFragment'];
    return SignalingIceCandidate(
      candidate: candidate,
      sdpMid: sdpMid is String ? sdpMid : null,
      sdpMLineIndex: sdpMLineIndex is num ? sdpMLineIndex.toInt() : null,
      usernameFragment: ufrag is String ? ufrag : null,
    );
  }

  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
  final String? usernameFragment;

  Map<String, Object?> toJson() => <String, Object?>{
        'candidate': candidate,
        if (sdpMid != null) 'sdpMid': sdpMid,
        if (sdpMLineIndex != null) 'sdpMLineIndex': sdpMLineIndex,
        if (usernameFragment != null) 'usernameFragment': usernameFragment,
      };
}

/// End-to-end encrypted application packet carried by the signaling relay.
@immutable
class SignalingRelayMessage {
  const SignalingRelayMessage({
    required this.senderId,
    required this.kind,
    required this.payload,
    required this.storedAt,
  });

  factory SignalingRelayMessage.fromJson(Map<String, Object?> json) {
    final Object? senderId = json['senderId'];
    final Object? kind = json['kind'];
    final Object? payload = json['payload'];
    final Object? storedAt = json['storedAt'];
    if (senderId is! String ||
        kind is! String ||
        payload is! String ||
        storedAt is! num) {
      throw const FormatException('malformed relay message');
    }
    return SignalingRelayMessage(
      senderId: senderId,
      kind: kind,
      payload: Uint8List.fromList(base64Decode(payload)),
      storedAt: DateTime.fromMillisecondsSinceEpoch(storedAt.toInt()),
    );
  }

  final String senderId;
  final String kind;
  final Uint8List payload;
  final DateTime storedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'senderId': senderId,
        'kind': kind,
        'payload': base64Encode(payload),
      };
}

/// Anything the signaling client can fail with.
class SignalingException implements Exception {
  const SignalingException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => statusCode == null
      ? 'SignalingException: $message'
      : 'SignalingException($statusCode): $message';
}

/// Thin HTTP client that talks to the Pulse signaling Cloudflare Worker.
///
/// One instance per session is typical, but the client is stateless apart
/// from the bearer token, so it is safe to reuse across sessions if the
/// caller updates the token between calls.
class SignalingClient {
  SignalingClient({
    http.Client? httpClient,
    String? baseUrl,
    Duration postTimeout = _kDefaultPostTimeout,
    Duration shortGetTimeout = _kDefaultShortGetTimeout,
    Duration longPollTimeout = _kDefaultLongPollTimeout,
  })  : _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _baseUrl = _normaliseBase(baseUrl ?? _kSignalingBaseUrl),
        _postTimeout = postTimeout,
        _shortGetTimeout = shortGetTimeout,
        _longPollTimeout = longPollTimeout;

  final http.Client _http;
  final bool _ownsClient;
  final Uri _baseUrl;
  final Duration _postTimeout;
  final Duration _shortGetTimeout;
  final Duration _longPollTimeout;

  static Uri _normaliseBase(String raw) {
    final Uri parsed = Uri.parse(raw);
    if (!parsed.hasScheme ||
        (parsed.scheme != 'http' && parsed.scheme != 'https')) {
      throw ArgumentError.value(raw, 'baseUrl', 'must be http or https');
    }
    // Drop any trailing slash so `/session` concatenation is unambiguous.
    final String pathNoSlash = parsed.path.endsWith('/')
        ? parsed.path.substring(0, parsed.path.length - 1)
        : parsed.path;
    return parsed.replace(path: pathNoSlash);
  }

  Uri _resolve(String path, {Map<String, String>? query}) {
    final String full = '${_baseUrl.path}$path';
    return _baseUrl.replace(path: full, queryParameters: query);
  }

  Map<String, String> _authHeaders(String token) => <String, String>{
        'content-type': 'application/json; charset=utf-8',
        'authorization': 'Bearer $token',
      };

  /// `POST /session` — create a new signaling session.
  Future<SignalingSession> createSession(String pairingCode) async {
    final Uri uri = _resolve('/session');
    final http.Response res = await _http
        .post(
          uri,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8'
          },
          body: jsonEncode(<String, Object?>{'pairingCode': pairingCode}),
        )
        .timeout(_postTimeout);
    if (res.statusCode != 201) {
      throw SignalingException(
        'createSession failed: ${res.body}',
        statusCode: res.statusCode,
      );
    }
    return SignalingSession.fromJson(
      jsonDecode(res.body) as Map<String, Object?>,
    );
  }

  /// `POST /session/:id/offer` — store an SDP offer (and optional initial
  /// ICE candidates) for the peer to pick up.
  Future<void> postOffer({
    required String sessionId,
    required String token,
    required SignalingSessionDescription offer,
    List<SignalingIceCandidate>? initialIce,
  }) async {
    final Uri uri = _resolve('/session/$sessionId/offer');
    final Map<String, Object?> body = <String, Object?>{
      'sdp': offer.sdp,
      if (initialIce != null && initialIce.isNotEmpty)
        'ice': initialIce.map((SignalingIceCandidate c) => c.toJson()).toList(),
    };
    final http.Response res = await _http
        .post(uri, headers: _authHeaders(token), body: jsonEncode(body))
        .timeout(_postTimeout);
    if (res.statusCode != 200) {
      throw SignalingException(
        'postOffer failed: ${res.body}',
        statusCode: res.statusCode,
      );
    }
  }

  /// `GET /session/:id/offer` — read the stored offer, or `null` if the
  /// other peer has not posted one yet.
  Future<SignalingSessionDescription?> getOffer({
    required String sessionId,
    required String token,
  }) async {
    final Uri uri = _resolve('/session/$sessionId/offer');
    final http.Response res = await _http
        .get(uri, headers: _authHeaders(token))
        .timeout(_shortGetTimeout);
    if (res.statusCode == 204) {
      return null;
    }
    if (res.statusCode != 200) {
      throw SignalingException(
        'getOffer failed: ${res.body}',
        statusCode: res.statusCode,
      );
    }
    return SignalingSessionDescription.fromJson(
      jsonDecode(res.body) as Map<String, Object?>,
    );
  }

  /// `POST /session/:id/answer` — store an SDP answer for the offering peer.
  Future<void> postAnswer({
    required String sessionId,
    required String token,
    required SignalingSessionDescription answer,
    List<SignalingIceCandidate>? initialIce,
  }) async {
    final Uri uri = _resolve('/session/$sessionId/answer');
    final Map<String, Object?> body = <String, Object?>{
      'sdp': answer.sdp,
      if (initialIce != null && initialIce.isNotEmpty)
        'ice': initialIce.map((SignalingIceCandidate c) => c.toJson()).toList(),
    };
    final http.Response res = await _http
        .post(uri, headers: _authHeaders(token), body: jsonEncode(body))
        .timeout(_postTimeout);
    if (res.statusCode != 200) {
      throw SignalingException(
        'postAnswer failed: ${res.body}',
        statusCode: res.statusCode,
      );
    }
  }

  /// `GET /session/:id/answer` — read the stored answer, or `null` if the
  /// other peer has not posted one yet.
  Future<SignalingSessionDescription?> getAnswer({
    required String sessionId,
    required String token,
  }) async {
    final Uri uri = _resolve('/session/$sessionId/answer');
    final http.Response res = await _http
        .get(uri, headers: _authHeaders(token))
        .timeout(_shortGetTimeout);
    if (res.statusCode == 204) {
      return null;
    }
    if (res.statusCode != 200) {
      throw SignalingException(
        'getAnswer failed: ${res.body}',
        statusCode: res.statusCode,
      );
    }
    return SignalingSessionDescription.fromJson(
      jsonDecode(res.body) as Map<String, Object?>,
    );
  }

  /// `POST /session/:id/ice` — append a trickle-ICE candidate.
  Future<void> postIce({
    required String sessionId,
    required String token,
    required SignalingIceCandidate candidate,
  }) async {
    final Uri uri = _resolve('/session/$sessionId/ice');
    final http.Response res = await _http
        .post(uri,
            headers: _authHeaders(token), body: jsonEncode(candidate.toJson()))
        .timeout(_postTimeout);
    if (res.statusCode != 200) {
      throw SignalingException(
        'postIce failed: ${res.body}',
        statusCode: res.statusCode,
      );
    }
  }

  /// Long-poll ICE candidates as they trickle in from the peer.
  ///
  /// The stream emits each new candidate exactly once, ordered by the
  /// Worker's append cursor. Cancelling the subscription stops the loop.
  Stream<SignalingIceCandidate> iceCandidates({
    required String sessionId,
    required String token,
  }) {
    // The controller is closed by `_runIcePoll` once the loop terminates
    // (either via cancellation or an error). The `cancel_subscriptions` and
    // `close_sinks` lints are happy because every code path through the
    // pump closes the controller.
    // ignore: close_sinks
    final StreamController<SignalingIceCandidate> controller =
        StreamController<SignalingIceCandidate>();
    bool stopped = false;
    controller.onCancel = () async {
      stopped = true;
    };
    controller.onListen = () {
      unawaited(_runIcePoll(
        controller: controller,
        sessionId: sessionId,
        token: token,
        isStopped: () => stopped,
      ));
    };
    return controller.stream;
  }

  /// `POST /session/:id/messages` — append one encrypted app packet.
  Future<void> postMessage({
    required String sessionId,
    required String token,
    required SignalingRelayMessage message,
  }) async {
    final Uri uri = _resolve('/session/$sessionId/messages');
    final http.Response res = await _http
        .post(uri,
            headers: _authHeaders(token), body: jsonEncode(message.toJson()))
        .timeout(_postTimeout);
    if (res.statusCode != 200) {
      throw SignalingException(
        'postMessage failed: ${res.body}',
        statusCode: res.statusCode,
      );
    }
  }

  /// Long-poll encrypted application packets from the signaling relay.
  Stream<SignalingRelayMessage> messages({
    required String sessionId,
    required String token,
  }) {
    // ignore: close_sinks
    final StreamController<SignalingRelayMessage> controller =
        StreamController<SignalingRelayMessage>();
    bool stopped = false;
    controller.onCancel = () async {
      stopped = true;
    };
    controller.onListen = () {
      unawaited(_runMessagePoll(
        controller: controller,
        sessionId: sessionId,
        token: token,
        isStopped: () => stopped,
      ));
    };
    return controller.stream;
  }

  Future<void> _runIcePoll({
    required StreamController<SignalingIceCandidate> controller,
    required String sessionId,
    required String token,
    required bool Function() isStopped,
  }) async {
    int cursor = 0;
    try {
      while (!isStopped()) {
        final Uri uri = _resolve(
          '/session/$sessionId/ice',
          query: <String, String>{'since': cursor.toString()},
        );
        late http.Response res;
        try {
          res = await _http
              .get(uri, headers: _authHeaders(token))
              .timeout(_longPollTimeout);
        } on TimeoutException {
          // The Worker holds the request open for ~25s; we wrap that in a
          // 30s client timeout. On client-side timeout we simply retry with
          // the same cursor.
          continue;
        }
        if (isStopped()) {
          return;
        }
        if (res.statusCode == 204) {
          // No new candidates in this long-poll window — loop and try again.
          continue;
        }
        if (res.statusCode != 200) {
          controller.addError(
            SignalingException(
              'iceCandidates failed: ${res.body}',
              statusCode: res.statusCode,
            ),
          );
          return;
        }
        final Map<String, Object?> payload =
            jsonDecode(res.body) as Map<String, Object?>;
        final Object? candidates = payload['candidates'];
        final Object? next = payload['cursor'];
        if (candidates is! List || next is! num) {
          controller.addError(
            const SignalingException('malformed ICE long-poll payload'),
          );
          return;
        }
        for (final Object? c in candidates) {
          if (c is Map<String, Object?>) {
            controller.add(SignalingIceCandidate.fromJson(c));
          }
        }
        cursor = next.toInt();
      }
    } finally {
      if (!controller.isClosed) {
        await controller.close();
      }
    }
  }

  Future<void> _runMessagePoll({
    required StreamController<SignalingRelayMessage> controller,
    required String sessionId,
    required String token,
    required bool Function() isStopped,
  }) async {
    int cursor = 0;
    try {
      while (!isStopped()) {
        final Uri uri = _resolve(
          '/session/$sessionId/messages',
          query: <String, String>{'since': cursor.toString()},
        );
        late http.Response res;
        try {
          res = await _http
              .get(uri, headers: _authHeaders(token))
              .timeout(_longPollTimeout);
        } on TimeoutException {
          continue;
        }
        if (isStopped()) {
          return;
        }
        if (res.statusCode == 204) {
          continue;
        }
        if (res.statusCode != 200) {
          controller.addError(
            SignalingException(
              'messages failed: ${res.body}',
              statusCode: res.statusCode,
            ),
          );
          return;
        }
        final Map<String, Object?> payload =
            jsonDecode(res.body) as Map<String, Object?>;
        final Object? messages = payload['messages'];
        final Object? next = payload['cursor'];
        if (messages is! List || next is! num) {
          controller.addError(
            const SignalingException('malformed message long-poll payload'),
          );
          return;
        }
        for (final Object? m in messages) {
          if (m is Map<String, Object?>) {
            controller.add(SignalingRelayMessage.fromJson(m));
          }
        }
        cursor = next.toInt();
      }
    } finally {
      if (!controller.isClosed) {
        await controller.close();
      }
    }
  }

  /// Release the underlying HTTP client. Safe to call multiple times.
  void close() {
    if (_ownsClient) {
      _http.close();
    }
  }
}
