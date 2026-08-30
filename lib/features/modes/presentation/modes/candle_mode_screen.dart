import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../capabilities/application/capability_providers.dart';
import '../../../capabilities/domain/device_capability.dart';
import '../../application/candle_dynamics.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import '../../primitives/candle_sound_controller.dart';
import '../../primitives/haptic_pattern_player.dart';
import '../../primitives/mic_level_stream.dart';
import '../../primitives/primitive_providers.dart';
import 'unsupported_mode_screen.dart';

/// "Candle" — touch to light a virtual candle, blow into the mic to
/// extinguish it. The partner's candle lights/extinguishes in sync.
///
/// Uses [MicLevelStream] for blow detection and [HapticPatternPlayer]
/// for gentle haptic feedback on light/extinguish events.
class CandleModeScreen extends ConsumerWidget {
  const CandleModeScreen({
    super.key,
    this.micLevelStream,
    this.hapticEngine,
    this.blowThreshold = 0.6,
    this.requiredBlowSamples = 3,
    this.calibrationDuration = const Duration(milliseconds: 1800),
  });

  final MicLevelStream? micLevelStream;
  final HapticEngine? hapticEngine;
  final double blowThreshold;
  final int requiredBlowSamples;
  final Duration calibrationDuration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final capsAsync = ref.watch(deviceCapabilitiesProvider);
    const required = {DeviceCapability.microphone};
    if (capsAsync.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.pulse),
        ),
      );
    }
    final caps = capsAsync.asData?.value ?? const DeviceCapabilities.none();
    if (!caps.hasAll(required)) {
      return UnsupportedModeScreen(
        title: t.modeCandle,
        missing: caps.missing(required),
      );
    }
    return _CandleModeView(
      micLevelStream: micLevelStream ?? ref.watch(micLevelStreamProvider),
      hapticEngine: hapticEngine ?? ref.watch(hapticEngineProvider),
      blowThreshold: blowThreshold,
      requiredBlowSamples: requiredBlowSamples,
      calibrationDuration: calibrationDuration,
    );
  }
}

class _CandleModeView extends ConsumerStatefulWidget {
  const _CandleModeView({
    required this.micLevelStream,
    required this.hapticEngine,
    required this.blowThreshold,
    required this.requiredBlowSamples,
    required this.calibrationDuration,
  });

  final MicLevelStream? micLevelStream;
  final HapticEngine? hapticEngine;
  final double blowThreshold;
  final int requiredBlowSamples;
  final Duration calibrationDuration;

  @override
  ConsumerState<_CandleModeView> createState() => _CandleModeViewState();
}

class _CandleModeViewState extends ConsumerState<_CandleModeView>
    with SingleTickerProviderStateMixin {
  late final MicLevelStream _mic;
  late final HapticEngine _engine;
  late final HapticPatternPlayer _player;
  late final CandleBreathAnalyzer _breathAnalyzer;
  late final AnimationController _flicker;
  StreamSubscription<MicLevel>? _micSub;
  StreamSubscription<ModeEvent>? _partnerSub;
  Timer? _partnerWindDecay;
  Timer? _sharedGlowTimer;
  bool _ownsMic = false;
  bool _ownsEngine = false;

  bool _isLit = false;
  bool _soundEnabled = true;
  bool _partnerWasBlowing = false;
  int _blowSamplesOverThreshold = 0;
  double _localWind = 0;
  double _partnerWind = 0;
  DateTime? _lastWindSentAt;
  double _lastWindSentLevel = 0;
  double _calibrationProgress = 0;
  bool _calibrated = false;
  DateTime? _lastSoundUpdateAt;
  DateTime? _lastLocalLightAt;
  DateTime? _sharedGlowUntil;
  DateTime? _extinguishedAt;
  CandleStyle _style = CandleStyle.classic;
  final Map<CandleStyle, ui.Image> _candleImages = {};
  ui.Image? _flameImage;

  @override
  void initState() {
    super.initState();
    if (widget.micLevelStream == null) {
      _mic = FakeMicLevelStream();
      _ownsMic = true;
    } else {
      _mic = widget.micLevelStream!;
    }
    if (widget.hapticEngine == null) {
      _engine = const NullHapticEngine();
      _ownsEngine = true;
    } else {
      _engine = widget.hapticEngine!;
    }
    _player = HapticPatternPlayer(_engine);
    _breathAnalyzer = CandleBreathAnalyzer(
      calibrationDuration: widget.calibrationDuration,
    );
    _calibrated = _breathAnalyzer.calibrated;
    _flicker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _micSub = _mic.levels.listen(_onMicLevel);
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
        .where((e) => e.type == 'candle_light' || e.type == 'candle_blow')
        .listen(_onPartnerEvent);
    unawaited(_loadCandleImages());
  }

  Future<void> _loadCandleImages() async {
    const assets = {
      CandleStyle.classic: 'assets/candles/candle_classic_unlit.png',
      CandleStyle.glass: 'assets/candles/candle_glass_unlit.png',
      CandleStyle.violet: 'assets/candles/candle_violet_unlit.png',
    };
    final decoded = <CandleStyle, ui.Image>{};
    ui.Image? decodedFlame;
    try {
      for (final entry in assets.entries) {
        final bytes = await rootBundle.load(entry.value);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        decoded[entry.key] = frame.image;
      }
      final flameBytes = await rootBundle.load(
        'assets/candles/candle_flame.png',
      );
      final flameCodec = await ui.instantiateImageCodec(
        flameBytes.buffer.asUint8List(
          flameBytes.offsetInBytes,
          flameBytes.lengthInBytes,
        ),
      );
      final flameFrame = await flameCodec.getNextFrame();
      flameCodec.dispose();
      decodedFlame = flameFrame.image;
    } on Object {
      // The vector fallback below keeps the mode usable if an asset cannot
      // be decoded on an unusually constrained device.
      for (final image in decoded.values) {
        image.dispose();
      }
      decodedFlame?.dispose();
      return;
    }
    if (!mounted) {
      for (final image in decoded.values) {
        image.dispose();
      }
      decodedFlame.dispose();
      return;
    }
    setState(() {
      _candleImages.addAll(decoded);
      _flameImage = decodedFlame;
    });
  }

  void _onPartnerEvent(ModeEvent event) {
    if (!mounted) return;
    if (event.type == 'candle_light') {
      final styleIndex = (event.data['style'] as num?)?.toInt();
      if (styleIndex != null &&
          styleIndex >= 0 &&
          styleIndex < CandleStyle.values.length) {
        setState(() => _style = CandleStyle.values[styleIndex]);
      }
      final now = DateTime.now();
      final shared = _isLit &&
          _lastLocalLightAt != null &&
          now.difference(_lastLocalLightAt!) < const Duration(seconds: 2);
      _lightCandle();
      if (shared) {
        setState(() => _sharedGlowUntil = now.add(const Duration(seconds: 2)));
        _sharedGlowTimer?.cancel();
        _sharedGlowTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _sharedGlowUntil = null);
        });
        unawaited(_player.play(HapticPatterns.candleTogether));
      }
    } else if (event.type == 'candle_blow') {
      final level = (event.data['level'] as num?)?.toDouble() ?? 0;
      final extinguished =
          event.data['extinguished'] as bool? ?? level >= widget.blowThreshold;
      setState(() {
        final target = level.clamp(0.0, 1.0);
        _partnerWind = _partnerWind * 0.34 + target * 0.66;
      });
      if (level >= .16 && !_partnerWasBlowing) {
        _partnerWasBlowing = true;
        unawaited(_player.play(HapticPatterns.candleBreath));
      } else if (level < .08) {
        _partnerWasBlowing = false;
      }
      _partnerWindDecay?.cancel();
      if (!extinguished && level > 0) {
        _partnerWindDecay = Timer(const Duration(milliseconds: 450), () {
          if (mounted) {
            setState(() {
              _partnerWind = 0;
              _partnerWasBlowing = false;
            });
          }
        });
      }
      if (extinguished) _extinguishCandle();
    }
  }

  void _onMicLevel(MicLevel sample) {
    if (!mounted) return;
    final reading = _breathAnalyzer.add(
      level: sample.level01,
      noiseLikeness: sample.noiseLikeness,
      at: sample.timestamp,
    );
    if (_calibrated != reading.calibrated ||
        (_calibrationProgress - reading.calibrationProgress).abs() >= .04) {
      setState(() {
        _calibrated = reading.calibrated;
        _calibrationProgress = reading.calibrationProgress;
      });
    }
    if (!_isLit || !reading.calibrated) return;
    final level = reading.pressure;
    // Microphone samples are noisy. A short low-pass filter keeps the flame
    // organic while still reacting quickly enough to a real breath.
    setState(() => _localWind = _localWind * 0.36 + level * 0.64);
    _sendWind(
      level,
      confidence: reading.confidence,
      extinguished: false,
      at: sample.timestamp,
    );
    _updateSound(level, sample.timestamp);
    final threshold =
        widget.blowThreshold * _style.character.extinguishResistance;
    if (level > threshold) {
      _blowSamplesOverThreshold++;
      if (_blowSamplesOverThreshold >= widget.requiredBlowSamples) {
        _extinguishCandle();
        _sendWind(
          level,
          confidence: reading.confidence,
          extinguished: true,
          at: sample.timestamp,
          force: true,
        );
        _blowSamplesOverThreshold = 0;
      }
    } else {
      // Pressure dissipates rather than disappearing in one sample, which
      // prevents a brief microphone dip from making sustained breath feel
      // unresponsive.
      _blowSamplesOverThreshold = math.max(0, _blowSamplesOverThreshold - 1);
    }
  }

  void _sendWind(
    double level, {
    required double confidence,
    required bool extinguished,
    required DateTime at,
    bool force = false,
  }) {
    // A quiet microphone produces an endless stream of zero-value PCM
    // chunks. Send one transition back to zero after real breath, then stay
    // silent so the transport and the partner's notification layer do not
    // get flooded while the candle is simply burning.
    if (!force && level <= 0.02 && _lastWindSentLevel <= 0.02) return;
    // Microphone chunks can arrive dozens of times per second. Ten updates
    // per second are enough for a fluid flame and protect the data channel.
    if (!force &&
        _lastWindSentAt != null &&
        at.difference(_lastWindSentAt!) < const Duration(milliseconds: 100)) {
      return;
    }
    _lastWindSentAt = at;
    _lastWindSentLevel = level;
    unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
          type: 'candle_blow',
          data: {
            'level': level,
            'confidence': confidence,
            'extinguished': extinguished,
          },
        )));
  }

  void _updateSound(double pressure, DateTime at) {
    if (!_soundEnabled) return;
    if (_lastSoundUpdateAt != null &&
        at.difference(_lastSoundUpdateAt!) <
            const Duration(milliseconds: 180)) {
      return;
    }
    _lastSoundUpdateAt = at;
    unawaited(CandleSoundController.update(
      (.34 + pressure * .66) * _style.character.crackle,
    ));
  }

  void _lightCandle() {
    if (_isLit) return;
    setState(() {
      _isLit = true;
      _extinguishedAt = null;
      _blowSamplesOverThreshold = 0;
    });
    HapticFeedback.lightImpact();
    unawaited(_player.play(HapticPatterns.tap));
    if (_soundEnabled) {
      unawaited(CandleSoundController.ignite(_style));
    }
  }

  void _extinguishCandle() {
    if (!_isLit) return;
    setState(() {
      _isLit = false;
      _localWind = 0;
      _partnerWind = 0;
      _extinguishedAt = DateTime.now();
    });
    HapticFeedback.mediumImpact();
    unawaited(_player.play(HapticPatterns.candleOut));
    if (_soundEnabled) unawaited(CandleSoundController.extinguish());
  }

  void _onTap() {
    if (!_isLit) {
      _lastLocalLightAt = DateTime.now();
      _lightCandle();
      ref.read(modeEventBusProvider).send(ModeEvent(
            type: 'candle_light',
            data: {'style': _style.index},
          ));
    }
  }

  void _selectStyle(CandleStyle style) {
    if (_style == style) return;
    setState(() => _style = style);
    if (_isLit && _soundEnabled) {
      unawaited(CandleSoundController.start(
        style,
        intensity: style.character.crackle,
      ));
    }
    if (_isLit) {
      unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
            type: 'candle_light',
            data: {'style': style.index},
          )));
    }
  }

  void _toggleSound() {
    setState(() => _soundEnabled = !_soundEnabled);
    if (_soundEnabled && _isLit) {
      unawaited(CandleSoundController.start(
        _style,
        intensity: _style.character.crackle,
      ));
    } else {
      unawaited(CandleSoundController.stop());
    }
  }

  @override
  void dispose() {
    _micSub?.cancel();
    _partnerSub?.cancel();
    _partnerWindDecay?.cancel();
    _sharedGlowTimer?.cancel();
    _flicker.dispose();
    unawaited(_player.stop());
    if (_ownsMic) unawaited(_mic.dispose());
    if (_ownsEngine) unawaited(_engine.cancel());
    for (final image in _candleImages.values) {
      image.dispose();
    }
    _flameImage?.dispose();
    unawaited(CandleSoundController.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onTap,
                child: AnimatedBuilder(
                  animation: _flicker,
                  builder: (context, _) {
                    final extinguishedAt = _extinguishedAt;
                    final smokeProgress = extinguishedAt == null
                        ? 1.0
                        : DateTime.now()
                                .difference(extinguishedAt)
                                .inMilliseconds /
                            4200;
                    final forces = CandleForces.resolve(
                      localPressure: _localWind,
                      partnerPressure: _partnerWind,
                      style: _style,
                    );
                    final sharedUntil = _sharedGlowUntil;
                    final sharedGlow = sharedUntil == null
                        ? 0.0
                        : (sharedUntil
                                    .difference(DateTime.now())
                                    .inMilliseconds /
                                2000)
                            .clamp(0.0, 1.0)
                            .toDouble();
                    return CustomPaint(
                      painter: _CandlePainter(
                        isLit: _isLit,
                        flicker: _flicker.value,
                        forces: forces,
                        localWind: _localWind,
                        partnerWind: _partnerWind,
                        sharedGlow: sharedGlow,
                        smokeProgress: smokeProgress.clamp(0.0, 1.0),
                        style: _style,
                        candleImage: _candleImages[_style],
                        flameImage: _flameImage,
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 22,
              child: _CandleStylePicker(
                selected: _style,
                onSelected: _selectStyle,
              ),
            ),
            Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  _calibrated
                      ? (_isLit ? t.candleBlowHint : t.candleTouchHint)
                      : t.candleCalibrating,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (!_calibrated)
              Positioned(
                top: 42,
                left: 84,
                right: 84,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    value: _calibrationProgress,
                    color: AppColors.pulse,
                    backgroundColor: Colors.white.withValues(alpha: .08),
                  ),
                ),
              ),
            if (_sharedGlowUntil != null &&
                _sharedGlowUntil!.isAfter(DateTime.now()))
              Positioned(
                top: 52,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    t.candleTogether,
                    style: const TextStyle(
                      color: Color(0xFFFFD58A),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .8,
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                tooltip: _soundEnabled ? t.candleSoundOff : t.candleSoundOn,
                color: AppColors.textSecondary,
                icon: Icon(
                  _soundEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                ),
                onPressed: _toggleSound,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: t.hubExit,
                color: AppColors.textSecondary,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandlePainter extends CustomPainter {
  _CandlePainter({
    required this.isLit,
    required this.flicker,
    required this.forces,
    required this.localWind,
    required this.partnerWind,
    required this.sharedGlow,
    required this.smokeProgress,
    required this.style,
    required this.candleImage,
    required this.flameImage,
  });

  final bool isLit;
  final double flicker;
  final CandleForces forces;
  final double localWind;
  final double partnerWind;
  final double sharedGlow;
  final double smokeProgress;
  final CandleStyle style;
  final ui.Image? candleImage;
  final ui.Image? flameImage;

  double get wind => forces.lean;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = flicker * math.pi * 2;
    // Keep the object comfortably inside the portrait composition. Its size
    // is tied to screen width (not a cropped media viewport), while the
    // vertical anchor leaves room for the complete flame, base and shadow.
    final center = Offset(size.width / 2, size.height * 0.46);
    final candleWidth =
        size.shortestSide * (style == CandleStyle.glass ? 0.31 : 0.255);
    final candleHeight =
        size.shortestSide * (style == CandleStyle.glass ? 0.39 : 0.46);

    final bodyRect = Rect.fromCenter(
      center: center + Offset(0, candleHeight * 0.23),
      width: candleWidth,
      height: candleHeight,
    );
    final image = candleImage;
    final photoreal = image == null ? null : _photorealLayout(size, image);
    final visualBody = photoreal?.visualBounds ?? bodyRect;
    final wickBase = photoreal?.wickBase ?? Offset(center.dx, bodyRect.top - 3);

    _drawAtmosphere(canvas, size, wickBase, phase);
    _drawSurfaceShadow(canvas, visualBody, visualBody.width);

    if (image != null && photoreal != null) {
      _drawPhotorealCandle(canvas, image, photoreal.imageRect);
      _drawPhotorealRelighting(canvas, photoreal, phase);
    } else {
      switch (style) {
        case CandleStyle.classic:
          _drawPillar(
            canvas,
            bodyRect,
            candleWidth,
            phase,
            const _WaxPalette(
              dark: Color(0xFF8A6A48),
              mid: Color(0xFFE7D0AA),
              light: Color(0xFFFFF8E9),
              pool: Color(0xFFFFEAC8),
            ),
          );
          break;
        case CandleStyle.glass:
          _drawGlassCandle(canvas, bodyRect, candleWidth, phase);
          break;
        case CandleStyle.violet:
          _drawPillar(
            canvas,
            bodyRect,
            candleWidth,
            phase,
            const _WaxPalette(
              dark: Color(0xFF32134F),
              mid: Color(0xFF8150B9),
              light: Color(0xFFD8B9FF),
              pool: Color(0xFFBA8BEA),
            ),
            crystalline: true,
          );
          break;
      }
      _drawWick(canvas, wickBase);
    }

    _drawAirflow(canvas, size, wickBase, phase);

    if (isLit) {
      _drawFlame(canvas, wickBase, visualBody, phase);
    } else {
      _drawExtinguishedWick(canvas, wickBase, phase);
    }
  }

  _PhotorealCandleLayout _photorealLayout(Size size, ui.Image image) {
    final widthFactor = style == CandleStyle.glass ? .48 : .55;
    final imageWidth = size.shortestSide * widthFactor;
    final imageHeight = imageWidth * image.height / image.width;
    final centerY = size.height * (style == CandleStyle.glass ? .49 : .50);
    final imageRect = Rect.fromCenter(
      center: Offset(size.width / 2, centerY),
      width: imageWidth,
      height: imageHeight,
    );

    final normalized = switch (style) {
      CandleStyle.classic => const (
          left: .21,
          top: .08,
          right: .79,
          bottom: .92,
          wickY: .195,
        ),
      CandleStyle.glass => const (
          left: .055,
          top: .045,
          right: .945,
          bottom: .95,
          wickY: .20,
        ),
      CandleStyle.violet => const (
          left: .13,
          top: .075,
          right: .87,
          bottom: .93,
          wickY: .185,
        ),
    };
    final visualBounds = Rect.fromLTRB(
      imageRect.left + imageRect.width * normalized.left,
      imageRect.top + imageRect.height * normalized.top,
      imageRect.left + imageRect.width * normalized.right,
      imageRect.top + imageRect.height * normalized.bottom,
    );
    final wickBase = Offset(
      imageRect.center.dx,
      imageRect.top + imageRect.height * normalized.wickY,
    );
    return _PhotorealCandleLayout(
      imageRect: imageRect,
      visualBounds: visualBounds,
      wickBase: wickBase,
    );
  }

  void _drawPhotorealCandle(Canvas canvas, ui.Image image, Rect imageRect) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      imageRect,
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high,
    );
  }

  void _drawPhotorealRelighting(
    Canvas canvas,
    _PhotorealCandleLayout layout,
    double phase,
  ) {
    if (!isLit) return;
    final character = style.character;
    final pulse = 1 + math.sin(phase * 2.3) * .035 * character.flickerAmount;
    final bounds = layout.visualBounds;
    final warm = Color.lerp(
      const Color(0xFFFF9D45),
      const Color(0xFFC27CFF),
      style == CandleStyle.violet ? .34 : 0,
    )!;
    canvas.saveLayer(bounds.inflate(18), Paint());
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, Radius.circular(bounds.width * .12)),
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            warm.withValues(alpha: .26 * pulse * character.warmth),
            warm.withValues(alpha: .08 * character.warmth),
            Colors.transparent,
          ],
          stops: const [0, .36, 1],
        ).createShader(bounds),
    );
    canvas.restore();

    final pool = Rect.fromCenter(
      center: layout.wickBase + const Offset(0, 6),
      width: bounds.width * (style == CandleStyle.glass ? .82 : .68),
      height: bounds.width * .23,
    );
    canvas.drawOval(
      pool,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFF1B0).withValues(alpha: .30 * pulse),
            warm.withValues(alpha: .17 * pulse),
            Colors.transparent,
          ],
        ).createShader(pool),
    );

    if (style == CandleStyle.glass) {
      final x = bounds.left + bounds.width * (.20 + math.sin(phase) * .018);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, bounds.top + 12, 4, bounds.height * .62),
          const Radius.circular(4),
        ),
        Paint()
          ..blendMode = BlendMode.screen
          ..color = const Color(0xFFFFD79A).withValues(alpha: .28 * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
  }

  void _drawAtmosphere(
    Canvas canvas,
    Size size,
    Offset wickBase,
    double phase,
  ) {
    final character = style.character;
    final pulse = 0.96 +
        math.sin(phase * 1.7) * 0.04 * character.flickerAmount +
        forces.turbulence * math.sin(phase * 5.3) * .025;
    final center = wickBase + Offset(wind * 8, -34);
    final rect =
        Rect.fromCircle(center: center, radius: size.shortestSide * .72);
    final warmAlpha =
        isLit ? (0.20 + sharedGlow * .12) * pulse * character.warmth : 0.0;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.16),
          radius: 0.84,
          colors: [
            Color.lerp(
              const Color(0xFFFFA34A),
              const Color(0xFFC380FF),
              style == CandleStyle.violet ? .24 : 0,
            )!
                .withValues(alpha: warmAlpha),
            const Color(0xFF7132A6).withValues(alpha: isLit ? 0.10 : 0.04),
            Colors.transparent,
          ],
          stops: const [0, 0.42, 1],
        ).createShader(rect),
    );

    if (!isLit) return;
    canvas.drawCircle(
      center,
      118,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFC36A).withValues(alpha: 0.15 * pulse),
            const Color(0xFFFF8A38).withValues(alpha: 0.045 * pulse),
            Colors.transparent,
          ],
          stops: const [0, .38, 1],
        ).createShader(Rect.fromCircle(center: center, radius: 118)),
    );
  }

  void _drawSurfaceShadow(Canvas canvas, Rect bodyRect, double candleWidth) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(bodyRect.center.dx - wind * 4, bodyRect.bottom + 9),
        width: candleWidth * 1.7,
        height: candleWidth * .34,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.52)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    if (!isLit) return;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(bodyRect.center.dx + wind * 8, bodyRect.bottom + 7),
        width: candleWidth * 1.25,
        height: candleWidth * .22,
      ),
      Paint()
        ..color = const Color(0xFFFF9E43).withValues(alpha: 0.13)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
  }

  void _drawPillar(
    Canvas canvas,
    Rect bodyRect,
    double candleWidth,
    double phase,
    _WaxPalette palette, {
    bool crystalline = false,
  }) {
    final body = RRect.fromRectAndRadius(bodyRect, const Radius.circular(8));
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          colors: [
            palette.dark,
            palette.mid,
            palette.light,
            palette.mid,
            palette.dark,
          ],
          stops: const [0, .19, .47, .72, 1],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(bodyRect),
    );

    // Fine vertical wax texture breaks the perfectly digital gradient.
    final texture = Paint()
      ..strokeWidth = .7
      ..color = Colors.white.withValues(alpha: crystalline ? .06 : .09);
    for (var i = 1; i < 9; i++) {
      final x = bodyRect.left + bodyRect.width * i / 10;
      final wobble = math.sin(i * 2.7) * 1.8;
      canvas.drawLine(
        Offset(x, bodyRect.top + 14 + wobble),
        Offset(x + wobble, bodyRect.bottom - 8),
        texture,
      );
    }

    // Rounded top, recessed molten pool and irregular rim create depth.
    final topOval = Rect.fromCenter(
      center: Offset(bodyRect.center.dx, bodyRect.top + 2),
      width: candleWidth,
      height: candleWidth * .31,
    );
    canvas.drawOval(topOval, Paint()..color = palette.light);
    final poolRect = Rect.fromCenter(
      center: topOval.center + const Offset(0, 1),
      width: candleWidth * .69,
      height: candleWidth * .18,
    );
    canvas.drawOval(
      poolRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            palette.pool.withValues(alpha: isLit ? .98 : .72),
            palette.mid.withValues(alpha: .88),
          ],
        ).createShader(poolRect),
    );
    canvas.drawArc(
      topOval.deflate(1),
      math.pi * .04,
      math.pi * .9,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );

    final drip = Path()
      ..moveTo(bodyRect.right - candleWidth * .26, bodyRect.top + 3)
      ..cubicTo(
        bodyRect.right - candleWidth * .20,
        bodyRect.top + 22,
        bodyRect.right - candleWidth * .26,
        bodyRect.top + 49,
        bodyRect.right - candleWidth * .35,
        bodyRect.top + 52,
      )
      ..cubicTo(
        bodyRect.right - candleWidth * .43,
        bodyRect.top + 38,
        bodyRect.right - candleWidth * .41,
        bodyRect.top + 17,
        bodyRect.right - candleWidth * .43,
        bodyRect.top + 5,
      )
      ..close();
    canvas.drawPath(drip, Paint()..color = palette.mid.withValues(alpha: .72));

    if (crystalline) {
      final glint = Paint()
        ..color = const Color(0xFFECCFFF).withValues(alpha: .55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      for (var i = 0; i < 7; i++) {
        final x = bodyRect.left + 12 + (i * 17.0) % (bodyRect.width - 24);
        final y = bodyRect.top + 28 + (i * 31.0) % (bodyRect.height - 42);
        final r = i.isEven ? 1.4 : .8;
        canvas.drawCircle(Offset(x, y), r, glint);
      }
    }

    if (isLit) {
      canvas.drawOval(
        Rect.fromCenter(
          center: bodyRect.topCenter + Offset(wind * 3, 8),
          width: candleWidth * .78,
          height: candleWidth * .32,
        ),
        Paint()
          ..color = const Color(0xFFFFB85B).withValues(alpha: .14)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  void _drawGlassCandle(
    Canvas canvas,
    Rect bodyRect,
    double candleWidth,
    double phase,
  ) {
    final radius = Radius.circular(candleWidth * .28);
    final glass = RRect.fromRectAndRadius(bodyRect, radius);
    final waxRect = Rect.fromLTRB(
      bodyRect.left + 7,
      bodyRect.top + bodyRect.height * .31,
      bodyRect.right - 7,
      bodyRect.bottom - 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(waxRect, Radius.circular(candleWidth * .20)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFB58ADD), Color(0xFF7847A6), Color(0xFF3C1D58)],
          stops: [0, .48, 1],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(waxRect),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(waxRect.center.dx, waxRect.top + 2),
        width: waxRect.width,
        height: candleWidth * .18,
      ),
      Paint()..color = const Color(0xFFD7B4F4).withValues(alpha: .88),
    );
    canvas.drawRRect(
      glass,
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFF9B86C8).withValues(alpha: .18),
            Colors.white.withValues(alpha: .20),
            const Color(0xFF38234F).withValues(alpha: .16),
            Colors.white.withValues(alpha: .08),
          ],
          stops: const [0, .22, .62, 1],
        ).createShader(bodyRect),
    );
    canvas.drawRRect(
      glass,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: .38),
    );

    // Thick glass rim and asymmetric specular streaks.
    final rim = Rect.fromCenter(
      center: Offset(bodyRect.center.dx, bodyRect.top + 4),
      width: bodyRect.width,
      height: candleWidth * .26,
    );
    canvas.drawOval(
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: .18),
            Colors.white.withValues(alpha: .65),
            const Color(0xFF725694).withValues(alpha: .35),
          ],
        ).createShader(rim),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          bodyRect.left + 11,
          bodyRect.top + 20,
          4,
          bodyRect.height * .58,
        ),
        const Radius.circular(4),
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: .34)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          bodyRect.right - 12,
          bodyRect.top + 35,
          2,
          bodyRect.height * .33,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = Colors.white.withValues(alpha: .13),
    );

    if (isLit) {
      final reflection = Offset(
        bodyRect.center.dx + math.sin(phase * 1.3) * 2,
        waxRect.top + 9,
      );
      canvas.drawCircle(
        reflection,
        candleWidth * .36,
        Paint()
          ..color = const Color(0xFFFFA84D).withValues(alpha: .12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }
  }

  void _drawWick(Canvas canvas, Offset wickBase) {
    final wick = Path()
      ..moveTo(wickBase.dx, wickBase.dy + 13)
      ..quadraticBezierTo(
        wickBase.dx - 1.5,
        wickBase.dy + 5,
        wickBase.dx + wind * 1.5,
        wickBase.dy,
      );
    canvas.drawPath(
      wick,
      Paint()
        ..color = const Color(0xFF251B1A)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawFlame(
    Canvas canvas,
    Offset wickBase,
    Rect bodyRect,
    double phase,
  ) {
    final character = style.character;
    final gust = forces.pressure.clamp(0.0, 1.0);
    final unstable = forces.turbulence;
    final turbulence =
        (math.sin(phase * 1.9) * 2.2 + math.sin(phase * 3.7 + 1.2) * 1.0) *
                character.flickerAmount +
            math.sin(phase * 7.1) * unstable * 3.4;
    final height = 45.0 * forces.heightScale +
        math.sin(phase * 2.3) * 2.7 * character.flickerAmount;
    final width = 16.5 +
        gust * 5 +
        unstable * 4 +
        math.cos(phase * 2.8) * 1.2 * character.flickerAmount;
    final lean = wind * (25 + gust * 15) + turbulence;
    final base = wickBase + const Offset(0, 2);
    final tip = base + Offset(lean, -height);
    final glowCenter = Offset.lerp(base, tip, .52)!;

    canvas.drawCircle(
      glowCenter,
      90 - gust * 13 + sharedGlow * 16,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFC35F).withValues(
              alpha: .40 - gust * .09 + sharedGlow * .08,
            ),
            const Color(0xFFFF8738).withValues(alpha: .13 - gust * .04),
            Colors.transparent,
          ],
          stops: const [0, .34, 1],
        ).createShader(
          Rect.fromCircle(
            center: glowCenter,
            radius: 90 - gust * 13 + sharedGlow * 16,
          ),
        ),
    );

    final sprite = flameImage;
    if (sprite != null) {
      _drawFlameSprite(
        canvas,
        sprite,
        base: base,
        height: height,
        width: width,
        gust: gust,
        phase: phase,
      );
    } else {
      final bounds = Rect.fromLTRB(
        math.min(base.dx, tip.dx) - width,
        tip.dy,
        math.max(base.dx, tip.dx) + width,
        base.dy + 5,
      );
      final outer = _flamePath(base: base, tip: tip, width: width);
      canvas.drawPath(
        outer,
        Paint()
          ..shader = const LinearGradient(
            colors: [
              Color(0xFFFFF4A8),
              Color(0xFFFFC54D),
              Color(0xFFFF7B2F),
              Color(0xFFE43D18),
            ],
            stops: [0, .35, .76, 1],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(bounds),
      );

      final innerTip = Offset.lerp(base, tip, .64)! + Offset(wind * 2, 2);
      final inner = _flamePath(
        base: base + const Offset(0, 1),
        tip: innerTip,
        width: width * .43,
      );
      canvas.drawPath(
        inner,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = const LinearGradient(
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFFFF0A0),
              Color(0xFFFFA33C),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(bounds),
      );

      canvas.drawOval(
        Rect.fromCenter(center: base, width: width * .78, height: 9),
        Paint()
          ..color = const Color(0xFF769CFF).withValues(alpha: .62)
          ..blendMode = BlendMode.plus,
      );
    }

    _drawInnerFlame(canvas, base, tip, width, phase, unstable);
    _drawHeatShimmer(canvas, tip, phase, unstable);

    // Warm reflection in the molten wax/glass immediately below the flame.
    canvas.drawOval(
      Rect.fromCenter(
        center: bodyRect.topCenter + const Offset(0, 6),
        width: bodyRect.width * .72,
        height: bodyRect.width * .24,
      ),
      Paint()
        ..color = const Color(0xFFFFB349).withValues(alpha: .18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
  }

  void _drawInnerFlame(
    Canvas canvas,
    Offset base,
    Offset tip,
    double width,
    double phase,
    double unstable,
  ) {
    final innerTip = Offset.lerp(base, tip, .58)! +
        Offset(math.sin(phase * 3.1) * (1 + unstable * 2), 2);
    final inner = _flamePath(
      base: base + const Offset(0, 1),
      tip: innerTip,
      width: width * .34,
    );
    final bounds = Rect.fromPoints(
      Offset(base.dx - width, tip.dy),
      Offset(base.dx + width, base.dy + 4),
    );
    canvas.drawPath(
      inner,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: .82),
            const Color(0xFFFFE985).withValues(alpha: .72),
            const Color(0xFFFF9A36).withValues(alpha: .38),
          ],
        ).createShader(bounds),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: base + const Offset(0, 1.8),
        width: width * .48,
        height: 4.2,
      ),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = const RadialGradient(
          colors: [Color(0xA0B8D2FF), Color(0x705278FF), Colors.transparent],
          stops: [0, .46, 1],
        ).createShader(Rect.fromCircle(center: base, radius: width)),
    );
  }

  void _drawHeatShimmer(
    Canvas canvas,
    Offset tip,
    double phase,
    double unstable,
  ) {
    for (var i = 0; i < 3; i++) {
      final rise = 18.0 + i * 14;
      final drift =
          math.sin(phase * (1.1 + i * .17) + i * 2.1) * (3 + unstable * 5);
      final path = Path()
        ..moveTo(tip.dx, tip.dy - 2 - i * 2)
        ..quadraticBezierTo(
          tip.dx - drift,
          tip.dy - rise * .55,
          tip.dx + drift,
          tip.dy - rise,
        );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFFFFD69A).withValues(alpha: .045 - i * .01)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
      );
    }
  }

  void _drawFlameSprite(
    Canvas canvas,
    ui.Image image, {
    required Offset base,
    required double height,
    required double width,
    required double gust,
    required double phase,
  }) {
    final spriteHeight = height * (1.50 - gust * .18);
    final spriteWidth = width * (3.0 + gust * .42);
    final angle = wind * (.28 + gust * .12) + math.sin(phase * 2.1) * .018;
    canvas.save();
    canvas.translate(base.dx, base.dy + 2);
    canvas.rotate(angle);
    canvas.scale(1 + gust * .18, 1 - gust * .16);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTRB(
        -spriteWidth / 2,
        -spriteHeight,
        spriteWidth / 2,
        4,
      ),
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  Path _flamePath({
    required Offset base,
    required Offset tip,
    required double width,
  }) {
    final direction = tip - base;
    return Path()
      ..moveTo(base.dx, base.dy + 3)
      ..cubicTo(
        base.dx - width * .85,
        base.dy + direction.dy * .24,
        tip.dx - width * .34,
        tip.dy - direction.dy * .16,
        tip.dx,
        tip.dy,
      )
      ..cubicTo(
        tip.dx + width * .42,
        tip.dy - direction.dy * .18,
        base.dx + width * .86,
        base.dy + direction.dy * .27,
        base.dx,
        base.dy + 3,
      )
      ..close();
  }

  void _drawAirflow(
    Canvas canvas,
    Size size,
    Offset wickBase,
    double phase,
  ) {
    void stream(double strength, bool fromLeft) {
      if (strength < .06) return;
      final alpha = (.10 + strength * .22).clamp(0.0, .30);
      final direction = fromLeft ? 1.0 : -1.0;
      final paint = Paint()
        ..color = const Color(0xFFDCCBFF).withValues(alpha: alpha)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .6);
      for (var i = 0; i < 4; i++) {
        final travel = (flicker * (1.15 + i * .08) + i * .23) % 1;
        final startX = fromLeft
            ? size.width * .10 + travel * size.width * .30
            : size.width * .90 - travel * size.width * .30;
        final y = wickBase.dy - 42 + i * 14 + math.sin(phase + i) * 3;
        final length = 10 + strength * 18;
        canvas.drawLine(
          Offset(startX, y),
          Offset(startX + direction * length, y + math.sin(i * 1.8) * 2),
          paint,
        );
      }
    }

    stream(localWind, true);
    stream(partnerWind, false);
  }

  void _drawExtinguishedWick(Canvas canvas, Offset wickBase, double phase) {
    final emberAlpha = smokeProgress < .30 ? (1 - smokeProgress / .30) : 0.0;
    if (emberAlpha > 0) {
      canvas.drawCircle(
        wickBase,
        8,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFF7A37).withValues(alpha: emberAlpha * .75),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: wickBase, radius: 8)),
      );
    }

    if (smokeProgress >= 1) return;
    final fade = math.pow(1 - smokeProgress, 1.45).toDouble();
    final rise = 24 + smokeProgress * 88;
    final drift = math.sin(phase * .55 + smokeProgress * 4) * 12 +
        wind * 20 +
        smokeProgress * 8;
    for (var i = 0; i < 3; i++) {
      final offset = (i - 1) * 3.0;
      final smoke = Path()
        ..moveTo(wickBase.dx + offset, wickBase.dy - 1)
        ..cubicTo(
          wickBase.dx - 9 + offset,
          wickBase.dy - rise * .28,
          wickBase.dx + 13 + drift * .35,
          wickBase.dy - rise * .56,
          wickBase.dx + drift + offset,
          wickBase.dy - rise,
        );
      canvas.drawPath(
        smoke,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2 - i * .75
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFC9BED4).withValues(
            alpha: fade * (.18 - i * .035),
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.5 + i),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) =>
      old.isLit != isLit ||
      old.flicker != flicker ||
      old.forces.lean != forces.lean ||
      old.forces.pressure != forces.pressure ||
      old.forces.turbulence != forces.turbulence ||
      old.forces.heightScale != forces.heightScale ||
      old.localWind != localWind ||
      old.partnerWind != partnerWind ||
      old.sharedGlow != sharedGlow ||
      old.smokeProgress != smokeProgress ||
      old.candleImage != candleImage ||
      old.flameImage != flameImage ||
      old.style != style;
}

class _PhotorealCandleLayout {
  const _PhotorealCandleLayout({
    required this.imageRect,
    required this.visualBounds,
    required this.wickBase,
  });

  final Rect imageRect;
  final Rect visualBounds;
  final Offset wickBase;
}

class _WaxPalette {
  const _WaxPalette({
    required this.dark,
    required this.mid,
    required this.light,
    required this.pool,
  });

  final Color dark;
  final Color mid;
  final Color light;
  final Color pool;
}

class _CandleStylePicker extends StatelessWidget {
  const _CandleStylePicker({required this.selected, required this.onSelected});

  final CandleStyle selected;
  final ValueChanged<CandleStyle> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final labels = [t.candleClassic, t.candleGlass, t.candleViolet];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF211631).withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          children: CandleStyle.values.map((style) {
            final active = style == selected;
            return Expanded(
              child: Semantics(
                selected: active,
                button: true,
                child: InkWell(
                  key: ValueKey('candle-style-${style.name}'),
                  borderRadius: BorderRadius.circular(19),
                  onTap: () => onSelected(style),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.pulse.withValues(alpha: 0.28)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: Text(
                      labels[style.index],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: active ? Colors.white : AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(growable: false),
        ),
      ),
    );
  }
}
