import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import 'mode_close_button.dart';

/// Paid "Goosebumps" mode: each tap throws out a wave of tiny dots that
/// radiate from the touch point and fade. Symbolises a mild, full-body
/// shiver sent across the wire.
class GoosebumpsModeScreen extends ConsumerStatefulWidget {
  const GoosebumpsModeScreen({super.key});

  @override
  ConsumerState<GoosebumpsModeScreen> createState() =>
      _GoosebumpsModeScreenState();
}

class _GoosebumpsModeScreenState extends ConsumerState<GoosebumpsModeScreen>
    with TickerProviderStateMixin {
  final List<_Burst> _bursts = [];

  void _spawn(Offset at) {
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    final burst = _Burst(at: at, controller: ctrl);
    setState(() => _bursts.add(burst));
    ctrl.forward();
    ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        if (!mounted) return;
        setState(() => _bursts.remove(burst));
        ctrl.dispose();
      }
    });
  }

  @override
  void dispose() {
    for (final b in _bursts) {
      b.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTapDown: (d) => _spawn(d.localPosition),
        behavior: HitTestBehavior.opaque,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: AppColors.backgroundGradient,
          ),
          child: Stack(
            children: [
              for (final b in _bursts)
                AnimatedBuilder(
                  animation: b.controller,
                  builder: (context, _) => CustomPaint(
                    size: Size.infinite,
                    painter: _GoosebumpsPainter(
                      origin: b.at,
                      progress: b.controller.value,
                      seed: b.hashCode,
                    ),
                  ),
                ),
              const ModeCloseButton(),
              Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Text(
                  t.goosebumpsHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Burst {
  _Burst({required this.at, required this.controller});
  final Offset at;
  final AnimationController controller;
}

class _GoosebumpsPainter extends CustomPainter {
  _GoosebumpsPainter({
    required this.origin,
    required this.progress,
    required this.seed,
  });

  final Offset origin;
  final double progress;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final maxRadius = size.shortestSide * 0.45;
    final radius = maxRadius * Curves.easeOut.transform(progress);
    final paint = Paint()
      ..color = AppColors.pulse.withValues(alpha: 1.0 - progress);
    for (var i = 0; i < 24; i++) {
      final angle = rng.nextDouble() * 2 * math.pi;
      final jitter = 0.6 + rng.nextDouble() * 0.4;
      final dx = origin.dx + math.cos(angle) * radius * jitter;
      final dy = origin.dy + math.sin(angle) * radius * jitter;
      canvas.drawCircle(Offset(dx, dy), 2.4, paint);
    }
  }

  @override
  bool shouldRepaint(_GoosebumpsPainter old) =>
      old.progress != progress || old.origin != origin;
}
