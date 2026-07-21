import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/secure_key_store.dart';
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
    state = ConnectionsState(connections: existing, isLoading: false);
  }

  /// Create a demo connection for testing / debug. Not used in production
  /// — real connections are only ever created through [createPairedConnection]
  /// after a completed ECDH handshake.
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
}

/// Provider for [Uuid] so tests can inject a deterministic generator.
final uuidProvider = Provider<Uuid>((ref) => const Uuid());

final connectionsControllerProvider =
    NotifierProvider<ConnectionsController, ConnectionsState>(
  ConnectionsController.new,
);
