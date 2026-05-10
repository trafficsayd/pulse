import 'dart:async';
import 'dart:typed_data';

import '../../core/crypto/pulse_crypto.dart';
import '../../core/crypto/pulse_key_manager.dart';
import 'ble_transport.dart';
import 'local_network_transport.dart';
import 'transport.dart';
import 'webrtc_transport.dart';

/// Picks the best available [Transport] for a given connection and falls
/// through automatically without dropping the user-visible session.
///
/// Priority follows the spec: direct (BLE / Wi-Fi Direct) → local network
/// → relay. The manager never raises a "disconnected" event upward — it
/// switches to [TransportKind.searching] and keeps trying with exponential
/// backoff so that the connection survives network blips and sleep.
///
/// All payloads sent through [send] are sealed with the connection's
/// per-pair shared secret (Curve25519 ECDH + AES-256-GCM) before they hit
/// the wire — see [setSharedSecret] and [sealAndSend].
class TransportManager {
  TransportManager({
    Transport? ble,
    Transport? localNetwork,
    Transport? relay,
    PulseCrypto? crypto,
    PulseKeyManager? keyManager,
  })  : _transports = [
          ble ?? BleTransport(),
          localNetwork ?? LocalNetworkTransport(),
          relay ?? WebRtcTransport(),
        ],
        _crypto = crypto ?? PulseCrypto(),
        _keyManager = keyManager;

  /// In priority order: direct → local network → relay.
  final List<Transport> _transports;

  /// Crypto engine. Owned by the manager so a single in-memory instance is
  /// reused for all connections.
  final PulseCrypto _crypto;
  PulseCrypto get crypto => _crypto;

  /// Optional [PulseKeyManager] hook. When wired, [ensureSharedSecret] will
  /// derive secrets directly from saved X25519 material rather than relying
  /// on callers to pre-load them via [setSharedSecret]. Tests pass `null`
  /// here.
  final PulseKeyManager? _keyManager;

  /// Per-connection 32-byte shared secret keyed by connection id.
  ///
  /// Populated after the pairing handshake; cleared in [detach]. The
  /// transport never logs or persists these — they live in memory only.
  final Map<String, List<int>> _sharedSecrets = <String, List<int>>{};

  void setSharedSecret(String connectionId, List<int> secret) {
    if (secret.length != 32) {
      throw ArgumentError(
        'Pulse shared secret must be 32 bytes, got ${secret.length}',
      );
    }
    _sharedSecrets[connectionId] = List<int>.unmodifiable(secret);
  }

  void clearSharedSecret(String connectionId) {
    _sharedSecrets.remove(connectionId);
  }

  bool hasSharedSecret(String connectionId) =>
      _sharedSecrets.containsKey(connectionId);

  /// Lazily fills the in-memory secret cache for [connectionId] by asking the
  /// [PulseKeyManager] to derive one from the saved X25519 material. Returns
  /// `true` if a secret is available afterward. No-op when the manager is not
  /// wired or the handshake hasn't completed yet.
  Future<bool> ensureSharedSecret(String connectionId) async {
    if (_sharedSecrets.containsKey(connectionId)) return true;
    final manager = _keyManager;
    if (manager == null) return false;
    final secret = await manager.sharedSecret(connectionId);
    if (secret == null || secret.length != 32) return false;
    _sharedSecrets[connectionId] = List<int>.unmodifiable(secret);
    return true;
  }

  final _state = StreamController<TransportKind>.broadcast();
  Stream<TransportKind> get state => _state.stream;

  TransportKind _current = TransportKind.searching;
  TransportKind get current => _current;

  /// Open all candidate transports. Whichever connects first wins; the
  /// others stay armed in case the active one degrades.
  Future<void> attach({required Map<String, String> reconnectTokens}) async {
    for (final t in _transports) {
      // Run in parallel — the manager just promotes whichever connects.
      unawaited(t.connect(reconnectTokens: reconnectTokens));
      t.state.listen((s) {
        if (s != TransportKind.searching && _rank(s) < _rank(_current)) {
          _current = s;
          _state.add(_current);
        }
      });
    }
  }

  /// Send via the highest-priority connected transport.
  ///
  /// If none is connected, the packet is dropped — Pulse never queues mode
  /// events; missed beats simply don't arrive. (Sneak In delivery is
  /// handled separately on the shadow channel.)
  Future<void> send(TransportPacket packet) async {
    for (final t in _transports) {
      if (t.isConnected) {
        await t.send(packet);
        return;
      }
    }
  }

  /// Encrypt [plaintext] for [connectionId] (using its previously stored
  /// shared secret) and ship it through the best available transport.
  ///
  /// Throws [StateError] if no shared secret has been negotiated for that
  /// connection yet — callers must run pairing first.
  Future<void> sealAndSend({
    required String connectionId,
    required List<int> plaintext,
  }) async {
    final secret = _sharedSecrets[connectionId];
    if (secret == null) {
      throw StateError(
        'TransportManager: no shared secret for connection $connectionId',
      );
    }
    final sealed = await _crypto.seal(
      sharedSecret: secret,
      plaintext: plaintext,
    );
    await send(TransportPacket(
      kind: 'mode_event',
      payload: sealed,
    ));
  }

  /// Inverse of [sealAndSend]: decrypts an incoming sealed payload using
  /// the connection's shared secret. Throws if no secret is registered or
  /// the payload was tampered with.
  Future<Uint8List> openIncoming({
    required String connectionId,
    required List<int> sealed,
  }) async {
    final secret = _sharedSecrets[connectionId];
    if (secret == null) {
      throw StateError(
        'TransportManager: no shared secret for connection $connectionId',
      );
    }
    return _crypto.open(sharedSecret: secret, sealed: sealed);
  }

  Future<void> detach() async {
    for (final t in _transports) {
      await t.disconnect();
    }
    _sharedSecrets.clear();
    _current = TransportKind.searching;
    _state.add(_current);
  }

  static int _rank(TransportKind k) => switch (k) {
        TransportKind.direct => 0,
        TransportKind.localNetwork => 1,
        TransportKind.relay => 2,
        TransportKind.searching => 3,
      };
}
