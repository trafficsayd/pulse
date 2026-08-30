enum CandleQualityProfile { high, balanced, economy }

/// Hysteretic frame-pressure controller.
///
/// It takes a sustained run of slow frames to lower quality and a much longer
/// healthy run to raise it again. A GC pause, app switch or shader warm-up can
/// therefore never change the appearance on its own.
class CandleQualityController {
  CandleQualityController({this.profile = CandleQualityProfile.high});

  CandleQualityProfile profile;
  int _pressure = 0;
  int _healthyFrames = 0;

  CandleQualityProfile record(Duration totalFrameTime) {
    final milliseconds = totalFrameTime.inMicroseconds / 1000;
    if (milliseconds > 28) {
      _pressure = (_pressure + 3).clamp(0, 60);
      _healthyFrames = 0;
    } else {
      _pressure = (_pressure - 1).clamp(0, 60);
      if (milliseconds < 18) {
        _healthyFrames++;
      } else {
        _healthyFrames = 0;
      }
    }

    if (_pressure >= 36 && profile != CandleQualityProfile.economy) {
      profile = profile == CandleQualityProfile.high
          ? CandleQualityProfile.balanced
          : CandleQualityProfile.economy;
      _pressure = 0;
      _healthyFrames = 0;
    } else if (_healthyFrames >= 360 && profile != CandleQualityProfile.high) {
      profile = profile == CandleQualityProfile.economy
          ? CandleQualityProfile.balanced
          : CandleQualityProfile.high;
      _pressure = 0;
      _healthyFrames = 0;
    }
    return profile;
  }
}
