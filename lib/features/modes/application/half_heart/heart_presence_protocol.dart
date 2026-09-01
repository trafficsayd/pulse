import '../../../session/application/mode_event.dart';
import 'heart_presence_models.dart';

/// Wire format for Half-Heart v2.
///
/// The outer event names stay `hold_start` / `hold_end`, so peers running the
/// original mode and app-wide routing continue to understand the gesture.
abstract final class HeartPresenceProtocol {
  static const int version = 2;
  static const Set<String> supportedTypes = {'hold_start', 'hold_end'};

  static ModeEvent encode(HeartHoldSignal signal) => ModeEvent(
        type: signal.held ? 'hold_start' : 'hold_end',
        data: {'v': version, ...signal.toMap()},
      );

  static HeartHoldSignal? tryParse(
    ModeEvent event, {
    required int receivedAtMs,
  }) {
    if (!supportedTypes.contains(event.type)) return null;
    final rawVersion = event.data['v'];
    if (rawVersion == null) {
      return HeartHoldSignal(
        eventId: 'legacy-${event.type}-$receivedAtMs',
        holdId: 'legacy',
        sequence: receivedAtMs,
        sentAtMs: receivedAtMs,
        held: event.type == 'hold_start',
        strength: .5,
        x: .5,
        y: .5,
        isLegacy: true,
      );
    }
    if (rawVersion != version) return null;
    final signal = HeartHoldSignal.tryFromMap(event.data);
    if (signal == null) return null;
    if (signal.held != (event.type == 'hold_start')) return null;
    return signal;
  }
}
