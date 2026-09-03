import '../../primitives/flashlight_controller.dart';

/// Bounds torch exposure and keeps the visual screen flash as the automatic
/// fallback whenever the torch is missing, busy or denied by the OS.
class ThunderFlashCoordinator {
  ThunderFlashCoordinator(this._flashlight);

  final FlashlightController _flashlight;
  bool _available = false;
  bool _probed = false;
  bool _disposed = false;

  Future<bool> pulse({
    required int onMs,
    required int gapMs,
    required int count,
  }) async {
    if (_disposed) return false;
    if (!_probed) {
      _probed = true;
      try {
        _available = await _flashlight.isAvailable();
      } on Object {
        _available = false;
      }
    }
    if (!_available || _disposed) return false;
    try {
      await _flashlight.pulse(
        Duration(milliseconds: onMs.clamp(24, 90)),
        Duration(milliseconds: gapMs.clamp(50, 160)),
        count.clamp(1, 2),
      );
      return true;
    } on Object {
      _available = false;
      return false;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
  }

  Future<void> stop() async {
    try {
      await _flashlight.off();
    } on Object {
      // Camera ownership may already have moved to another application.
    }
  }
}
