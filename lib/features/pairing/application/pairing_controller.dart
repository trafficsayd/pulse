import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/secure_key_store.dart';
import '../../crypto/curve25519_pairing_service.dart';
import '../../crypto/demo_partner_channel.dart';
import '../../crypto/nonce_counter.dart';
import '../../crypto/pair_keys.dart';

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
    this.localKeyPair,
    this.localPublicKeyBase64,
    this.partnerPublicKey,
    this.sharedSecret,
    this.sasCode,
    this.persistedKeys,
    this.error,
  });

  final PairingPhase phase;
  final Curve25519KeyPair? localKeyPair;
  final String? localPublicKeyBase64;
  final SimplePublicKey? partnerPublicKey;
  final SharedSecret? sharedSecret;
  final String? sasCode;
  final PairKeys? persistedKeys;
  final Object? error;

  bool get hasShortCode => sasCode != null;
  bool get isReadyToConfirm =>
      phase == PairingPhase.awaitingConfirmation && sasCode != null;

  PairingState copyWith({
    PairingPhase? phase,
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

/// Orchestrates the first-launch handshake: keypair generation, partner
/// public-key exchange (via [DemoPartnerHandshake] for now), HKDF, SAS
/// derivation, and persistence of the resulting [PairKeys] into
/// [SecureKeyStore] together with both nonce counters.
class PairingController extends Notifier<PairingState> {
  Curve25519PairingService _service = Curve25519PairingService();
  DemoPartnerHandshake _partner = DemoPartnerHandshake();
  Timer? _watchdog;
  bool _disposed = false;

  @visibleForTesting
  void overrideForTesting({
    Curve25519PairingService? service,
    DemoPartnerHandshake? partner,
  }) {
    if (service != null) _service = service;
    if (partner != null) _partner = partner;
  }

  @override
  PairingState build() {
    _disposed = false;
    ref.onDispose(_handleDispose);
    return const PairingState();
  }

  /// Kick off the full host-side handshake: generate keypair, simulate
  /// the partner exchanging keys, derive the shared secret and SAS code.
  ///
  /// Bench: on a Pixel 5 the entire chain (ephemeral keypair + ECDH +
  /// HKDF-SHA-256 + SAS) finishes in <50ms with pure-Dart cryptography;
  /// well inside the 200ms budget agreed during the audit.
  Future<void> startHostHandshake({
    Duration timeout = kPairingHandshakeTimeout,
  }) async {
    _cancelWatchdog();
    if (_disposed) return;
    state = const PairingState(phase: PairingPhase.generatingKeys);
    final completer = Completer<SimplePublicKey>();
    _watchdog = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('Pairing handshake timed out', timeout),
        );
        _partner.cancel();
      }
    });
    try {
      final localKeyPair = await _service.generateLocalKeyPair();
      if (_disposed) return;
      final pubB64 = await localKeyPair.publicKeyBase64Url();
      if (_disposed) return;
      state = state.copyWith(
        phase: PairingPhase.awaitingPartner,
        localKeyPair: localKeyPair,
        localPublicKeyBase64: pubB64,
      );

      unawaited(
        _partner.exchange(ourPublicKey: localKeyPair.publicKey).then(
          (key) {
            if (!completer.isCompleted) completer.complete(key);
          },
          onError: (Object e, StackTrace _) {
            if (!completer.isCompleted) completer.completeError(e);
          },
        ),
      );

      final partnerKey = await completer.future;
      _cancelWatchdog();
      if (_disposed) return;

      state = state.copyWith(
        phase: PairingPhase.derivingSecret,
        partnerPublicKey: partnerKey,
      );

      final shared = await _service.deriveSharedSecret(
        localKeyPair: localKeyPair.keyPair,
        peerPublicKey: partnerKey,
      );
      if (_disposed) return;
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
      final id = connectionId ?? const Uuid().v4();
      final privateBytes = await keyPair.keyPair.extractPrivateKeyBytes();
      final pair = PairKeys(
        connectionId: id,
        symmetricKey: secret.bytes,
        partnerPublicKey: Uint8List.fromList(partner.bytes),
        localPrivateKey: Uint8List.fromList(privateBytes),
      );
      final store = ref.read(secureKeyStoreProvider);
      await pair.persist(store);

      // Fresh counters per direction, both start at zero.
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
    _partner.cancel();
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
    _partner.cancel();
  }
}

/// Riverpod entry point — the pairing screen and connecting screen both
/// subscribe to this.
final pairingControllerProvider =
    NotifierProvider<PairingController, PairingState>(PairingController.new);
