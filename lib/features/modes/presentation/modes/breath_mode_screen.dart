import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../capabilities/application/capability_providers.dart';
import '../../../capabilities/domain/device_capability.dart';
import '../../primitives/haptic_pattern_player.dart';
import '../../primitives/mic_level_stream.dart';
import '../../primitives/primitive_providers.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import 'unsupported_mode_screen.dart';

/// "Breath" — a guided breathing exercise synced between two users.
/// A pulsing circle expands for 4 seconds (inhale) and contracts for
/// 4 seconds (exhale). The microphone detects breath intensity and
/// makes the circle glow brighter when the user is actually exhaling.
/// Both users see each other's breath intensity.
///
/// Requires [DeviceCapability.microphone].
class BreathModeScreen extends ConsumerWidget {
  const BreathModeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final capsAsync = ref.watch(deviceCapabilitiesProvider);
    const required = {DeviceCapability.microphone};
    if (capsAsync.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.pulse)),
      );
    }
    final caps = capsAsync.asData?.value ?? const DeviceCapabilities.none();
    if (!caps.hasAll(required)) {
      return UnsupportedModeScreen(
        title: t.modeBreath,
        missing: caps.missing(required),
      );
    }
    return _BreathModeView(
      mic: ref.watch(micLevelStreamProvider),
      hapticEngine: ref.watch(hapticEngineProvider),
    );
  }
}

class _BreathModeView extends ConsumerStatefulWidget {
  const _BreathModeView({required this.mic, required this.hapticEngine});
  final MicLevelStream mic;
  final HapticEngine hapticEngine;

  @override
  ConsumerState<_BreathModeView> createState() => _BreathModeViewState();
}

class _BreathModeViewState extends ConsumerState<_BreathModeView>
    with TickerProviderStateMixin {
  late final AnimationController _breath;
  StreamSubscription<MicLevel>? _micSub;
  StreamSubscription<ModeEvent>? _partnerSub;
  Timer? _partnerLevelDecay;
  double _localLevel = 0;
  double _partnerLevel = 0;
  DateTime? _lastLevelSentAt;
  double _lastLevelSent = 0;
  late final HapticPatternPlayer _player;

  @override
  void initState() {
    super.initState();
    _player = HapticPatternPlayer(widget.hapticEngine);
    // 8-second cycle: 4s inhale (expand) + 4s exhale (contract).
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _micSub = widget.mic.levels.listen((sample) {
      if (!mounted) return;
      setState(() => _localLevel = sample.level01);
      final shouldTransmit = sample.level01 > 0.02 || _lastLevelSent > 0.02;
      if (shouldTransmit &&
          (_lastLevelSentAt == null ||
              sample.timestamp.difference(_lastLevelSentAt!) >=
                  const Duration(milliseconds: 100))) {
        _lastLevelSentAt = sample.timestamp;
        _lastLevelSent = sample.level01;
        unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
              type: 'breath_level',
              data: {'level': sample.level01},
            )));
      }
    });
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
        .where((e) => e.type == 'breath_level')
        .listen((e) {
      if (mounted) {
        final level = (e.data['level'] as num?)?.toDouble() ?? 0;
        setState(() => _partnerLevel = level);
        _partnerLevelDecay?.cancel();
        if (level > 0) {
          _partnerLevelDecay = Timer(const Duration(milliseconds: 450), () {
            if (mounted) setState(() => _partnerLevel = 0);
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _micSub?.cancel();
    _partnerSub?.cancel();
    _partnerLevelDecay?.cancel();
    _breath.dispose();
    unawaited(_player.stop());
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
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _breath,
                  builder: (context, _) {
                    // Inhale = first half (expanding), exhale = second half.
                    // Align both phones to the same wall-clock cycle instead
                    // of starting a private cycle when each screen opens.
                    final phase =
                        (DateTime.now().millisecondsSinceEpoch % 8000) / 8000;
                    final isExhale = phase > 0.5;
                    final expand = isExhale ? 1 - (phase - 0.5) * 2 : phase * 2;
                    return CustomPaint(
                      painter: _BreathPainter(
                        expand: expand,
                        localLevel: _localLevel,
                        partnerLevel: _partnerLevel,
                        isExhale: isExhale,
                        inhaleLabel: t.breathInhale,
                        exhaleLabel: t.breathExhale,
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
                  t.modeBreath,
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

class _BreathPainter extends CustomPainter {
  _BreathPainter({
    required this.expand,
    required this.localLevel,
    required this.partnerLevel,
    required this.isExhale,
    required this.inhaleLabel,
    required this.exhaleLabel,
  });

  final double expand; // 0..1
  final double localLevel;
  final double partnerLevel;
  final bool isExhale;
  final String inhaleLabel;
  final String exhaleLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final baseRadius = size.shortestSide * 0.15;
    final maxRadius = size.shortestSide * 0.38;
    final radius = baseRadius + expand * (maxRadius - baseRadius);

    // Halo — brightness driven by breath level.
    final haloAlpha = 0.15 + localLevel * 0.5;
    final halo = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.pulse.withValues(alpha: haloAlpha),
          AppColors.pulse.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.8));
    canvas.drawCircle(center, radius * 1.8, halo);

    // Main breathing circle.
    final mainPaint = Paint()
      ..color = AppColors.pulse.withValues(alpha: 0.6 + localLevel * 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..isAntiAlias = true;
    canvas.drawCircle(center, radius, mainPaint);

    // Inner fill.
    final fillPaint = Paint()
      ..color = AppColors.pulse.withValues(alpha: 0.08 + localLevel * 0.15)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, fillPaint);

    // Partner indicator ring — pulses with partner's breath.
    if (partnerLevel > 0.01) {
      final partnerPaint = Paint()
        ..color = AppColors.heart.withValues(alpha: 0.3 + partnerLevel * 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius + 12, partnerPaint);
    }

    // Phase label.
    final textPaint = TextPainter(
      text: TextSpan(
        text: isExhale ? exhaleLabel : inhaleLabel,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPaint.paint(
      canvas,
      Offset(center.dx - textPaint.width / 2, center.dy - textPaint.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _BreathPainter old) =>
      old.expand != expand ||
      old.localLevel != localLevel ||
      old.partnerLevel != partnerLevel ||
      old.inhaleLabel != inhaleLabel ||
      old.exhaleLabel != exhaleLabel ||
      old.isExhale != isExhale;
}
