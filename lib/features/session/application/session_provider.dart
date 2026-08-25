import 'dart:async';

import 'package:collection/collection.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_key_store.dart';
import '../../connections/application/connections_controller.dart';
import '../../connections/domain/connection.dart';
import '../../connections/domain/connection_status.dart';
import '../../crypto/nonce_counter.dart';
import '../../crypto/pair_channel.dart';
import '../../crypto/pair_keys.dart';
import '../../transport/transport_byte_adapter.dart';
import '../../transport/transport.dart';
import '../../transport/transport_manager.dart';
import 'pulse_session.dart';

/// Riverpod notifier that creates and manages the [PulseSession] for the
/// currently active connection.
///
/// When the active connection changes (user switches on the People screen),
/// the old session is disposed and a new one is created. If no connection
/// is active or no keys have been persisted yet, the provider emits `null`.
class SessionNotifier extends AsyncNotifier<PulseSession?> {
  PulseSession? _session;

  @override
  Future<PulseSession?> build() async {
    // React to active connection changes.
    final state = ref.watch(connectionsControllerProvider);
    final active = state.connections
        .where((c) => c.status == ConnectionStatus.active)
        .firstOrNull;

    if (active == null) return null;

    final store = ref.read(secureKeyStoreProvider);
    final pairKeys = await PairKeys.load(store, active.id);
    if (pairKeys == null) {
      // Pairing hasn't completed yet for this connection.
      return null;
    }

    // Build nonce counters scoped to this connection.
    final outboundCounter = NonceCounter(
      storage: store,
      storageKey: PairKeys.outboundNonceKey(active.id),
    );
    final inboundCounter = NonceCounter(
      storage: store,
      storageKey: PairKeys.inboundNonceKey(active.id),
    );

    // Build transport layer.
    final transportManager = TransportManager();
    final adapter = TransportByteAdapter(manager: transportManager);

    // Build encrypted channel on top of the transport.
    final pairChannel = PairChannel(
      transport: adapter,
      key: SecretKey(pairKeys.symmetricKey),
      outboundCounter: outboundCounter,
      inboundCounter: inboundCounter,
    );

    // Open transports and start the encrypted channel.
    final tokens = _buildTokens(active);
    await transportManager.attach(reconnectTokens: tokens);
    await pairChannel.start();

    final session = PulseSession(
      connectionId: active.id,
      transportManager: transportManager,
      pairChannel: pairChannel,
    );
    _session = session;

    // Clean up when the provider is disposed (e.g. app shutdown).
    ref.onDispose(() {
      _session?.dispose();
      _session = null;
    });

    return session;
  }

  static Map<String, String> _buildTokens(Connection c) => {
        'bleAddressToken': c.bleAddressToken ?? '',
        'signalingToken': c.signalingToken ?? '',
        'connectionId': c.id,
        'transportClientId': c.transportClientId ?? '',
      };
}

/// Provider exposing the active [PulseSession] (or null).
final sessionProvider = AsyncNotifierProvider<SessionNotifier, PulseSession?>(
  SessionNotifier.new,
);

/// Reactive transport tier for UI surfaces. Reading `currentTransport` alone
/// only captures the value at session creation and misses later failovers.
final transportStateProvider = StreamProvider<TransportKind>((ref) async* {
  final session = await ref.watch(sessionProvider.future);
  if (session == null) {
    yield TransportKind.searching;
    return;
  }
  yield session.currentTransport;
  yield* session.transportState;
});
