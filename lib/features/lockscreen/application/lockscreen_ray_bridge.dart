import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../session/application/mode_event.dart';

/// Bridges incoming Ray events to Android's isolated lock-screen canvas.
///
/// The native side deliberately owns the lock-screen window: Flutter's main
/// activity never bypasses the keyguard and no private app navigation is
/// exposed while the device is locked. On iOS and other unsupported targets
/// these calls are harmless no-ops.
abstract final class LockscreenRayBridge {
  static const MethodChannel _channel =
      MethodChannel('app.pulse.lockscreen/ray');

  static const Set<String> _supportedEvents = {
    'ray_point',
    'ray_end',
    'ray_clear',
    'ray_canvas',
    'ray_card',
  };

  static Future<void> handleIncoming(
    ModeEvent event, {
    String? languageCode,
  }) async {
    if (!_supportedEvents.contains(event.type)) return;
    try {
      await _channel.invokeMethod<void>('rayEvent', {
        'type': event.type,
        'data': event.data,
        'languageCode': languageCode,
      });
    } on MissingPluginException {
      // Expected on iOS, desktop and widget tests.
    } on PlatformException catch (error) {
      debugPrint('Lock-screen Ray bridge failed: ${error.code}');
    }
  }

  static Future<bool> notificationsEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('notificationsEnabled') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      debugPrint('Notification status check failed: ${error.code}');
      return false;
    }
  }

  static Future<bool> presentationReady() async {
    try {
      return await _channel.invokeMethod<bool>(
            'lockscreenPresentationReady',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      debugPrint('Lock-screen presentation check failed: ${error.code}');
      return false;
    }
  }

  static Future<bool> requestNotifications() async {
    try {
      return await _channel.invokeMethod<bool>('requestNotifications') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      debugPrint('Notification permission request failed: ${error.code}');
      return false;
    }
  }

  static Future<void> setConnectionKeepAlive(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setConnectionKeepAlive', enabled);
    } on MissingPluginException {
      // Android-only lifecycle support.
    } on PlatformException catch (error) {
      debugPrint('Connection keep-alive failed: ${error.code}');
    }
  }
}
