import 'dart:convert';
import 'dart:typed_data';

/// Lightweight application-level event exchanged between two peers inside
/// an active mode session.
///
/// Encoded as compact JSON (`{'t': type, ...data}`) → UTF-8 bytes and then
/// sealed by `PairChannel` with AES-256-GCM. Mode event payloads are tiny
/// (a tap coordinate, a boolean, a mic level) so JSON overhead is negligible
/// after encryption.
///
/// Well-known event types:
/// - `tap` — TapTap v1 compatibility: `{x, y}`
/// - `knock_*` — TapTap v2: versioned tactile series and replies
/// - `hold_start` / `hold_end` — HalfHeart
/// - `candle_*` — shared Candle ritual (light, breath, shield, wish, memory)
/// - `whisper_level` — Whisper: `{level}`
/// - `bell_ring` — Bell: `{intensity}`
/// - `ray_point` / `ray_end` — Ray: `{x, y}`
/// - `star` — Constellation: `{x, y}`
class ModeEvent {
  const ModeEvent({required this.type, this.data = const {}});

  final String type;
  final Map<String, dynamic> data;

  /// Serialize to UTF-8 JSON bytes suitable for `PairChannel.send`.
  Uint8List encode() {
    final json = <String, dynamic>{'t': type, ...data};
    return Uint8List.fromList(utf8.encode(jsonEncode(json)));
  }

  /// Deserialize from UTF-8 JSON bytes received from `PairChannel.incoming`.
  factory ModeEvent.decode(Uint8List bytes) {
    final raw = utf8.decode(bytes);
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final type = map.remove('t') as String;
    return ModeEvent(type: type, data: map);
  }

  /// Decode from raw bytes, returning `null` on malformed input so the
  /// caller can silently skip corrupt frames.
  static ModeEvent? tryDecode(Uint8List bytes) {
    try {
      return ModeEvent.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'ModeEvent($type, $data)';
}
