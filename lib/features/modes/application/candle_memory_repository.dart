import '../../../core/storage/secure_key_store.dart';
import 'candle_dynamics.dart';

/// Persists the private half of a shared candle in encrypted platform
/// storage. The connection id scopes wax and wishes to one pair.
class CandleMemoryRepository {
  const CandleMemoryRepository({
    required SecureKeyStore store,
    required String connectionId,
  })  : _store = store,
        _connectionId = connectionId;

  final SecureKeyStore _store;
  final String _connectionId;

  String keyFor(CandleStyle style) =>
      'candle.memory.v2::$_connectionId::${style.name}';

  Future<CandleMemory> load(CandleStyle style) async {
    final json = await _store.readJson(keyFor(style));
    if (json != null) return CandleMemory.fromJson(json);
    return CandleMemory.fresh(seed: _seedFor(style));
  }

  Future<void> save(CandleStyle style, CandleMemory memory) =>
      _store.writeJson(keyFor(style), memory.toJson());

  int _seedFor(CandleStyle style) {
    var hash = 0x811c9dc5;
    for (final unit in '$_connectionId:${style.name}'.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
