import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../capabilities/application/capability_providers.dart';
import '../../../capabilities/domain/device_capability.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import '../../primitives/haptic_pattern_player.dart';
import '../../primitives/mic_level_stream.dart';
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
  });

  final MicLevelStream? micLevelStream;
  final HapticEngine? hapticEngine;
  final double blowThreshold;
  final int requiredBlowSamples;

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
      micLevelStream: micLevelStream,
      hapticEngine: hapticEngine,
      blowThreshold: blowThreshold,
      requiredBlowSamples: requiredBlowSamples,
    );
  }
}

class _CandleModeView extends ConsumerStatefulWidget {
  const _CandleModeView({
    required this.micLevelStream,
    required this.hapticEngine,
    required this.blowThreshold,
    required this.requiredBlowSamples,
  });

  final MicLevelStream? micLevelStream;
  final HapticEngine? hapticEngine;
  final double blowThreshold;
  final int requiredBlowSamples;

  @override
  ConsumerState<_CandleModeView> createState() => _CandleModeViewState();
}

class _CandleModeViewState extends ConsumerState<_CandleModeView>
    with SingleTickerProviderStateMixin {
  late final MicLevelStream _mic;
  late final HapticEngine _engine;
  late final HapticPatternPlayer _player;
  late final AnimationController _flicker;
  StreamSubscription<MicLevel>? _micSub;
  StreamSubscription<ModeEvent>? _partnerSub;
  bool _ownsMic = false;
  bool _ownsEngine = false;

  bool _isLit = false;
  int _blowSamplesOverThreshold = 0;

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
    _flicker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _micSub = _mic.levels.listen(_onMicLevel);
    _partnerSub = ref.read(modeEventBusProvider).incoming
        .where((e) => e.type == 'candle_light' || e.type == 'candle_blow')
        .listen(_onPartnerEvent);
  }

  void _onPartnerEvent(ModeEvent event) {
    if (!mounted) return;
    if (event.type == 'candle_light') {
      _lightCandle();
    } else if (event.type == 'candle_blow') {
      _extinguishCandle();
    }
  }

  void _onMicLevel(MicLevel sample) {
    if (!mounted || !_isLit) return;
    if (sample.level01 > widget.blowThreshold) {
      _blowSamplesOverThreshold++;
      if (_blowSamplesOverThreshold >= widget.requiredBlowSamples) {
        _extinguishCandle();
        ref.read(modeEventBusProvider).send(
              ModeEvent(type: 'candle_blow', data: {'level': sample.level01}),
            );
        _blowSamplesOverThreshold = 0;
      }
    } else {
      _blowSamplesOverThreshold = 0;
    }
  }

  void _lightCandle() {
    if (_isLit) return;
    setState(() => _isLit = true);
    HapticFeedback.lightImpact();
    unawaited(_player.play(HapticPatterns.tap));
  }

  void _extinguishCandle() {
    if (!_isLit) return;
    setState(() => _isLit = false);
    HapticFeedback.mediumImpact();
    unawaited(_player.play(HapticPatterns.whisper));
  }

  void _onTap() {
    if (!_isLit) {
      _lightCandle();
      ref.read(modeEventBusProvider).send(const ModeEvent(type: 'candle_light'));
    }
  }

  @override
  void dispose() {
    _micSub?.cancel();
    _partnerSub?.cancel();
    _flicker.dispose();
    unawaited(_player.stop());
    if (_ownsMic) unawaited(_mic.dispose());
    if (_ownsEngine) unawaited(_engine.cancel());
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
                    return CustomPaint(
                      painter: _CandlePainter(
                        isLit: _isLit,
                        flicker: _flicker.value,
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  _isLit ? t.candleBlowHint : t.candleTouchHint,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
  _CandlePainter({required this.isLit, required this.flicker});

  final bool isLit;
  final double flicker;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final candleWidth = size.shortestSide * 0.12;
    final candleHeight = size.shortestSide * 0.35;

    // Candle body.
    final bodyRect = Rect.fromCenter(
      center: center + Offset(0, candleHeight * 0.3),
      width: candleWidth,
      height: candleHeight,
    );
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFFF5E6D3),
          Color(0xFFE8D5B7),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(bodyRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(4)),
      bodyPaint,
    );

    // Wick.
    final wickTop = center.dy - candleHeight * 0.2;
    final wickPaint = Paint()
      ..color = const Color(0xFF3D3D3D)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(center.dx, wickTop + 12),
      Offset(center.dx, wickTop),
      wickPaint,
    );

    if (isLit) {
      // Flame — two overlapping bezier shapes with flicker offset.
      final flameCenter = Offset(center.dx, wickTop - 20);
      final flickerOffset = math.sin(flicker * 2 * math.pi) * 3.0;
      final flameHeight = 32.0 + flickerOffset;
      final flameWidth = 14.0 + math.cos(flicker * 2 * math.pi) * 2.0;

      // Outer glow.
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFB05C).withValues(alpha: 0.5),
            const Color(0xFFFFB05C).withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCircle(center: flameCenter, radius: 80),
        );
      canvas.drawCircle(flameCenter, 80, glowPaint);

      // Outer flame (orange).
      final outerPath = Path()
        ..moveTo(flameCenter.dx, flameCenter.dy - flameHeight)
        ..quadraticBezierTo(
          flameCenter.dx + flameWidth,
          flameCenter.dy - flameHeight * 0.3,
          flameCenter.dx,
          flameCenter.dy + 8,
        )
        ..quadraticBezierTo(
          flameCenter.dx - flameWidth,
          flameCenter.dy - flameHeight * 0.3,
          flameCenter.dx,
          flameCenter.dy - flameHeight,
        );
      canvas.drawPath(
        outerPath,
        Paint()
          ..shader = const LinearGradient(
            colors: [
              Color(0xFFFFD86A),
              Color(0xFFFFB05C),
              Color(0xFFFF6B35),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(
            Rect.fromCenter(
              center: flameCenter,
              width: flameWidth * 2,
              height: flameHeight,
            ),
          ),
      );

      // Inner flame (bright yellow-white).
      final innerHeight = flameHeight * 0.5;
      final innerWidth = flameWidth * 0.5;
      final innerPath = Path()
        ..moveTo(flameCenter.dx, flameCenter.dy - innerHeight)
        ..quadraticBezierTo(
          flameCenter.dx + innerWidth,
          flameCenter.dy - innerHeight * 0.3,
          flameCenter.dx,
          flameCenter.dy + 4,
        )
        ..quadraticBezierTo(
          flameCenter.dx - innerWidth,
          flameCenter.dy - innerHeight * 0.3,
          flameCenter.dx,
          flameCenter.dy - innerHeight,
        );
      canvas.drawPath(
        innerPath,
        Paint()..color = const Color(0xFFFFF8E1).withValues(alpha: 0.9),
      );
    } else {
      // Faint glow at wick tip when extinguished.
      final wickTip = Offset(center.dx, wickTop);
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFB05C).withValues(alpha: 0.15),
            const Color(0xFFFFB05C).withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: wickTip, radius: 20));
      canvas.drawCircle(wickTip, 20, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) =>
      old.isLit != isLit || old.flicker != flicker;
}
