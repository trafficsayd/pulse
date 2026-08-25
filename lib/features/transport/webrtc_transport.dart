import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'transport.dart';
import 'webrtc/ice_servers.dart';
import 'webrtc/native_peer.dart';
import 'webrtc/signaling_client.dart';

/// Internet transport using a native WebRTC DataChannel.
///
/// ICE considers host and STUN candidates first, so normal traffic is direct
/// peer-to-peer. Short-lived TURN servers are also present in the same ICE
/// configuration and libwebrtc selects them automatically only when NAT or a
/// firewall prevents the direct path.
class WebRtcTransport implements Transport {
  WebRtcTransport({
    SignalingClient? signalingClient,
    WebRtcPeerFactory peerFactory = createNativeWebRtcPeer,
    Duration negotiationTimeout = const Duration(seconds: 45),
  })  : _signaling = signalingClient ?? SignalingClient(),
        _peerFactory = peerFactory,
        _negotiationTimeout = negotiationTimeout,
        _clientId = _newId();

  final SignalingClient _signaling;
  final WebRtcPeerFactory _peerFactory;
  final Duration _negotiationTimeout;
  final String _clientId;

  // ignore: close_sinks
  final _incoming = StreamController<TransportPacket>.broadcast();
  // ignore: close_sinks
  final _state = StreamController<TransportKind>.broadcast();

  WebRtcPeer? _peer;
  WebRtcDataChannel? _channel;
  StreamSubscription<SignalingIceCandidate>? _iceSub;
  StreamSubscription<SignalingRelayMessage>? _messageSub;
  String? _messageSessionId;
  bool _connected = false;
  bool _usingHttpRelay = false;
  bool _remoteDescriptionSet = false;
  bool _disconnectRequested = false;
  bool _connecting = false;
  Map<String, String>? _reconnectTokens;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  String? _negotiationId;
  SignalingSession? _session;
  final List<SignalingIceCandidate> _pendingIce = <SignalingIceCandidate>[];

  @override
  TransportKind get kind => TransportKind.relay;

  @override
  bool get isConnected => _connected;

  @override
  Stream<TransportPacket> get incoming => _incoming.stream;

  @override
  Stream<TransportKind> get state => _state.stream;

  @override
  Future<void> connect({required Map<String, String> reconnectTokens}) async {
    _reconnectTokens = Map<String, String>.unmodifiable(reconnectTokens);
    _disconnectRequested = false;
    unawaited(_connectOnce());
  }

  Future<void> _connectOnce() async {
    if (_connecting ||
        _disconnectRequested ||
        (_connected && !_usingHttpRelay)) {
      return;
    }
    final signalingToken = _reconnectTokens?['signalingToken'];
    if (signalingToken == null || signalingToken.isEmpty) {
      _emitSearching();
      return;
    }

    _connecting = true;
    if (!_usingHttpRelay) _emitSearching();
    await _closePeer();

    try {
      final session = await _signaling.createSession(
        signalingToken,
        clientId: _reconnectTokens?['transportClientId']?.isNotEmpty == true
            ? _reconnectTokens!['transportClientId']
            : _clientId,
      );
      _session = session;
      await _activateSignalingRelay(session);
      List<IceServer> remoteTurn = const <IceServer>[];
      try {
        remoteTurn = await _signaling.getTurnIceServers(
          sessionId: session.sessionId,
          token: session.token,
        );
      } on Object catch (error) {
        debugPrint('[WebRtcTransport] TURN credentials unavailable: $error');
      }

      final peer = await _peerFactory(iceServersForSession(remoteTurn));
      if (_disconnectRequested) {
        await peer.close();
        return;
      }
      _peer = peer;
      _wirePeer(peer, session);
      _listenIce(peer, session);

      if (session.isInitiator) {
        await _negotiateAsInitiator(peer, session);
      } else {
        await _negotiateAsResponder(peer, session);
      }

      await _waitForOpen().timeout(_negotiationTimeout);
      _reconnectAttempt = 0;
    } on Object catch (error) {
      debugPrint('[WebRtcTransport] negotiation failed: $error');
      final retryAfter = error is SignalingException ? error.retryAfter : null;
      final session = _session;
      if (session != null && !_disconnectRequested) {
        await _activateSignalingRelay(session);
        _scheduleReconnect(minimumDelay: retryAfter);
      } else {
        _markDisconnected(
          scheduleReconnect: true,
          minimumDelay: retryAfter,
        );
      }
    } finally {
      _connecting = false;
    }
  }

  void _wirePeer(WebRtcPeer peer, SignalingSession session) {
    peer.onIceCandidate = (candidate) {
      unawaited(_signaling
          .postIce(
        sessionId: session.sessionId,
        token: session.token,
        candidate: SignalingIceCandidate(
          candidate: candidate.candidate,
          sdpMid: candidate.sdpMid,
          sdpMLineIndex: candidate.sdpMLineIndex,
          usernameFragment: candidate.usernameFragment,
          senderId: _clientId,
          negotiationId: _negotiationId,
        ),
      )
          .catchError((Object error) {
        debugPrint('[WebRtcTransport] ICE publish failed: $error');
      }));
    };
    peer.onDataChannel = _bindChannel;
    peer.onConnectionChanged = (connected) {
      if (!connected && _connected && !_usingHttpRelay) {
        final current = _session;
        if (current != null) {
          unawaited(_activateSignalingRelay(current));
        } else {
          _markDisconnected(scheduleReconnect: true);
        }
      }
    };
  }

  void _listenIce(WebRtcPeer peer, SignalingSession session) {
    _iceSub = _signaling
        .iceCandidates(sessionId: session.sessionId, token: session.token)
        .where((candidate) => candidate.senderId != _clientId)
        .listen((candidate) {
      if (_negotiationId == null) {
        _pendingIce.add(candidate);
      } else if (candidate.negotiationId != _negotiationId) {
        return;
      } else if (_remoteDescriptionSet) {
        unawaited(peer.addCandidate(candidate).catchError((Object error) {
          debugPrint('[WebRtcTransport] ICE candidate rejected: $error');
        }));
      } else {
        _pendingIce.add(candidate);
      }
    }, onError: (Object error) {
      debugPrint('[WebRtcTransport] ICE polling failed: $error');
    });
  }

  Future<void> _negotiateAsInitiator(
    WebRtcPeer peer,
    SignalingSession session,
  ) async {
    _bindChannel(await peer.createDataChannel());
    final negotiationId = _newId();
    _negotiationId = negotiationId;
    final local = await peer.createOffer();
    await peer.setLocalDescription(local);
    await _signaling.postOffer(
      sessionId: session.sessionId,
      token: session.token,
      offer: SignalingSessionDescription(
        type: 'offer',
        sdp: local.sdp,
        senderId: _clientId,
        negotiationId: negotiationId,
      ),
    );
    final answer = await _pollDescription(
      read: () => _signaling.getAnswer(
        sessionId: session.sessionId,
        token: session.token,
      ),
      accept: (value) =>
          value.senderId != _clientId && value.negotiationId == negotiationId,
    );
    await peer.setRemoteDescription(answer);
    await _remoteDescriptionReady(peer);
  }

  Future<void> _negotiateAsResponder(
    WebRtcPeer peer,
    SignalingSession session,
  ) async {
    final startedAt = DateTime.now().subtract(const Duration(seconds: 10));
    final offer = await _pollDescription(
      read: () => _signaling.getOffer(
        sessionId: session.sessionId,
        token: session.token,
      ),
      accept: (value) =>
          value.senderId != _clientId &&
          value.negotiationId != null &&
          (value.storedAt == null || value.storedAt!.isAfter(startedAt)),
    );
    _negotiationId = offer.negotiationId;
    await peer.setRemoteDescription(offer);
    await _remoteDescriptionReady(peer);
    _bindChannel(await peer.createDataChannel());
    final local = await peer.createAnswer();
    await peer.setLocalDescription(local);
    await _signaling.postAnswer(
      sessionId: session.sessionId,
      token: session.token,
      answer: SignalingSessionDescription(
        type: 'answer',
        sdp: local.sdp,
        senderId: _clientId,
        negotiationId: offer.negotiationId,
      ),
    );
  }

  Future<SignalingSessionDescription> _pollDescription({
    required Future<SignalingSessionDescription?> Function() read,
    required bool Function(SignalingSessionDescription value) accept,
  }) async {
    final deadline = DateTime.now().add(_negotiationTimeout);
    var attempt = 0;
    while (!_disconnectRequested && DateTime.now().isBefore(deadline)) {
      final value = await read();
      if (value != null && accept(value)) return value;
      // Both peers normally share one public IP (home Wi-Fi / mobile NAT).
      // A gently increasing interval keeps the first handshake responsive,
      // yet prevents two slow/reconnecting peers from exhausting the shared
      // signaling budget before either has published its description.
      final delayMs = min(1500, 400 + attempt * 200);
      attempt++;
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
    throw TimeoutException('WebRTC SDP negotiation timed out');
  }

  Future<void> _remoteDescriptionReady(WebRtcPeer peer) async {
    _remoteDescriptionSet = true;
    final pending = _pendingIce
        .where((candidate) => candidate.negotiationId == _negotiationId)
        .toList(growable: false);
    _pendingIce.clear();
    for (final candidate in pending) {
      await peer.addCandidate(candidate);
    }
  }

  void _bindChannel(WebRtcDataChannel channel) {
    debugPrint(
        '[WebRtcTransport] Binding DataChannel (open=${channel.isOpen})');
    _channel = channel;
    channel.onMessage = (bytes) {
      debugPrint(
          '[WebRtcTransport] DataChannel received ${bytes.length} bytes');
      try {
        _incoming.add(_decodePacket(bytes));
      } on Object catch (error, stack) {
        _incoming.addError(error, stack);
      }
    };
    channel.onStateChanged = (open) {
      if (open) {
        _usingHttpRelay = false;
        _connected = true;
        _state.add(TransportKind.relay);
      } else if (_connected && !_usingHttpRelay) {
        final current = _session;
        if (current != null) {
          unawaited(_activateSignalingRelay(current));
        } else {
          _markDisconnected(scheduleReconnect: true);
        }
      }
    };
    if (channel.isOpen) {
      _usingHttpRelay = false;
      _connected = true;
      _state.add(TransportKind.relay);
    }
  }

  Future<void> _waitForOpen() async {
    if (_channel?.isOpen == true) return;
    await state.firstWhere((value) => value == TransportKind.relay);
  }

  @override
  Future<void> send(TransportPacket packet) async {
    final channel = _channel;
    if (!_connected) return;
    if (channel != null && channel.isOpen && !_usingHttpRelay) {
      try {
        await channel.send(_encodePacket(packet));
        return;
      } on Object catch (error) {
        debugPrint('[WebRtcTransport] DataChannel send failed: $error');
        final current = _session;
        if (current != null) await _activateSignalingRelay(current);
      }
    }
    final session = _session;
    if (_usingHttpRelay && session != null) {
      await _signaling.postMessage(
        sessionId: session.sessionId,
        token: session.token,
        message: SignalingRelayMessage(
          senderId: _clientId,
          kind: packet.kind,
          payload: packet.payload,
          storedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> _activateSignalingRelay(SignalingSession session) async {
    if (_disconnectRequested) return;
    if (_messageSessionId != session.sessionId) {
      await _messageSub?.cancel();
      _messageSub = null;
      _messageSessionId = session.sessionId;
    }
    _messageSub ??= _signaling
        .messages(sessionId: session.sessionId, token: session.token)
        .where((message) => message.senderId != _clientId)
        .listen(
      (message) {
        if (!_incoming.isClosed) {
          _incoming.add(TransportPacket(
            kind: message.kind,
            payload: message.payload,
          ));
        }
      },
      onError: (Object error) {
        debugPrint('[WebRtcTransport] signaling relay failed: $error');
        _messageSub = null;
        _messageSessionId = null;
        if (_usingHttpRelay) {
          _markDisconnected(
            scheduleReconnect: true,
            minimumDelay: error is SignalingException ? error.retryAfter : null,
          );
        }
      },
    );
    _usingHttpRelay = true;
    _connected = true;
    if (!_state.isClosed) _state.add(TransportKind.relay);
  }

  void _markDisconnected({
    required bool scheduleReconnect,
    Duration? minimumDelay,
  }) {
    _connected = false;
    _emitSearching();
    if (scheduleReconnect && !_disconnectRequested) {
      _scheduleReconnect(minimumDelay: minimumDelay);
    }
  }

  void _emitSearching() {
    if (!_state.isClosed) _state.add(TransportKind.searching);
  }

  void _scheduleReconnect({Duration? minimumDelay}) {
    if (_reconnectTimer?.isActive == true) return;
    final seconds = min(30, 1 << min(_reconnectAttempt, 5));
    _reconnectAttempt++;
    final exponentialDelay = Duration(seconds: seconds);
    final delay = minimumDelay != null && minimumDelay > exponentialDelay
        ? minimumDelay
        : exponentialDelay;
    _reconnectTimer = Timer(delay, () {
      unawaited(_connectOnce());
    });
  }

  @override
  Future<void> disconnect() async {
    _disconnectRequested = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _messageSub?.cancel();
    _messageSub = null;
    _messageSessionId = null;
    await _closePeer();
    _connected = false;
    _usingHttpRelay = false;
    _session = null;
    _emitSearching();
  }

  Future<void> _closePeer() async {
    await _iceSub?.cancel();
    _iceSub = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) await channel.close();
    final peer = _peer;
    _peer = null;
    if (peer != null) await peer.close();
    _remoteDescriptionSet = false;
    _negotiationId = null;
    _pendingIce.clear();
  }

  static Uint8List _encodePacket(TransportPacket packet) {
    final kind = utf8.encode(packet.kind);
    if (kind.length > 65535) {
      throw ArgumentError.value(packet.kind, 'kind', 'is too long');
    }
    final builder = BytesBuilder(copy: false)
      ..add(<int>[kind.length >> 8, kind.length & 0xff])
      ..add(kind)
      ..add(packet.payload);
    return builder.takeBytes();
  }

  static TransportPacket _decodePacket(Uint8List bytes) {
    if (bytes.length < 2) throw const FormatException('short WebRTC packet');
    final kindLength = (bytes[0] << 8) | bytes[1];
    if (bytes.length < 2 + kindLength) {
      throw const FormatException('truncated WebRTC packet');
    }
    return TransportPacket(
      kind: utf8.decode(bytes.sublist(2, 2 + kindLength)),
      payload: Uint8List.fromList(bytes.sublist(2 + kindLength)),
    );
  }

  static String _newId() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
