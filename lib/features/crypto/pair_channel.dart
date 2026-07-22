import 'dart:async';
import 'dart:convert';
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
///
/// Every packet is additionally bound to a channel-wide associated-data
/// (AAD) tag via AES-GCM — see [_buildAad] for exactly how it is built
/// and why it is safe for both peers to compute independently.
class PairChannel {
  PairChannel({
    required RawByteChannel transport,
    required SecretKey key,
    required NonceCounter outboundCounter,
    required NonceCounter inboundCounter,
    AesGcmSealer? sealer,
    int epoch = 0,
  })  : _transport = transport,
        _key = key,
        _outbound = outboundCounter,
        _inbound = inboundCounter,
        _sealer = sealer ?? AesGcmSealer(),
        _epoch = epoch,
        _aad = _buildAad(epoch);

  final RawByteChannel _transport;
  final SecretKey _key;
  final NonceCounter _outbound;
  final NonceCounter _inbound;
  final AesGcmSealer _sealer;

  /// Rekey/session epoch this channel instance was constructed for.
  ///
  /// Defaults to `0` so every existing call site (which never mentions
  /// epochs) keeps behaving exactly as before. Bumping it — once a
  /// future rekey flow lands — forces both peers to construct a new
  /// [PairChannel] with the same higher value, which changes [_aad] and
  /// therefore makes packets sealed under one epoch fail to [open]
  /// under another.
  final int _epoch;

  /// The rekey/session epoch this channel was constructed with. Exposed
  /// for diagnostics/tests that want to confirm two [PairChannel]
  /// instances agree before wiring them to the same transport.
  int get epoch => _epoch;

  /// Associated data authenticated (via AES-GCM) on every packet this
  /// channel seals or opens.
  ///
  /// Deliberately **direction-independent**: it is a domain tag plus
  /// the epoch, with no "in"/"out" marker. AES-GCM AAD is never placed
  /// on the wire (see [AesGcmSealer]), so the only way [AesGcmSealer.open]
  /// can succeed is if both peers pass it the exact same aad bytes that
  /// were passed to the matching [AesGcmSealer.seal] call. If we encoded
  /// direction literally ("out" vs. "in"), the sender's AAD for an
  /// outbound packet ("...out...") would never match the receiver's AAD
  /// for that same physical packet (which it experiences as inbound,
  /// "...in..."), and every single packet would fail to authenticate.
  /// Keeping AAD symmetric per epoch — the same bytes on both sides for
  /// a given pairing session — is what makes [AesGcmSealer.seal] on one
  /// peer and [AesGcmSealer.open] on the other agree.
  ///
  /// What this AAD *does* protect against: a packet sealed by this pair
  /// under epoch N cannot be replayed and successfully opened as if it
  /// belonged to epoch M (e.g. after a rekey/session bump changes the
  /// epoch but the symmetric key is reused/derived similarly). Replay
  /// and reordering *within* an epoch are still guarded exclusively by
  /// the strict [NonceCounter] matching in [_processPacket] /
  /// [send] — this AAD is a domain-separation belt, not a
  /// replacement for the nonce-counter suspenders.
  final Uint8List _aad;

  final _controller = StreamController<PulsePacket>.broadcast();
  StreamSubscription<Uint8List>? _sub;
  bool _started = false;
  Future<void> _packetQueue = Future<void>.value();

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
      final plain = await _sealer.open(
        bytes,
        key: _key,
        expectedNonceCounter: expected,
        aad: _aad,
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
      aad: _aad,
    );
    await _transport.send(packet);
  }

  Future<void> close() async {
    await _sub?.cancel();
    await _transport.close();
    await _controller.close();
    await _errors.close();
  }

  /// Build the direction-independent AAD tag for [epoch].
  ///
  /// Format: the ASCII/UTF-8 domain tag `"pulse:v1:aad:"` followed by
  /// [epoch] encoded as a big-endian uint32 (4 bytes). Both peers derive
  /// this from nothing but the epoch they agree they're on — no
  /// direction, connection id, or transport detail leaks in, so it is
  /// trivial for the sender's `seal()` call and the receiver's `open()`
  /// call to land on identical bytes for the same packet.
  static Uint8List _buildAad(int epoch) {
    if (epoch < 0) {
      throw ArgumentError.value(epoch, 'epoch', 'Epoch must be non-negative');
    }
    const domainTag = 'pulse:v1:aad:';
    final tagBytes = utf8.encode(domainTag);
    final out = Uint8List(tagBytes.length + 4);
    out.setRange(0, tagBytes.length, tagBytes);
    var value = epoch;
    for (var i = tagBytes.length + 3; i >= tagBytes.length; i--) {
      out[i] = value & 0xff;
      value >>= 8;
    }
    return out;
  }
}
