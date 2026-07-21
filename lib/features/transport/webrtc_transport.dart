import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'transport.dart';
import 'webrtc/signaling_client.dart';

/// Internet relay transport backed by the Pulse signaling Cloudflare Worker.
///
/// Packets are already encrypted by [PairChannel] before they enter the
/// transport layer, so this fallback relays opaque bytes only. It gives two
/// Android devices a working over-internet channel while the future native
/// WebRTC data-channel implementation can keep using the same signaling API.
class WebRtcTransport implements Transport {
  WebRtcTransport({SignalingClient? signalingClient})
      : _signaling = signalingClient ?? SignalingClient(),
        _clientId = _newClientId();

  final SignalingClient _signaling;
  final String _clientId;

  // ignore: close_sinks
  final _incoming = StreamController<TransportPacket>.broadcast();
  // ignore: close_sinks
  final _state = StreamController<TransportKind>.broadcast();
  bool _connected = false;

  StreamSubscription<SignalingRelayMessage>? _messageSub;
  SignalingSession? _session;

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
    _state.add(TransportKind.searching);
    final signalingToken = reconnectTokens['signalingToken'];
    if (signalingToken == null || signalingToken.isEmpty) {
      debugPrint('[WebRtcTransport] no signalingToken — skipping connect');
      return;
    }

    try {
      _session = await _signaling.createSession(signalingToken);
      _listenMessages(_session!.sessionId, _session!.token);
      _connected = true;
      _state.add(TransportKind.relay);
    } on SignalingException catch (e) {
      debugPrint('[WebRtcTransport] signaling error: $e');
      _state.add(TransportKind.searching);
    } catch (e) {
      debugPrint('[WebRtcTransport] connect failed: $e');
      _state.add(TransportKind.searching);
    }
  }

  @override
  Future<void> send(TransportPacket packet) async {
    final session = _session;
    if (!_connected || session == null) {
      debugPrint('[WebRtcTransport] send() dropped while disconnected');
      return;
    }
    try {
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
    } on Object catch (e) {
      debugPrint('[WebRtcTransport] send failed: $e');
      _connected = false;
      _state.add(TransportKind.searching);
    }
  }

  @override
  Future<void> disconnect() async {
    await _messageSub?.cancel();
    _messageSub = null;
    _session = null;
    _connected = false;
    _state.add(TransportKind.searching);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _listenMessages(
    String sessionId,
    String token,
  ) {
    _messageSub =
        _signaling.messages(sessionId: sessionId, token: token).listen(
      (message) {
        if (message.senderId == _clientId) {
          return;
        }
        _incoming.add(TransportPacket(
          kind: message.kind,
          payload: message.payload,
        ));
      },
      onError: (Object e) {
        debugPrint('[WebRtcTransport] message stream error: $e');
        _connected = false;
        _state.add(TransportKind.searching);
      },
    );
  }

  static String _newClientId() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
