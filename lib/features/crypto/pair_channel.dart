import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'aes_gcm_sealer.dart';
import 'nonce_counter.dart';
import 'pair_channel_nonce_domains.dart';

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
/// Each direction has a disjoint AES-GCM nonce namespace and its own monotonic
/// [NonceCounter]. This prevents the two peers from ever using the same
/// key/nonce pair, including when both local counters start at one.
class PairChannel {
  PairChannel({
    required RawByteChannel transport,
    required SecretKey key,
    required PairChannelNonceDomains nonceDomains,
    required NonceCounter outboundCounter,
    required NonceCounter inboundCounter,
    AesGcmSealer? sealer,
  })  : _transport = transport,
        _key = key,
        _nonceDomains = nonceDomains,
        _outbound = outboundCounter,
        _inbound = inboundCounter,
        _sealer = sealer ?? AesGcmSealer();

  final RawByteChannel _transport;
  final SecretKey _key;
  final PairChannelNonceDomains _nonceDomains;
  final NonceCounter _outbound;
  final NonceCounter _inbound;
  final AesGcmSealer _sealer;

  final _controller = StreamController<PulsePacket>.broadcast();
  StreamSubscription<Uint8List>? _sub;
  bool _started = false;
  Future<void> _packetQueue = Future<void>.value();
  Future<void> _sendQueue = Future<void>.value();

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

  void _onPacket(Uint8List bytes) {
    _packetQueue = _packetQueue.then((_) => _processPacket(bytes));
  }

  Future<void> _processPacket(Uint8List bytes) async {
    try {
      final expected = await _inbound.peek();
      if (bytes.length < AesGcmSealer.nonceLength + AesGcmSealer.macLength) {
        throw const FormatException('AES-GCM packet too short');
      }
      final packetCounter = AesGcmSealer.counterFromNonce(
        Uint8List.sublistView(bytes, 0, AesGcmSealer.nonceLength),
      );
      if (!_nonceDomains.acceptsInboundWireCounter(packetCounter)) {
        throw StateError('AES-GCM nonce belongs to the wrong direction');
      }
      if (packetCounter < expected) {
        throw StateError('AES-GCM replayed or stale nonce counter');
      }
      final plain = await _sealer.open(
        bytes,
        key: _key,
        expectedNonceCounter: packetCounter,
      );
      // Advance only after successful authentication. A forward gap means a
      // transient mode event was lost during transport handover; mode events
      // are intentionally ephemeral, so the secure channel must continue.
      await _inbound.advanceTo(packetCounter, reservationSize: 64);
      _controller.add(
        PulsePacket(
          payload: plain,
          nonceCounter: _nonceDomains.logicalCounter(packetCounter),
        ),
      );
    } catch (e) {
      _errors.add(e);
    }
  }

  /// Seal [plaintext] with the next outbound counter and hand it to the
  /// transport.
  ///
  /// Gesture modes can enqueue dozens of points in one frame. Serialize the
  /// whole counter → seal → transport sequence so concurrent, intentionally
  /// unawaited sends can never mint the same AES-GCM nonce or overtake each
  /// other on the wire.
  Future<void> send(Uint8List plaintext) {
    final operation = _sendQueue.then((_) => _sendNow(plaintext));
    _sendQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> _sendNow(Uint8List plaintext) async {
    // Reserve a small nonce block durably, then serve high-frequency gesture
    // packets from memory. A crash skips unused values instead of ever
    // reusing one; the receiver already supports authenticated forward gaps.
    final counter = await _outbound.next(reservationSize: 64);
    final wireCounter = _nonceDomains.outboundWireCounter(counter);
    final packet = await _sealer.seal(
      plaintext,
      key: _key,
      nonceCounter: wireCounter,
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
