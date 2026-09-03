import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/secure_key_store.dart';
import '../../crypto/curve25519_pairing_service.dart';
import '../../crypto/nonce_counter.dart';
import '../../crypto/pair_keys.dart';
import '../../transport/webrtc/signaling_client.dart';
import '../domain/pairing_qr_payload.dart';

/// Discrete steps the pairing handshake walks through. Drives both the
/// pairing screen badge and the connecting screen's three-step indicator.
enum PairingPhase {
  idle,
  generatingKeys,
  awaitingPartner,
  derivingSecret,
  awaitingConfirmation,
  persisting,
  ready,
  failed,
}

/// Snapshot of the in-progress pairing handshake.
@immutable
class PairingState {
  const PairingState({
    this.phase = PairingPhase.idle,
    this.pairingCode,
    this.connectionId,
    this.signalingToken,
    this.localKeyPair,
    this.localPublicKeyBase64,
    this.partnerPublicKey,
    this.sharedSecret,
    this.sasCode,
    this.persistedKeys,
    this.error,
  });

  final PairingPhase phase;
  final String? pairingCode;
  final String? connectionId;
  final String? signalingToken;
  final Curve25519KeyPair? localKeyPair;
  final String? localPublicKeyBase64;
  final SimplePublicKey? partnerPublicKey;
  final SharedSecret? sharedSecret;
  final String? sasCode;
  final PairKeys? persistedKeys;
  final Object? error;

  bool get hasShortCode => sasCode != null;
  bool get hasPairingCode => pairingCode != null;
  bool get hasFailed => phase == PairingPhase.failed;
  bool get isReadyToConfirm =>
      phase == PairingPhase.awaitingConfirmation && sasCode != null;

  PairingState copyWith({
    PairingPhase? phase,
    String? pairingCode,
    String? connectionId,
    String? signalingToken,
    Curve25519KeyPair? localKeyPair,
    String? localPublicKeyBase64,
    SimplePublicKey? partnerPublicKey,
    SharedSecret? sharedSecret,
    String? sasCode,
    PairKeys? persistedKeys,
    Object? error,
    bool clearError = false,
  }) =>
      PairingState(
        phase: phase ?? this.phase,
        pairingCode: pairingCode ?? this.pairingCode,
        connectionId: connectionId ?? this.connectionId,
        signalingToken: signalingToken ?? this.signalingToken,
        localKeyPair: localKeyPair ?? this.localKeyPair,
        localPublicKeyBase64: localPublicKeyBase64 ?? this.localPublicKeyBase64,
        partnerPublicKey: partnerPublicKey ?? this.partnerPublicKey,
        sharedSecret: sharedSecret ?? this.sharedSecret,
        sasCode: sasCode ?? this.sasCode,
        persistedKeys: persistedKeys ?? this.persistedKeys,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Hard ceiling on how long Pulse will wait for the partner's response
/// before tearing the handshake down and freeing radios. Matches the
/// "60 second pairing window" requirement (§6.2 audit).
const Duration kPairingHandshakeTimeout = Duration(seconds: 60);

/// Orchestrates the first-launch handshake: keypair generation, public-key
/// exchange through the signaling rendezvous, HKDF, SAS derivation, and
/// persistence of the resulting [PairKeys] into [SecureKeyStore] together
/// with both nonce counters.
class PairingController extends Notifier<PairingState> {
  Curve25519PairingService _service = Curve25519PairingService();
  late final SignalingClient _signaling;
  final Random _random = Random.secure();
  Timer? _watchdog;
  bool _disposed = false;
  int _epoch = 0;

  @visibleForTesting
  void overrideForTesting({
    Curve25519PairingService? service,
  }) {
    if (service != null) _service = service;
  }

  @override
  PairingState build() {
    _disposed = false;
    _signaling = ref.read(pairingSignalingClientProvider);
    ref.onDispose(_handleDispose);
    return const PairingState();
  }

  /// Kick off the full host-side handshake: generate a pairing code,
  /// publish our public key through the signaling rendezvous, wait for the
  /// partner public key, then derive the shared secret and SAS code.
  ///
  /// Bench: on a Pixel 5 the entire chain (ephemeral keypair + ECDH +
  /// HKDF-SHA-256 + SAS) finishes in <50ms with pure-Dart cryptography;
  /// network wait is bounded by [timeout].
  Future<void> startHostHandshake({
    Duration timeout = kPairingHandshakeTimeout,
  }) async {
    _cancelWatchdog();
    final epoch = ++_epoch;
    if (_disposed) return;
    final pairingCode = _generatePairingCode();
    state = PairingState(
      phase: PairingPhase.generatingKeys,
      pairingCode: pairingCode,
    );

    // Boot race: at app cold-start the signaling server may not yet be
    // reachable from the emulator (wrangler still warming up, DNS not
    // resolved, kernel net stack still bringing interfaces up). Try the
    // rendezvous a few times with exponential backoff before giving up so
    // the user doesn't have to tap Retry on first open.
    Future<T> retryNet<T>(Future<T> Function() fn, {int attempts = 3}) async {
      Object? lastErr;
      for (var i = 0; i < attempts; i++) {
        try {
          return await fn();
        } catch (e) {
          lastErr = e;
          if (_disposed || epoch != _epoch) rethrow;
          await Future<void>.delayed(
            e is SignalingException && e.retryAfter != null
                ? e.retryAfter!
                : Duration(milliseconds: 250 * (1 << i)),
          );
        }
      }
      throw lastErr ?? StateError('unreachable');
    }

    try {
      final localKeyPair = await _service.generateLocalKeyPair();
      if (_disposed || epoch != _epoch) return;
      final pubB64 = await localKeyPair.publicKeyBase64Url();
      if (_disposed || epoch != _epoch) return;
      final session =
          await retryNet(() => _signaling.createSession(pairingCode));
      await retryNet(() => _signaling.postOffer(
            sessionId: session.sessionId,
            token: session.token,
            offer: SignalingSessionDescription(
              type: 'offer',
              sdp: _encodePublicKey(pubB64),
            ),
          ));
      state = state.copyWith(
        phase: PairingPhase.awaitingPartner,
        pairingCode: pairingCode,
        connectionId: session.sessionId,
        signalingToken: session.sessionId,
        localKeyPair: localKeyPair,
        localPublicKeyBase64: pubB64,
      );

      final answer = await _pollForAnswer(
        sessionId: session.sessionId,
        token: session.token,
        timeout: timeout,
        epoch: epoch,
      );
      if (_disposed || epoch != _epoch) return;
      if (answer == null) {
        throw TimeoutException('Pairing answer timed out', timeout);
      }
      final partnerKey = _decodePublicKey(answer.sdp);

      state = state.copyWith(
        phase: PairingPhase.derivingSecret,
        partnerPublicKey: partnerKey,
      );

      final shared = await _service.deriveSharedSecret(
        localKeyPair: localKeyPair.keyPair,
        peerPublicKey: partnerKey,
      );
      if (_disposed || epoch != _epoch) return;
      final sas = _service.deriveShortCode(shared);

      state = state.copyWith(
        phase: PairingPhase.awaitingConfirmation,
        sharedSecret: shared,
        sasCode: sas,
      );
    } catch (e) {
      _cancelWatchdog();
      if (_disposed) return;
      debugPrint('[Pairing] host handshake failed: $e');
      state = state.copyWith(phase: PairingPhase.failed, error: e);
    }
  }

  /// Join a host-created pairing session by its six digit rendezvous code.
  Future<void> joinHandshake(
    String rawCode, {
    List<int>? expectedHostPublicKey,
    Duration timeout = kPairingHandshakeTimeout,
  }) async {
    _cancelWatchdog();
    final epoch = ++_epoch;
    final pairingCode = _normaliseCode(rawCode);
    if (pairingCode.length != 6) {
      state = PairingState(
        phase: PairingPhase.failed,
        error: FormatException('Pairing code must be 6 digits', rawCode),
      );
      return;
    }
    if (expectedHostPublicKey != null && expectedHostPublicKey.length != 32) {
      state = const PairingState(
        phase: PairingPhase.failed,
        error: PairingQrPayloadException(
          'Expected host public key must be 32 bytes',
        ),
      );
      return;
    }
    if (_disposed) return;
    state = PairingState(
      phase: PairingPhase.generatingKeys,
      pairingCode: pairingCode,
    );
    try {
      final localKeyPair = await _service.generateLocalKeyPair();
      if (_disposed || epoch != _epoch) return;
      final pubB64 = await localKeyPair.publicKeyBase64Url();

      // Boot race: see comment in [startHostHandshake]. The joiner can hit
      // a cold signaling path too — both createSession and the first
      // getOffer are retried so a slow wrangler cold-start on the host
      // doesn't bounce the user back with "Couldn't reach the server."
      Future<T> retryNet<T>(Future<T> Function() fn, {int attempts = 3}) async {
        Object? lastErr;
        for (var i = 0; i < attempts; i++) {
          try {
            return await fn();
          } catch (e) {
            lastErr = e;
            if (_disposed || epoch != _epoch) rethrow;
            await Future<void>.delayed(
              e is SignalingException && e.retryAfter != null
                  ? e.retryAfter!
                  : Duration(milliseconds: 250 * (1 << i)),
            );
          }
        }
        throw lastErr ?? StateError('unreachable');
      }

      final session =
          await retryNet(() => _signaling.createSession(pairingCode));
      state = state.copyWith(
        phase: PairingPhase.awaitingPartner,
        connectionId: session.sessionId,
        signalingToken: session.sessionId,
        localKeyPair: localKeyPair,
        localPublicKeyBase64: pubB64,
      );

      // Poll the host's offer. The host may still be in `awaitingPartner`
      // (we race them to `createSession` returning the same id) — keep
      // polling until timeout. Single failures are retried inside the loop.
      SignalingSessionDescription? offer;
      final deadline = DateTime.now().add(timeout);
      var pollAttempt = 0;
      while (
          !_disposed && epoch == _epoch && DateTime.now().isBefore(deadline)) {
        Duration? serverBackoff;
        try {
          offer = await _signaling.getOffer(
            sessionId: session.sessionId,
            token: session.token,
          );
        } on SignalingException catch (error) {
          serverBackoff = error.retryAfter;
          // Transient signaling hiccup → keep polling until deadline.
        } on Object {
          // transient signaling hiccup → keep polling until deadline
        }
        if (offer != null) break;
        await Future<void>.delayed(
          serverBackoff ?? _pairingPollDelay(pollAttempt++),
        );
      }
      if (_disposed || epoch != _epoch) return;
      if (offer == null) {
        throw TimeoutException('Pairing offer timed out', timeout);
      }
      final partnerKey = _decodePublicKey(offer.sdp);
      if (expectedHostPublicKey != null &&
          !_constantTimeEquals(partnerKey.bytes, expectedHostPublicKey)) {
        throw const PairingQrKeyMismatchException();
      }

      state = state.copyWith(
        phase: PairingPhase.derivingSecret,
        partnerPublicKey: partnerKey,
      );
      final shared = await _service.deriveSharedSecret(
        localKeyPair: localKeyPair.keyPair,
        peerPublicKey: partnerKey,
      );
      if (_disposed || epoch != _epoch) return;

      await retryNet(() => _signaling.postAnswer(
            sessionId: session.sessionId,
            token: session.token,
            answer: SignalingSessionDescription(
              type: 'answer',
              sdp: _encodePublicKey(pubB64),
            ),
          ));
      if (_disposed || epoch != _epoch) return;

      final sas = _service.deriveShortCode(shared);
      state = state.copyWith(
        phase: PairingPhase.awaitingConfirmation,
        sharedSecret: shared,
        sasCode: sas,
      );
    } catch (e) {
      _cancelWatchdog();
      if (_disposed) return;
      state = state.copyWith(phase: PairingPhase.failed, error: e);
    }
  }

  /// User pressed "Confirm" — persist everything to secure storage and
  /// return the new [PairKeys] so callers can wire connections.
  Future<PairKeys?> confirmAndPersist({String? connectionId}) async {
    final keyPair = state.localKeyPair;
    final partner = state.partnerPublicKey;
    final secret = state.sharedSecret;
    if (keyPair == null || partner == null || secret == null) {
      return null;
    }
    state = state.copyWith(phase: PairingPhase.persisting);
    try {
      final id = connectionId ?? state.connectionId ?? const Uuid().v4();
      final privateBytes = await keyPair.keyPair.extractPrivateKeyBytes();
      final pair = PairKeys(
        connectionId: id,
        symmetricKey: secret.bytes,
        partnerPublicKey: Uint8List.fromList(partner.bytes),
        localPrivateKey: Uint8List.fromList(privateBytes),
      );
      final store = ref.read(secureKeyStoreProvider);
      await pair.persist(store);

      // Fresh counters per direction, both start at zero. Session startup maps
      // them into disjoint nonce domains, so opposite peers cannot repeat an
      // AES-GCM key/nonce pair.
      final outbound = NonceCounter(
        storage: store,
        storageKey: PairKeys.outboundNonceKey(id),
      );
      final inbound = NonceCounter(
        storage: store,
        storageKey: PairKeys.inboundNonceKey(id),
      );
      await outbound.resetToZero();
      await inbound.resetToZero();

      state = state.copyWith(
        phase: PairingPhase.ready,
        persistedKeys: pair,
      );
      return pair;
    } catch (e) {
      state = state.copyWith(phase: PairingPhase.failed, error: e);
      return null;
    }
  }

  /// Cancel any pending watchdog and reset back to idle. Safe to call
  /// from screen dispose handlers.
  void reset() {
    _cancelWatchdog();
    _epoch++;
    if (_disposed) return;
    state = const PairingState();
  }

  void _cancelWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  void _handleDispose() {
    _disposed = true;
    _cancelWatchdog();
    _epoch++;
  }

  String _generatePairingCode() =>
      _random.nextInt(1000000).toString().padLeft(6, '0');

  static String _normaliseCode(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  static String _encodePublicKey(String publicKeyBase64Url) =>
      'pulse-pair:v1:$publicKeyBase64Url';

  static SimplePublicKey _decodePublicKey(String encoded) {
    const prefix = 'pulse-pair:v1:';
    if (!encoded.startsWith(prefix)) {
      throw const FormatException('malformed pairing public key payload');
    }
    final raw = encoded.substring(prefix.length);
    final padded = raw.padRight(raw.length + (4 - raw.length % 4) % 4, '=');
    final bytes = base64Url.decode(padded);
    if (bytes.length != 32) {
      throw const FormatException('Curve25519 public key must be 32 bytes');
    }
    return SimplePublicKey(bytes, type: KeyPairType.x25519);
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  Future<SignalingSessionDescription?> _pollForAnswer({
    required String sessionId,
    required String token,
    required Duration timeout,
    required int epoch,
  }) async {
    final deadline = DateTime.now().add(timeout);
    var pollAttempt = 0;
    while (!_disposed && epoch == _epoch && DateTime.now().isBefore(deadline)) {
      Duration? serverBackoff;
      try {
        final answer = await _signaling.getAnswer(
          sessionId: sessionId,
          token: token,
        );
        if (answer != null) return answer;
      } on SignalingException catch (error) {
        final status = error.statusCode;
        final transient = status == null ||
            status == 404 ||
            status == 408 ||
            status == 429 ||
            status >= 500;
        if (!transient) rethrow;
        serverBackoff = error.retryAfter;
        // Mobile networks and emulators can drop an individual short poll.
        // Cloudflare KV can also briefly return 404 from another edge right
        // after creation. Neither invalidates the published host offer.
      } on TimeoutException {
        // Same transient short-poll failure, keep the rendezvous alive.
      }
      await Future<void>.delayed(
        serverBackoff ?? _pairingPollDelay(pollAttempt++),
      );
    }
    return null;
  }

  /// Keep the first pairing response snappy, then taper the request rate.
  /// Host and guest usually share one NAT address, and pairing may run while
  /// an existing connection is reconnecting in the background.
  static Duration _pairingPollDelay(int attempt) =>
      Duration(milliseconds: min(1500, 400 + attempt * 200));
}

final pairingSignalingClientProvider = Provider<SignalingClient>((ref) {
  final client = SignalingClient();
  ref.onDispose(client.close);
  return client;
});

/// Riverpod entry point — the pairing screen and connecting screen both
/// subscribe to this.
final pairingControllerProvider =
    NotifierProvider<PairingController, PairingState>(PairingController.new);
