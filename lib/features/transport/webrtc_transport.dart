import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'transport.dart';
import 'webrtc/ice_servers.dart';
import 'webrtc/signaling_client.dart';

/// Real WebRTC data-channel transport (the `relay` tier).
///
/// This replaces the earlier "relay" that shovelled every sealed packet
/// through the Cloudflare Worker. Now the Worker is used **only** to broker
/// the SDP offer/answer during setup; once the [RTCDataChannel] opens, sealed
/// packets travel **peer-to-peer over DTLS-SRTP** and never touch the Worker.
///
/// Design notes (why it looks the way it does):
///
///  * **Vanilla (non-trickle) ICE.** The Worker's ICE store is a single shared
///    append-only list with no per-sender attribution, so a trickle-ICE poll
///    would feed a peer its own candidates back. Instead we wait for local ICE
///    gathering to finish and ship the *complete* SDP (candidates embedded)
///    through the existing `offer`/`answer` slots — one round trip, no
///    ambiguity.
///
///  * **Self-contained role assignment.** Both peers reconnect with the *same*
///    `signalingToken`/`connectionId`, so nothing distinguishes them a priori.
///    Each posts a random 128-bit claim to the (otherwise-unused-in-vanilla)
///    ICE endpoint; the larger claim id becomes the offerer. Deterministic,
///    glare-free, and needs no extra pairing state.
///
///  * **Automatic relay fallback.** If the data channel cannot open within
///    [p2pTimeout] (e.g. both peers behind symmetric NATs and no TURN
///    credentials compiled in), the transport transparently falls back to
///    relaying sealed packets over the same signaling session — so the app
///    stays connected even when P2P is impossible. Payloads are already
///    end-to-end encrypted either way, so the Worker never sees plaintext.
///
/// Payloads are opaque: [PairChannel] seals them before they reach here.
class WebRtcTransport implements Transport {
  WebRtcTransport({
    SignalingClient? signalingClient,
    List<IceServer> iceServers = kIceServers,
    bool allowRelayFallback = true,
    Duration p2pTimeout = const Duration(seconds: 12),
    Duration roleTimeout = const Duration(seconds: 15),
    Random? random,
  })  : _signaling = signalingClient ?? SignalingClient(),
        _iceServers = iceServers,
        _allowRelayFallback = allowRelayFallback,
        _p2pTimeout = p2pTimeout,
        _roleTimeout = roleTimeout,
        _clientId = _newClientId(random ?? Random.secure());

  final SignalingClient _signaling;
  final List<IceServer> _iceServers;
  final bool _allowRelayFallback;
  final Duration _p2pTimeout;
  final Duration _roleTimeout;
  final String _clientId;

  /// Prefix marking an ICE-endpoint entry as a role-negotiation claim rather
  /// than a real ICE candidate (we never post real candidates — see class doc).
  static const String _kRoleClaimPrefix = 'pulse-role:';

  /// Message framing for the data channel: `{"k":"<kind>","p":"<base64>"}` —
  /// identical to the LAN transport so both sides speak one wire format.
  // ignore: close_sinks
  final _incoming = StreamController<TransportPacket>.broadcast();
  // ignore: close_sinks
  final _state = StreamController<TransportKind>.broadcast();

  bool _connected = false;
  bool _disposed = false;

  /// True once we've committed to relaying over the Worker (P2P gave up).
  bool _relayMode = false;

  SignalingSession? _session;
  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  StreamSubscription<SignalingIceCandidate>? _roleSub;
  StreamSubscription<SignalingRelayMessage>? _relaySub;
  Timer? _p2pDeadline;

  @override
  TransportKind get kind => TransportKind.relay;

  @override
  bool get isConnected => _connected;

  @override
  Stream<TransportPacket> get incoming => _incoming.stream;

  @override
  Stream<TransportKind> get state => _state.stream;

  /// Pure, testable role rule: the lexicographically larger client id offers.
  /// Ties (same id) are astronomically unlikely with 128 bits; treated as
  /// "not offerer" so a degenerate collision fails closed rather than
  /// deadlocking two offerers.
  static bool isOfferer(String myClientId, String peerClientId) =>
      myClientId.compareTo(peerClientId) > 0;

  /// Extract the claim id from a role-claim ICE entry, or null if [candidate]
  /// is not a role claim.
  static String? parseRoleClaim(String candidate) =>
      candidate.startsWith(_kRoleClaimPrefix)
          ? candidate.substring(_kRoleClaimPrefix.length)
          : null;

  @override
  Future<void> connect({required Map<String, String> reconnectTokens}) async {
    _state.add(TransportKind.searching);
    _relayMode = false;
    final signalingToken = reconnectTokens['signalingToken'];
    if (signalingToken == null || signalingToken.isEmpty) {
      if (kDebugMode) {
        debugPrint('[WebRtcTransport] no signalingToken — skipping connect');
      }
      return;
    }

    try {
      final session = await _signaling.createSession(signalingToken);
      _session = session;

      final peerId = await _negotiateRole(session);
      if (_disposed) return;
      if (peerId == null) {
        // No peer showed up within the window — let the manager retry later.
        _state.add(TransportKind.searching);
        return;
      }
      final offerer = isOfferer(_clientId, peerId);

      await _startPeerConnection(session, offerer: offerer);
    } on SignalingException catch (e) {
      // SECURITY (§4/§14 zero-logging): never log token/session values.
      if (kDebugMode) debugPrint('[WebRtcTransport] signaling error: $e');
      await _fallbackOrFail();
    } catch (e) {
      if (kDebugMode) debugPrint('[WebRtcTransport] connect failed: $e');
      await _fallbackOrFail();
    }
  }

  // ---------------------------------------------------------------------------
  // Role negotiation (over the ICE claim board)
  // ---------------------------------------------------------------------------

  /// Post our random claim and wait until we observe the peer's claim.
  /// Returns the peer's client id, or null on timeout (no peer present).
  Future<String?> _negotiateRole(SignalingSession session) async {
    await _signaling.postIce(
      sessionId: session.sessionId,
      token: session.token,
      candidate: SignalingIceCandidate(
        candidate: '$_kRoleClaimPrefix$_clientId',
      ),
    );

    final completer = Completer<String?>();
    _roleSub = _signaling
        .iceCandidates(sessionId: session.sessionId, token: session.token)
        .listen(
      (entry) {
        final id = parseRoleClaim(entry.candidate);
        if (id == null || id == _clientId) return; // skip non-claims and ours
        if (!completer.isCompleted) completer.complete(id);
      },
      onError: (Object _) {
        if (!completer.isCompleted) completer.complete(null);
      },
    );

    final peerId = await completer.future
        .timeout(_roleTimeout, onTimeout: () => null);
    await _roleSub?.cancel();
    _roleSub = null;
    return peerId;
  }

  // ---------------------------------------------------------------------------
  // WebRTC setup
  // ---------------------------------------------------------------------------

  Future<void> _startPeerConnection(
    SignalingSession session, {
    required bool offerer,
  }) async {
    final pc = await createPeerConnection(<String, dynamic>{
      'iceServers': _iceServers.map((s) => s.toMap()).toList(),
      'sdpSemantics': 'unified-plan',
    });
    _pc = pc;

    pc.onConnectionState = (RTCPeerConnectionState s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        // P2P dropped — surface as searching so the manager can react.
        if (!_relayMode) _markSearching();
      }
    };

    if (offerer) {
      final channel = await pc.createDataChannel(
        'pulse',
        RTCDataChannelInit()..ordered = true,
      );
      _attachDataChannel(channel);

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await _waitForIceGathering(pc);
      if (_disposed) return;
      final local = await pc.getLocalDescription();
      await _signaling.postOffer(
        sessionId: session.sessionId,
        token: session.token,
        offer: SignalingSessionDescription(
          type: 'offer',
          sdp: local?.sdp ?? offer.sdp ?? '',
        ),
      );
      final answer = await _pollDescription(
        () => _signaling.getAnswer(
          sessionId: session.sessionId,
          token: session.token,
        ),
      );
      if (_disposed) return;
      if (answer == null) {
        await _fallbackOrFail();
        return;
      }
      await pc.setRemoteDescription(
        RTCSessionDescription(answer.sdp, answer.type),
      );
    } else {
      pc.onDataChannel = _attachDataChannel;

      final offer = await _pollDescription(
        () => _signaling.getOffer(
          sessionId: session.sessionId,
          token: session.token,
        ),
      );
      if (_disposed) return;
      if (offer == null) {
        await _fallbackOrFail();
        return;
      }
      await pc.setRemoteDescription(
        RTCSessionDescription(offer.sdp, offer.type),
      );
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await _waitForIceGathering(pc);
      if (_disposed) return;
      final local = await pc.getLocalDescription();
      await _signaling.postAnswer(
        sessionId: session.sessionId,
        token: session.token,
        answer: SignalingSessionDescription(
          type: 'answer',
          sdp: local?.sdp ?? answer.sdp ?? '',
        ),
      );
    }

    // Arm the P2P deadline: if the data channel is not open by then, fall
    // back to relaying over the Worker so the user is never left offline.
    _p2pDeadline = Timer(_p2pTimeout, () {
      if (!_connected && !_disposed) {
        if (kDebugMode) {
          debugPrint('[WebRtcTransport] data channel not open — relay fallback');
        }
        unawaited(_fallbackOrFail());
      }
    });
  }

  void _attachDataChannel(RTCDataChannel channel) {
    _dc = channel;
    channel.onDataChannelState = (RTCDataChannelState s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen) {
        _p2pDeadline?.cancel();
        _relayMode = false;
        _connected = true;
        _state.add(TransportKind.relay);
      } else if (s == RTCDataChannelState.RTCDataChannelClosed) {
        if (!_relayMode) _markSearching();
      }
    };
    channel.onMessage = (RTCDataChannelMessage message) {
      final packet = _decodeFrame(message);
      if (packet != null) _incoming.add(packet);
    };
  }

  /// Wait until ICE gathering completes (vanilla ICE), bounded so a stuck
  /// gathering can't hang setup forever.
  Future<void> _waitForIceGathering(RTCPeerConnection pc) async {
    if (pc.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }
    final completer = Completer<void>();
    pc.onIceGatheringState = (RTCIceGatheringState s) {
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !completer.isCompleted) {
        completer.complete();
      }
    };
    await completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {},
    );
  }

  /// Poll a signaling GET (offer/answer) until it returns a value, the peer
  /// timeout elapses, or the transport is disposed.
  Future<SignalingSessionDescription?> _pollDescription(
    Future<SignalingSessionDescription?> Function() get,
  ) async {
    final deadline = DateTime.now().add(_roleTimeout);
    while (!_disposed && DateTime.now().isBefore(deadline)) {
      final value = await get();
      if (value != null) return value;
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Relay fallback (Worker-brokered, still end-to-end encrypted)
  // ---------------------------------------------------------------------------

  Future<void> _fallbackOrFail() async {
    final session = _session;
    if (!_allowRelayFallback || session == null || _disposed) {
      _markSearching();
      return;
    }
    _p2pDeadline?.cancel();
    await _teardownPeer();
    _relayMode = true;
    _relaySub = _signaling
        .messages(sessionId: session.sessionId, token: session.token)
        .listen(
      (message) {
        if (message.senderId == _clientId) return;
        _incoming.add(
          TransportPacket(kind: message.kind, payload: message.payload),
        );
      },
      onError: (Object e) {
        if (kDebugMode) debugPrint('[WebRtcTransport] relay stream error: $e');
        _markSearching();
      },
    );
    _connected = true;
    _state.add(TransportKind.relay);
  }

  @override
  Future<void> send(TransportPacket packet) async {
    if (!_connected || _disposed) return;
    try {
      if (_relayMode) {
        final session = _session;
        if (session == null) return;
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
      } else {
        final dc = _dc;
        if (dc == null) return;
        await dc.send(RTCDataChannelMessage(_encodeFrame(packet)));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[WebRtcTransport] send failed: $e');
      _markSearching();
    }
  }

  @override
  Future<void> disconnect() async {
    _disposed = true;
    _p2pDeadline?.cancel();
    await _roleSub?.cancel();
    _roleSub = null;
    await _relaySub?.cancel();
    _relaySub = null;
    await _teardownPeer();
    _session = null;
    _connected = false;
    _relayMode = false;
    _state.add(TransportKind.searching);
  }

  Future<void> _teardownPeer() async {
    try {
      await _dc?.close();
    } catch (_) {}
    _dc = null;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
  }

  void _markSearching() {
    _connected = false;
    if (!_state.isClosed) _state.add(TransportKind.searching);
  }

  // ---------------------------------------------------------------------------
  // Wire framing
  // ---------------------------------------------------------------------------

  static String _encodeFrame(TransportPacket packet) => jsonEncode(
        <String, Object?>{
          'k': packet.kind,
          'p': base64Encode(packet.payload),
        },
      );

  static TransportPacket? _decodeFrame(RTCDataChannelMessage message) {
    if (message.isBinary) return null; // we only speak the JSON text frame
    try {
      final json = jsonDecode(message.text) as Map<String, Object?>;
      final kind = json['k'];
      final payload = json['p'];
      if (kind is! String || payload is! String) return null;
      return TransportPacket(
        kind: kind,
        payload: Uint8List.fromList(base64Decode(payload)),
      );
    } catch (_) {
      return null;
    }
  }

  static String _newClientId(Random random) =>
      List<int>.generate(16, (_) => random.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
}
