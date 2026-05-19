import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'curve25519_pairing_service.dart';
import 'pair_channel.dart';

/// In-memory byte channel useful for tests and for the demo pairing flow
/// shipped before the real BLE / mDNS / WebRTC transports land.
///
/// Two channels pair up via [InMemoryByteChannelPair.create] so that what
/// is written to [local] is delivered to [remote] and vice versa.
class InMemoryByteChannel implements RawByteChannel {
  InMemoryByteChannel._();

  final StreamController<Uint8List> _inbox =
      StreamController<Uint8List>.broadcast();
  late final InMemoryByteChannel _peer;
  bool _closed = false;

  @override
  Stream<Uint8List> get incoming => _inbox.stream;

  @override
  Future<void> send(Uint8List bytes) async {
    if (_closed || _peer._closed) return;
    // Defer one microtask so callers see strict producer/consumer
    // ordering, identical to what a real socket would give us.
    scheduleMicrotask(() {
      if (!_peer._inbox.isClosed) {
        _peer._inbox.add(Uint8List.fromList(bytes));
      }
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _inbox.close();
  }
}

/// Bidirectional [InMemoryByteChannel] pair. `local` and `remote` are
/// mirror images of each other.
class InMemoryByteChannelPair {
  InMemoryByteChannelPair._(this.local, this.remote);

  factory InMemoryByteChannelPair.create() {
    final a = InMemoryByteChannel._();
    final b = InMemoryByteChannel._();
    a._peer = b;
    b._peer = a;
    return InMemoryByteChannelPair._(a, b);
  }

  final InMemoryByteChannel local;
  final InMemoryByteChannel remote;
}

/// Simulated remote partner used by the pairing UI before real
/// transports land.
///
/// Generates its own ephemeral X25519 keypair, performs ECDH on its
/// side, and emits its public key after [responseDelay] so the host can
/// derive the matching shared secret. The host then compares the SAS
/// code with the partner out-of-band.
///
/// This class lives in `features/crypto/` on purpose: it is *not* a
/// transport. The real transport stack will replace it without changing
/// the surface seen by [pairing_screen.dart].
class DemoPartnerHandshake {
  DemoPartnerHandshake({
    Curve25519PairingService? service,
    Duration responseDelay = const Duration(milliseconds: 700),
  })  : _service = service ?? Curve25519PairingService(),
        _responseDelay = responseDelay;

  final Curve25519PairingService _service;
  final Duration _responseDelay;

  Curve25519KeyPair? _partnerKeyPair;
  Timer? _pendingTimer;
  Completer<SimplePublicKey>? _pendingCompleter;

  /// Pretend a partner just scanned our QR. After [_responseDelay] this
  /// future resolves with the partner's freshly-generated X25519 public
  /// key. Returning the partner's key is enough information for the
  /// host to finish ECDH locally.
  ///
  /// The internal [Timer] is exposed via [cancel] so the host can tear
  /// the partner exchange down cleanly on widget disposal or timeout
  /// (avoids the "Timer still pending" assertion in widget tests).
  Future<SimplePublicKey> exchange({
    required SimplePublicKey ourPublicKey,
  }) async {
    cancel();
    _partnerKeyPair = await _service.generateLocalKeyPair();
    final completer = Completer<SimplePublicKey>();
    _pendingCompleter = completer;
    _pendingTimer = Timer(_responseDelay, () {
      if (!completer.isCompleted) {
        completer.complete(_partnerKeyPair!.publicKey);
      }
      _pendingTimer = null;
      _pendingCompleter = null;
    });
    return completer.future;
  }

  /// Cancel an in-flight [exchange]. Any pending future completes with
  /// a [StateError] so the host's `await` chain unwinds promptly.
  void cancel() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    final pending = _pendingCompleter;
    _pendingCompleter = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        StateError('Demo partner handshake cancelled'),
      );
    }
  }

  /// Public key the demo partner chose for this handshake. Available
  /// only after [exchange] has been awaited at least once.
  SimplePublicKey? get partnerPublicKey => _partnerKeyPair?.publicKey;
}
