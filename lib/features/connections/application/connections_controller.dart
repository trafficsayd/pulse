import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/secure_key_store.dart';
import '../../crypto/pair_keys.dart';
import '../data/connections_repository.dart';
import '../domain/connection.dart';
import '../domain/connection_status.dart';
import '../domain/permission_flags.dart';

/// Aggregated read-model exposed to the UI.
@immutable
class ConnectionsState {
  const ConnectionsState({this.connections = const [], this.isLoading = true});

  final List<Connection> connections;
  final bool isLoading;

  Connection? get active =>
      connections.firstWhereOrNull((c) => c.status == ConnectionStatus.active);

  ConnectionsState copyWith({List<Connection>? connections, bool? isLoading}) =>
      ConnectionsState(
        connections: connections ?? this.connections,
        isLoading: isLoading ?? this.isLoading,
      );
}

/// Controller orchestrating CRUD on connections plus the "exactly one
/// active session" rule from the spec.
class ConnectionsController extends Notifier<ConnectionsState> {
  late final ConnectionsRepository _repo;
  late final Uuid _uuid;

  @override
  ConnectionsState build() {
    final store = ref.read(secureKeyStoreProvider);
    _uuid = ref.read(uuidProvider);
    _repo = ConnectionsRepository(keyStore: store, uuid: _uuid);
    _bootstrap();
    return const ConnectionsState();
  }

  Future<void> _bootstrap() async {
    final existing = await _repo.loadAll();
    if (existing.isEmpty && kDebugMode) {
      // Seed demo data so the UI redesign is immediately visible without
      // having to walk through pairing every time. These records live only
      // on this device and never leave it. Skipped in release builds so
      // real users start from an empty connections book per the spec.
      final seeded = await _seedDemoConnections();
      state = ConnectionsState(connections: seeded, isLoading: false);
      return;
    }
    state = ConnectionsState(connections: existing, isLoading: false);
  }

  Future<List<Connection>> _seedDemoConnections() async {
    final demos = <_SeedSpec>[
      const _SeedSpec(
        nickname: 'Солнце',
        emoji: '🌞',
        colorIndex: 0,
        status: ConnectionStatus.active,
      ),
      const _SeedSpec(
        nickname: 'Луна',
        emoji: '🌙',
        colorIndex: 1,
        status: ConnectionStatus.paused,
      ),
      const _SeedSpec(
        nickname: 'Звезда',
        emoji: '✨',
        colorIndex: 2,
        status: ConnectionStatus.paused,
      ),
      const _SeedSpec(
        nickname: 'Комета',
        emoji: '☄️',
        colorIndex: 3,
        status: ConnectionStatus.archived,
        permissions: PermissionFlags.blocked,
      ),
    ];
    final out = <Connection>[];
    for (final s in demos) {
      final created = await _repo.create(
        nickname: s.nickname,
        emoji: s.emoji,
        colorIndex: s.colorIndex,
        permissions: s.permissions,
      );
      final patched = created.copyWith(status: s.status);
      await _repo.update(patched);
      out.add(patched);
    }
    return out;
  }

  Future<Connection> createStubConnection({String nickname = 'Demo'}) async {
    const palette = [0, 1, 2, 3, 4, 5, 6, 7];
    const emojis = ['🌞', '🌙', '✨', '☄️', '🪐', '🌟', '🌈', '🔮'];
    final colorIndex = palette[state.connections.length % palette.length];
    final emoji = emojis[state.connections.length % emojis.length];
    final c = await _repo.create(
      nickname: nickname,
      emoji: emoji,
      colorIndex: colorIndex,
    );
    final next = [...state.connections, c];
    state = state.copyWith(connections: next);
    return c;
  }

  /// Create the saved connection that belongs to a completed pairing.
  ///
  /// [connectionId] must match the id used by [PairKeys.persist], otherwise
  /// [SessionNotifier] will not be able to load the encrypted channel keys
  /// for the active person.
  Future<Connection> createPairedConnection({
    required String connectionId,
    String nickname = 'Pulse',
    String? bleAddressToken,
    String? signalingToken,
  }) async {
    final existing = state.connections.firstWhereOrNull(
      (c) => c.id == connectionId,
    );
    if (existing != null) {
      await makeActive(existing.id);
      return existing.copyWith(status: ConnectionStatus.active);
    }

    const palette = [0, 1, 2, 3, 4, 5, 6, 7];
    const emojis = ['🌞', '🌙', '✨', '☄️', '🪐', '🌟', '🌈', '🔮'];
    final colorIndex = palette[state.connections.length % palette.length];
    final emoji = emojis[state.connections.length % emojis.length];
    final created = await _repo.create(
      id: connectionId,
      nickname: nickname,
      emoji: emoji,
      colorIndex: colorIndex,
      status: ConnectionStatus.active,
      bleAddressToken: bleAddressToken ?? signalingToken ?? _uuid.v4(),
      signalingToken: signalingToken ?? connectionId,
    );

    final next = <Connection>[];
    for (final c in state.connections) {
      if (c.status == ConnectionStatus.active) {
        final paused = c.copyWith(status: ConnectionStatus.paused);
        await _repo.update(paused);
        next.add(paused);
      } else {
        next.add(c);
      }
    }
    next.add(created);
    state = state.copyWith(connections: next, isLoading: false);
    return created;
  }

  Future<void> makeActive(String id) async {
    final next = <Connection>[];
    for (final c in state.connections) {
      if (c.id == id) {
        final updated = c.copyWith(status: ConnectionStatus.active);
        await _repo.update(updated);
        next.add(updated);
      } else if (c.status == ConnectionStatus.active) {
        final updated = c.copyWith(status: ConnectionStatus.paused);
        await _repo.update(updated);
        next.add(updated);
      } else {
        next.add(c);
      }
    }
    state = state.copyWith(connections: next);
  }

  Future<void> archive(String id) async {
    final next = [
      for (final c in state.connections)
        if (c.id == id)
          (await _persist(c.copyWith(status: ConnectionStatus.archived)))
        else
          c,
    ];
    state = state.copyWith(connections: next);
  }

  Future<void> unarchive(String id) async {
    final next = [
      for (final c in state.connections)
        if (c.id == id)
          (await _persist(c.copyWith(status: ConnectionStatus.paused)))
        else
          c,
    ];
    state = state.copyWith(connections: next);
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    // SECURITY (§6 "паническое стирание"): removing a connection MUST
    // destroy all of its cryptographic material — the symmetric AES key,
    // the partner's public key and both nonce counters — not just the
    // metadata entry. Otherwise the key survives in the Keychain /
    // EncryptedSharedPreferences indefinitely and history stays recoverable.
    final store = ref.read(secureKeyStoreProvider);
    await PairKeys.wipe(store, id);
    state = state.copyWith(
      connections: [
        for (final c in state.connections)
          if (c.id != id) c,
      ],
    );
  }

  Future<void> updatePermissions(String id, PermissionFlags flags) async {
    final next = [
      for (final c in state.connections)
        if (c.id == id) (await _persist(c.copyWith(permissions: flags))) else c,
    ];
    state = state.copyWith(connections: next);
  }

  Future<void> rename(String id, String nickname) async {
    final next = [
      for (final c in state.connections)
        if (c.id == id) (await _persist(c.copyWith(nickname: nickname))) else c,
    ];
    state = state.copyWith(connections: next);
  }

  Future<Connection> _persist(Connection c) async {
    await _repo.update(c);
    return c;
  }

  /// Number of saved connections counted against the tier's `maxConnections`
  /// cap (spec §9).
  ///
  /// This is the *total* number of local connection-book entries —
  /// including [ConnectionStatus.archived] ones. §7 defines "сохранённая
  /// связь" as anything persisted in the local connection book (it still
  /// has a UUID, key material on disk, etc.); archiving only changes a
  /// connection's status, it does not remove the entry. Counting only
  /// active/paused rows would let a paying-free user dodge the paywall by
  /// archiving an old connection right before pairing a new one while the
  /// old key material — and the "slot" it occupies per the spec's wording
  /// — is still sitting on disk.
  int get savedConnectionsCount => state.connections.length;

  /// Whether a brand-new connection can be added under [maxConnections] for
  /// the caller's current subscription tier.
  ///
  /// [maxConnections] must come from the live `Entitlements`/
  /// `SubscriptionController` (see `maxConnections` there) so there is a
  /// single source of truth for the tier's cap — this controller never
  /// hardcodes the 3 / 2 / 10 numbers from spec §9 itself.
  bool canAddConnection(int maxConnections) =>
      savedConnectionsCount < maxConnections;
}

class _SeedSpec {
  const _SeedSpec({
    required this.nickname,
    required this.emoji,
    required this.colorIndex,
    required this.status,
    this.permissions = const PermissionFlags(),
  });

  final String nickname;
  final String emoji;
  final int colorIndex;
  final ConnectionStatus status;
  final PermissionFlags permissions;
}

/// Provider for [Uuid] so tests can inject a deterministic generator.
final uuidProvider = Provider<Uuid>((ref) => const Uuid());

final connectionsControllerProvider =
    NotifierProvider<ConnectionsController, ConnectionsState>(
  ConnectionsController.new,
);
