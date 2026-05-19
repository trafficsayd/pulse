import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/secure_key_store.dart';
import '../data/connections_repository.dart';
import '../domain/connection.dart';
import '../domain/connection_status.dart';
import '../domain/permission_flags.dart';

/// Aggregated read-model exposed to the UI.
@immutable
class ConnectionsState {
  const ConnectionsState({
    this.connections = const [],
    this.isLoading = true,
  });

  final List<Connection> connections;
  final bool isLoading;

  Connection? get active => connections
      .where((c) => c.status == ConnectionStatus.active)
      .cast<Connection?>()
      .firstWhere((_) => true, orElse: () => null);

  ConnectionsState copyWith({
    List<Connection>? connections,
    bool? isLoading,
  }) =>
      ConnectionsState(
        connections: connections ?? this.connections,
        isLoading: isLoading ?? this.isLoading,
      );
}

/// Controller orchestrating CRUD on connections plus the "exactly one
/// active session" rule from the spec.
class ConnectionsController extends Notifier<ConnectionsState> {
  late final ConnectionsRepository _repo;

  @override
  ConnectionsState build() {
    final store = ref.read(secureKeyStoreProvider);
    _repo = ConnectionsRepository(keyStore: store);
    _bootstrap();
    return const ConnectionsState();
  }

  Future<void> _bootstrap() async {
    final existing = await _repo.loadAll();
    if (existing.isEmpty) {
      // Seed demo data so the UI redesign is immediately visible without
      // having to walk through pairing every time. These records live only
      // on this device and never leave it; once real pairing is wired up
      // the seeder can be removed.
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
