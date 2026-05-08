import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_key_store.dart';
import '../data/connections_repository.dart';
import '../domain/connection.dart';
import '../domain/connection_status.dart';
import '../domain/permission_flags.dart';

/// Provides the singleton [SecureKeyStore].
final secureKeyStoreProvider = Provider<SecureKeyStore>((ref) {
  return SecureKeyStore();
});

/// Provides the singleton [ConnectionsRepository].
final connectionsRepositoryProvider =
    Provider<ConnectionsRepository>((ref) {
  return ConnectionsRepository(keyStore: ref.watch(secureKeyStoreProvider));
});

/// Owns the in-memory list of saved connections and the currently active
/// connection id. The controller is the only place that mutates either —
/// every screen reads through Riverpod so updates fan out cleanly.
class ConnectionsState {
  const ConnectionsState({
    this.connections = const [],
    this.activeId,
    this.loading = true,
  });

  final List<Connection> connections;
  final String? activeId;
  final bool loading;

  Connection? get active {
    if (activeId == null) return null;
    for (final c in connections) {
      if (c.id == activeId) return c;
    }
    return null;
  }

  ConnectionsState copyWith({
    List<Connection>? connections,
    Object? activeId = _sentinel,
    bool? loading,
  }) {
    return ConnectionsState(
      connections: connections ?? this.connections,
      activeId:
          identical(activeId, _sentinel) ? this.activeId : activeId as String?,
      loading: loading ?? this.loading,
    );
  }

  static const _sentinel = Object();
}

class ConnectionsController extends Notifier<ConnectionsState> {
  @override
  ConnectionsState build() {
    _bootstrap();
    return const ConnectionsState();
  }

  Future<void> _bootstrap() async {
    final repo = ref.read(connectionsRepositoryProvider);
    final all = await repo.loadAll();
    state = ConnectionsState(
      connections: all,
      activeId: all
          .firstWhere(
            (c) => c.status == ConnectionStatus.active,
            orElse: () => const _NullConnection(),
          )
          .id
          .nullIfEmpty(),
      loading: false,
    );
  }

  /// Stub used until real pairing lands. Creates a paused connection so the
  /// rest of the app can be exercised without a partner device.
  Future<void> createStubConnection({required String nickname}) async {
    final repo = ref.read(connectionsRepositoryProvider);
    final created = await repo.create(
      nickname: nickname,
      colorIndex: state.connections.length % 8,
      emoji: '✨',
    );
    state = state.copyWith(connections: [...state.connections, created]);
  }

  /// Make [id] the single active full-duplex connection, demoting any prior
  /// active one to [ConnectionStatus.paused].
  Future<void> makeActive(String id) async {
    final repo = ref.read(connectionsRepositoryProvider);
    final next = <Connection>[];
    for (final c in state.connections) {
      if (c.id == id && c.status != ConnectionStatus.active) {
        final updated = c.copyWith(status: ConnectionStatus.active);
        await repo.update(updated);
        next.add(updated);
      } else if (c.id != id && c.status == ConnectionStatus.active) {
        final updated = c.copyWith(status: ConnectionStatus.paused);
        await repo.update(updated);
        next.add(updated);
      } else {
        next.add(c);
      }
    }
    state = state.copyWith(connections: next, activeId: id);
  }

  Future<void> updatePermissions(String id, PermissionFlags permissions) async {
    final repo = ref.read(connectionsRepositoryProvider);
    final next = <Connection>[];
    for (final c in state.connections) {
      if (c.id == id) {
        final updated = c.copyWith(permissions: permissions);
        await repo.update(updated);
        next.add(updated);
      } else {
        next.add(c);
      }
    }
    state = state.copyWith(connections: next);
  }

  Future<void> archive(String id) async {
    final repo = ref.read(connectionsRepositoryProvider);
    final next = <Connection>[];
    String? newActive = state.activeId;
    for (final c in state.connections) {
      if (c.id == id) {
        final updated = c.copyWith(status: ConnectionStatus.archived);
        await repo.update(updated);
        next.add(updated);
        if (state.activeId == id) newActive = null;
      } else {
        next.add(c);
      }
    }
    state = state.copyWith(connections: next, activeId: newActive);
  }

  Future<void> delete(String id) async {
    final repo = ref.read(connectionsRepositoryProvider);
    await repo.delete(id);
    state = state.copyWith(
      connections: state.connections.where((c) => c.id != id).toList(),
      activeId: state.activeId == id ? null : state.activeId,
    );
  }
}

/// Convenience: empty string -> null (used in [_bootstrap]).
extension on String {
  String? nullIfEmpty() => isEmpty ? null : this;
}

/// Sentinel used inside [_bootstrap] when there is no active connection at
/// startup. Avoids special-casing nullability in [firstWhere].
class _NullConnection implements Connection {
  const _NullConnection();
  @override
  String get id => '';
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

final connectionsControllerProvider =
    NotifierProvider<ConnectionsController, ConnectionsState>(
        ConnectionsController.new);
