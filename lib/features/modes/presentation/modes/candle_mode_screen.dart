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
      micLevelStream: micLevelStream ?? ref.watch(micLevelStreamProvider),
      hapticEngine: hapticEngine ?? ref.watch(hapticEngineProvider),
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
  Timer? _partnerWindDecay;
  bool _ownsMic = false;
  bool _ownsEngine = false;

  bool _isLit = false;
  int _blowSamplesOverThreshold = 0;
  double _localWind = 0;
  double _partnerWind = 0;
  DateTime? _lastWindSentAt;
  CandleStyle _style = CandleStyle.classic;

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
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
        .where((e) => e.type == 'candle_light' || e.type == 'candle_blow')
        .listen(_onPartnerEvent);
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
      _lightCandle();
    } else if (event.type == 'candle_blow') {
      final level = (event.data['level'] as num?)?.toDouble() ?? 0;
      final extinguished =
          event.data['extinguished'] as bool? ?? level >= widget.blowThreshold;
      setState(() => _partnerWind = level.clamp(0, 1));
      _partnerWindDecay?.cancel();
      if (!extinguished && level > 0) {
        _partnerWindDecay = Timer(const Duration(milliseconds: 450), () {
          if (mounted) setState(() => _partnerWind = 0);
        });
      }
      if (extinguished) _extinguishCandle();
    }
  }

  void _onMicLevel(MicLevel sample) {
    if (!mounted || !_isLit) return;
    final level = sample.level01.clamp(0.0, 1.0);
    setState(() => _localWind = level);
    _sendWind(level, extinguished: false, at: sample.timestamp);
    if (sample.level01 > widget.blowThreshold) {
      _blowSamplesOverThreshold++;
      if (_blowSamplesOverThreshold >= widget.requiredBlowSamples) {
        _extinguishCandle();
        _sendWind(level, extinguished: true, at: sample.timestamp, force: true);
        _blowSamplesOverThreshold = 0;
      }
    } else {
      _blowSamplesOverThreshold = 0;
    }
  }

  void _sendWind(
    double level, {
    required bool extinguished,
    required DateTime at,
    bool force = false,
  }) {
    // Microphone chunks can arrive dozens of times per second. Ten updates
    // per second are enough for a fluid flame and protect the data channel.
    if (!force &&
        _lastWindSentAt != null &&
        at.difference(_lastWindSentAt!) < const Duration(milliseconds: 100)) {
      return;
    }
    _lastWindSentAt = at;
    unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
          type: 'candle_blow',
          data: {'level': level, 'extinguished': extinguished},
        )));
  }

  void _lightCandle() {
    if (_isLit) return;
    setState(() => _isLit = true);
    HapticFeedback.lightImpact();
    unawaited(_player.play(HapticPatterns.tap));
  }

  void _extinguishCandle() {
    if (!_isLit) return;
    setState(() {
      _isLit = false;
      _localWind = 0;
      _partnerWind = 0;
    });
    HapticFeedback.mediumImpact();
    unawaited(_player.play(HapticPatterns.whisper));
  }

  void _onTap() {
    if (!_isLit) {
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
    if (_isLit) {
      unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
            type: 'candle_light',
            data: {'style': style.index},
          )));
    }
  }

  @override
  void dispose() {
    _micSub?.cancel();
    _partnerSub?.cancel();
    _partnerWindDecay?.cancel();
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
                        wind: (_localWind - _partnerWind).clamp(-1, 1),
                        style: _style,
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
  _CandlePainter({
    required this.isLit,
    required this.flicker,
    required this.wind,
    required this.style,
  });

  final bool isLit;
  final double flicker;
  final double wind;
  final CandleStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final candleWidth =
        size.shortestSide * (style == CandleStyle.glass ? 0.22 : 0.18);
    final candleHeight =
        size.shortestSide * (style == CandleStyle.glass ? 0.29 : 0.32);

    // Candle body.
    final bodyRect = Rect.fromCenter(
      center: center + Offset(0, candleHeight * 0.3),
      width: candleWidth,
      height: candleHeight,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, bodyRect.bottom + 7),
        width: candleWidth * 1.18,
        height: 18,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.42)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    final bodyColors = switch (style) {
      CandleStyle.classic => const [
          Color(0xFFCDB491),
          Color(0xFFFFF4E1),
          Color(0xFFEAD5B6),
          Color(0xFFB99C78),
        ],
      CandleStyle.glass => const [
          Color(0x335A477D),
          Color(0x99E9E4FF),
          Color(0x445A477D),
        ],
      CandleStyle.violet => const [
          Color(0xFF59328F),
          Color(0xFFD8C0FF),
          Color(0xFF9B6DE0),
          Color(0xFF47256F),
        ],
    };
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        colors: bodyColors,
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(bodyRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bodyRect,
        Radius.circular(style == CandleStyle.glass ? candleWidth * 0.45 : 6),
      ),
      bodyPaint,
    );
    if (style == CandleStyle.glass) {
      final waxRect = Rect.fromLTRB(
        bodyRect.left + 8,
        bodyRect.top + bodyRect.height * 0.22,
        bodyRect.right - 8,
        bodyRect.bottom - 5,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(waxRect, const Radius.circular(12)),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFFB99CE8), Color(0xFF5D358C)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(waxRect),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bodyRect, Radius.circular(candleWidth * 0.45)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.35),
      );
      canvas.drawLine(
        Offset(bodyRect.left + 12, bodyRect.top + 18),
        Offset(bodyRect.left + 12, bodyRect.bottom - 22),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.32)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    } else {
      // Elliptical top and a small wax drip give the pillar real volume.
      final topOval = Rect.fromCenter(
        center: Offset(center.dx, bodyRect.top + 3),
        width: candleWidth,
        height: candleWidth * 0.28,
      );
      canvas.drawOval(
        topOval,
        Paint()
          ..color = (style == CandleStyle.classic
                  ? const Color(0xFFFFF7E8)
                  : const Color(0xFFDCC8FF))
              .withValues(alpha: 0.94),
      );
      final dripPath = Path()
        ..moveTo(bodyRect.right - candleWidth * 0.22, bodyRect.top + 2)
        ..quadraticBezierTo(
          bodyRect.right - candleWidth * 0.18,
          bodyRect.top + 35,
          bodyRect.right - candleWidth * 0.30,
          bodyRect.top + 45,
        )
        ..quadraticBezierTo(
          bodyRect.right - candleWidth * 0.39,
          bodyRect.top + 28,
          bodyRect.right - candleWidth * 0.40,
          bodyRect.top + 4,
        )
        ..close();
      canvas.drawPath(
        dripPath,
        Paint()
          ..color = (style == CandleStyle.classic
                  ? const Color(0xFFF4DFC0)
                  : const Color(0xFFAF86E8))
              .withValues(alpha: 0.8),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bodyRect, const Radius.circular(8)),
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.30),
              Colors.white.withValues(alpha: 0),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.center,
          ).createShader(bodyRect),
      );
    }

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
      final windOffset = wind * 22;
      final flameCenter = Offset(center.dx + windOffset * 0.35, wickTop - 20);
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
        ..moveTo(flameCenter.dx + windOffset, flameCenter.dy - flameHeight)
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
        ..moveTo(
            flameCenter.dx + windOffset * 0.55, flameCenter.dy - innerHeight)
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
      old.isLit != isLit ||
      old.flicker != flicker ||
      old.wind != wind ||
      old.style != style;
}

enum CandleStyle { classic, glass, violet }

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
