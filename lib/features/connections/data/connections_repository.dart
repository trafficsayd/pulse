import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/storage/secure_key_store.dart';
import '../domain/connection.dart';
import '../domain/connection_status.dart';
import '../domain/permission_flags.dart';

/// CRUD over the local connection book.
///
/// Connections are persisted as JSON inside [SecureKeyStore] so that even
/// metadata (nickname, status, permissions) gets the same at-rest protection
/// as the symmetric keys.
class ConnectionsRepository {
  ConnectionsRepository({
    required SecureKeyStore keyStore,
    Uuid? uuid,
  })  : _keyStore = keyStore,
        _uuid = uuid ?? const Uuid();

  static const _indexKey = 'connections.index.v1';
  static const _entryPrefix = 'connections.entry.v1.';

  final SecureKeyStore _keyStore;
  final Uuid _uuid;

  Future<List<Connection>> loadAll() async {
    final indexRaw = await _keyStore.readString(_indexKey);
    if (indexRaw == null) return const [];
    final ids = (jsonDecode(indexRaw) as List<Object?>).cast<String>();

    final out = <Connection>[];
    for (final id in ids) {
      final json = await _keyStore.readJson('$_entryPrefix$id');
      if (json != null) {
        var connection = Connection.fromJson(json);
        if (connection.transportClientId == null) {
          connection = connection.copyWith(transportClientId: _uuid.v4());
          await _writeEntry(connection);
        }
        out.add(connection);
      }
    }
    return out;
  }

  Future<Connection> create({
    required String nickname,
    required int colorIndex,
    required String emoji,
    String? id,
    ConnectionStatus status = ConnectionStatus.paused,
    PermissionFlags permissions = const PermissionFlags(),
    String? bleAddressToken,
    String? signalingToken,
    String? transportClientId,
  }) async {
    final connection = Connection(
      id: id ?? _uuid.v4(),
      nickname: nickname,
      colorIndex: colorIndex,
      emoji: emoji,
      status: status,
      permissions: permissions,
      createdAt: DateTime.now(),
      bleAddressToken: bleAddressToken,
      signalingToken: signalingToken,
      transportClientId: transportClientId ?? _uuid.v4(),
    );
    await _writeEntry(connection);
    await _appendIndex(connection.id);
    return connection;
  }

  Future<void> update(Connection connection) async {
    await _writeEntry(connection);
  }

  Future<void> delete(String id) async {
    await _keyStore.delete('$_entryPrefix$id');
    final ids = await _readIndex();
    ids.remove(id);
    await _writeIndex(ids);
  }

  Future<void> _writeEntry(Connection c) =>
      _keyStore.writeJson('$_entryPrefix${c.id}', c.toJson());

  Future<List<String>> _readIndex() async {
    final raw = await _keyStore.readString(_indexKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List<Object?>).cast<String>().toList();
  }

  Future<void> _writeIndex(List<String> ids) =>
      _keyStore.writeString(_indexKey, jsonEncode(ids));

  Future<void> _appendIndex(String id) async {
    final ids = await _readIndex();
    if (!ids.contains(id)) ids.add(id);
    await _writeIndex(ids);
  }
}
