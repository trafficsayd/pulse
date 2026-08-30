import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../application/candle_dynamics.dart';

/// Quiet procedural fire audio. Android synthesises it locally so there is
/// no looping sample seam and nothing is sent across the connection.
abstract final class CandleSoundController {
  static const MethodChannel _channel = MethodChannel('app.pulse.audio/candle');

  static Future<void> ignite(CandleStyle style) =>
      _invoke('ignite', {'style': style.index});

  static Future<void> start(CandleStyle style, {double intensity = .5}) =>
      _invoke('start', {'style': style.index, 'intensity': intensity});

  static Future<void> update(double intensity) =>
      _invoke('update', {'intensity': intensity.clamp(0.0, 1.0)});

  static Future<void> extinguish() => _invoke('extinguish');

  static Future<void> stop() => _invoke('stop');

  static Future<void> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Expected on iOS, desktop and widget tests until native support exists.
    } on PlatformException catch (error) {
      if (kDebugMode) {
        debugPrint('Candle audio failed: ${error.code}');
      }
    }
  }
}
