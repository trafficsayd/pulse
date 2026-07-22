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
/// - `tap` — TapTap: `{x, y}`
/// - `hold_start` / `hold_end` — HalfHeart
/// - `candle_light` / `candle_blow` — Candle
/// - `whisper_level` — Whisper: `{level}`
/// - `bell_ring` — Bell: `{intensity}`
/// - `ray_point` / `ray_end` — Ray: `{x, y}`
/// - `star` — Constellation: `{x, y}`
/// - `sneak` — Sneak In: `{sig, from?}` where `sig` is a stable signal id
///   from `kSneakSignals` and `from` is the optional sender connection id.
class ModeEvent {
  const ModeEvent({required this.type, this.data = const {}});

  /// Wire type for a Sneak In signal. Part of the protocol — do not rename.
  static const String typeSneak = 'sneak';

  /// JSON key carrying the sneak signal id inside [data].
  static const String sneakSignalKey = 'sig';

  /// JSON key carrying the optional sender id inside [data].
  static const String sneakSenderKey = 'from';

  /// Build a Sneak In event carrying a stable [signalId] (one of the ids in
  /// `kSneakSignals`) and, optionally, the [senderId] connection so the
  /// receiver can attribute the signal. Serialises through the exact same
  /// `{type, data}` machinery as every other event.
  factory ModeEvent.sneak(String signalId, {String? senderId}) {
    return ModeEvent(
      type: typeSneak,
      data: {
        sneakSignalKey: signalId,
        if (senderId != null) sneakSenderKey: senderId,
      },
    );
  }

  final String type;
  final Map<String, dynamic> data;

  /// True when this event is a Sneak In signal.
  bool get isSneak => type == typeSneak;

  /// The sneak signal id (from `kSneakSignals`) if this is a sneak event and
  /// carries a well-formed id, otherwise `null`.
  String? get sneakSignalId {
    final raw = data[sneakSignalKey];
    return raw is String ? raw : null;
  }

  /// The optional sender connection id attached to a sneak event, or `null`.
  String? get sneakSenderId {
    final raw = data[sneakSenderKey];
    return raw is String ? raw : null;
  }

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
