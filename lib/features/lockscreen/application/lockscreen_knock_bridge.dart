import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../session/application/mode_event.dart';

/// Android bridge for the keyguard-safe «Тук-Тук» surface.
abstract final class LockscreenKnockBridge {
  static const MethodChannel _channel =
      MethodChannel('app.pulse.lockscreen/knock');

  static const Set<String> _supportedEvents = {
    'tap',
    'knock_begin',
    'knock_hit',
    'knock_end',
    'knock_reply',
  };

  static void initialize({
    required Future<void> Function(ModeEvent event) onNativeReply,
  }) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'knockReply') return;
      final raw = call.arguments;
      if (raw is! Map) return;
      final data = <String, dynamic>{};
      for (final entry in raw.entries) {
        if (entry.key is String) data[entry.key as String] = entry.value;
      }
      await onNativeReply(ModeEvent(type: 'knock_reply', data: data));
    });
  }

  static Future<void> handleIncoming(
    ModeEvent event, {
    String? languageCode,
  }) async {
    if (!_supportedEvents.contains(event.type)) return;
    try {
      await _channel.invokeMethod<void>('knockEvent', {
        'type': event.type,
        'data': event.data,
        'languageCode': languageCode,
      });
    } on MissingPluginException {
      // Android-only presentation.
    } on PlatformException catch (error) {
      debugPrint('Lock-screen Knock bridge failed: ${error.code}');
    }
  }
}
