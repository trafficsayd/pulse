import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'aes_gcm_sealer.dart';
import 'nonce_counter.dart';

/// Abstraction over the underlying transport (BLE, mDNS/LAN, WebRTC).
///
/// [PairChannel] does not care which physical transport is in use — it
/// only needs an opaque bidirectional byte stream. This is the seam the
/// transport layer (`lib/features/transport/`) will plug into in a
/// later sprint.
abstract interface class RawByteChannel {
  /// Inbound encrypted packets straight off the wire.
  Stream<Uint8List> get incoming;

  /// Send a single encrypted packet down the wire.
  Future<void> send(Uint8List bytes);

  /// Best-effort graceful close.
  Future<void> close();
}

/// A frame that has been authenticated and decrypted by [PairChannel].
///
/// Payload bytes are whatever the higher layers (mode events, sneak-in
/// signals, etc.) wanted to send. The nonce counter is exposed so
/// debuggers / analyzers can verify monotonicity without re-reading
/// the storage.
class PulsePacket {
  PulsePacket({required this.payload, required this.nonceCounter});

  final Uint8List payload;
  final int nonceCounter;
}

/// Sealed packet layer that sits between a raw byte transport and the
/// rest of the app.
///
/// Each direction has its own monotonic [NonceCounter] so the two peers
/// can never collide on a 96-bit AES-GCM nonce, even across app
/// restarts.
class PairChannel {
  PairChannel({
    required RawByteChannel transport,
    required SecretKey key,
    required NonceCounter outboundCounter,
    required NonceCounter inboundCounter,
    AesGcmSealer? sealer,
  })  : _transport = transport,
        _key = key,
        _outbound = outboundCounter,
        _inbound = inboundCounter,
        _sealer = sealer ?? AesGcmSealer();

  final RawByteChannel _transport;
  final SecretKey _key;
  final NonceCounter _outbound;
  final NonceCounter _inbound;
  final AesGcmSealer _sealer;

  final _controller = StreamController<PulsePacket>.broadcast();
  StreamSubscription<Uint8List>? _sub;
  bool _started = false;

  /// Decrypted, authenticated packets in arrival order.
  Stream<PulsePacket> get incoming => _controller.stream;

  /// Errors that happened while opening a packet (replay, tamper, MAC
  /// failure, etc.). The stream is kept open so the UI can surface a
  /// "secure channel desynced" banner.
  Stream<Object> get errors => _errors.stream;
  final _errors = StreamController<Object>.broadcast();

  /// Wire up the transport and warm up persisted nonce counters.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _outbound.restore();
    await _inbound.restore();
    _sub = _transport.incoming.listen(_onPacket, onError: _errors.add);
  }

  Future<void> _onPacket(Uint8List bytes) async {
    try {
      final expected = await _inbound.peek();
      final plain = await _sealer.open(
        bytes,
        key: _key,
        expectedNonceCounter: expected,
      );
      // Advance the inbound counter only after a successful open so a
      // tampered packet cannot push us out of sync with the peer.
      await _inbound.next();
      _controller.add(
        PulsePacket(payload: plain, nonceCounter: expected),
      );
    } catch (e) {
      _errors.add(e);
    }
  }

  /// Seal [plaintext] with the next outbound counter and hand it to the
  /// transport.
  Future<void> send(Uint8List plaintext) async {
    final counter = await _outbound.next();
    final packet = await _sealer.seal(
      plaintext,
      key: _key,
      nonceCounter: counter,
    );
    await _transport.send(packet);
  }

  Future<void> close() async {
    await _sub?.cancel();
    await _transport.close();
    await _controller.close();
    await _errors.close();
  }
}
