import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import 'ice_servers.dart';
import 'signaling_client.dart';

typedef WebRtcPeerFactory = Future<WebRtcPeer> Function(
  List<IceServer> iceServers,
);

abstract interface class WebRtcPeer {
  void Function(SignalingIceCandidate candidate)? onIceCandidate;
  void Function(WebRtcDataChannel channel)? onDataChannel;
  void Function(bool connected)? onConnectionChanged;

  Future<WebRtcDataChannel> createDataChannel();
  Future<SignalingSessionDescription> createOffer();
  Future<SignalingSessionDescription> createAnswer();
  Future<void> setLocalDescription(SignalingSessionDescription description);
  Future<void> setRemoteDescription(SignalingSessionDescription description);
  Future<void> addCandidate(SignalingIceCandidate candidate);
  Future<void> close();
}

abstract interface class WebRtcDataChannel {
  bool get isOpen;
  void Function(bool open)? onStateChanged;
  void Function(Uint8List bytes)? onMessage;

  Future<void> send(Uint8List bytes);
  Future<void> close();
}

Future<WebRtcPeer> createNativeWebRtcPeer(List<IceServer> iceServers) async {
  final rtc.RTCPeerConnection native = await rtc.createPeerConnection(
    <String, dynamic>{
      'iceServers': iceServers.map((server) => server.toMap()).toList(),
      'iceTransportPolicy': 'all',
      'bundlePolicy': 'max-bundle',
    },
  );
  return NativeWebRtcPeer._(native);
}

class NativeWebRtcPeer implements WebRtcPeer {
  NativeWebRtcPeer._(this._native) {
    _native.onIceCandidate = (rtc.RTCIceCandidate candidate) {
      final String? value = candidate.candidate;
      if (value == null || value.isEmpty) return;
      onIceCandidate?.call(SignalingIceCandidate(
        candidate: value,
        sdpMid: candidate.sdpMid,
        sdpMLineIndex: candidate.sdpMLineIndex,
      ));
    };
    _native.onDataChannel = (rtc.RTCDataChannel channel) {
      onDataChannel?.call(NativeWebRtcDataChannel(channel));
    };
    _native.onConnectionState = (rtc.RTCPeerConnectionState state) {
      switch (state) {
        case rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          onConnectionChanged?.call(true);
        case rtc.RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        case rtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        case rtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          onConnectionChanged?.call(false);
        case rtc.RTCPeerConnectionState.RTCPeerConnectionStateNew:
        case rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          break;
      }
    };
  }

  final rtc.RTCPeerConnection _native;

  @override
  void Function(SignalingIceCandidate candidate)? onIceCandidate;
  @override
  void Function(WebRtcDataChannel channel)? onDataChannel;
  @override
  void Function(bool connected)? onConnectionChanged;

  @override
  Future<WebRtcDataChannel> createDataChannel() async {
    final rtc.RTCDataChannelInit init = rtc.RTCDataChannelInit()
      ..ordered = true
      // Both peers open the same out-of-band channel. This avoids relying on
      // the in-band DCEP callback during fast Android reconnects.
      ..negotiated = true
      ..id = 0;
    final channel = await _native.createDataChannel('pulse-events-v1', init);
    return NativeWebRtcDataChannel(channel);
  }

  @override
  Future<SignalingSessionDescription> createOffer() async {
    final description = await _native.createOffer();
    return SignalingSessionDescription(
      type: description.type ?? 'offer',
      sdp: description.sdp ?? '',
    );
  }

  @override
  Future<SignalingSessionDescription> createAnswer() async {
    final description = await _native.createAnswer();
    return SignalingSessionDescription(
      type: description.type ?? 'answer',
      sdp: description.sdp ?? '',
    );
  }

  @override
  Future<void> setLocalDescription(
    SignalingSessionDescription description,
  ) =>
      _native.setLocalDescription(
        rtc.RTCSessionDescription(description.sdp, description.type),
      );

  @override
  Future<void> setRemoteDescription(
    SignalingSessionDescription description,
  ) =>
      _native.setRemoteDescription(
        rtc.RTCSessionDescription(description.sdp, description.type),
      );

  @override
  Future<void> addCandidate(SignalingIceCandidate candidate) =>
      _native.addCandidate(rtc.RTCIceCandidate(
        candidate.candidate,
        candidate.sdpMid,
        candidate.sdpMLineIndex,
      ));

  @override
  Future<void> close() async {
    await _native.close();
    await _native.dispose();
  }
}

class NativeWebRtcDataChannel implements WebRtcDataChannel {
  NativeWebRtcDataChannel(this._native) {
    debugPrint('[WebRtcTransport] DataChannel created: ${_native.state}');
    _native.onDataChannelState = (rtc.RTCDataChannelState state) {
      debugPrint('[WebRtcTransport] DataChannel state: $state');
      onStateChanged?.call(
        state == rtc.RTCDataChannelState.RTCDataChannelOpen,
      );
    };
    _native.onMessage = (rtc.RTCDataChannelMessage message) {
      if (message.isBinary) onMessage?.call(message.binary);
    };
  }

  final rtc.RTCDataChannel _native;

  @override
  void Function(bool open)? onStateChanged;
  @override
  void Function(Uint8List bytes)? onMessage;

  @override
  bool get isOpen =>
      _native.state == rtc.RTCDataChannelState.RTCDataChannelOpen;

  @override
  Future<void> send(Uint8List bytes) =>
      _native.send(rtc.RTCDataChannelMessage.fromBinary(bytes));

  @override
  Future<void> close() => _native.close();
}
