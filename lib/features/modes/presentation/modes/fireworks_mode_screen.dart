import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import 'mode_close_button.dart';

/// Paid "Fireworks" mode: tap anywhere to launch a short-lived burst of
/// radiating sparks. Each burst draws particles whose distance from the
/// origin grows over the lifetime while the alpha decays.
class FireworksModeScreen extends ConsumerStatefulWidget {
  const FireworksModeScreen({super.key});

  @override
  ConsumerState<FireworksModeScreen> createState() =>
      _FireworksModeScreenState();
}

class _FireworksModeScreenState extends ConsumerState<FireworksModeScreen>
    with TickerProviderStateMixin {
  final List<_Firework> _fws = [];
  static const _palette = <Color>[
    AppColors.pulse,
    AppColors.pulsePink,
    Color(0xFFF59E0B),
    Color(0xFF22C55E),
    Color(0xFF60A5FA),
  ];

  void _spawn(Offset at) {
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    final fw = _Firework(
      at: at,
      controller: ctrl,
      color: _palette[math.Random().nextInt(_palette.length)],
    );
    setState(() => _fws.add(fw));
    ctrl.forward();
    ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        if (!mounted) return;
        setState(() => _fws.remove(fw));
        ctrl.dispose();
      }
    });
  }

  @override
  void dispose() {
    for (final f in _fws) {
      f.controller.dispose();
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
              for (final f in _fws)
                AnimatedBuilder(
                  animation: f.controller,
                  builder: (context, _) => CustomPaint(
                    size: Size.infinite,
                    painter: _FireworksPainter(
                      origin: f.at,
                      progress: f.controller.value,
                      color: f.color,
                      seed: f.hashCode,
                    ),
                  ),
                ),
              const ModeCloseButton(),
              Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Text(
                  t.fireworksHint,
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

class _Firework {
  _Firework({
    required this.at,
    required this.controller,
    required this.color,
  });
  final Offset at;
  final AnimationController controller;
  final Color color;
}

class _FireworksPainter extends CustomPainter {
  _FireworksPainter({
    required this.origin,
    required this.progress,
    required this.color,
    required this.seed,
  });

  final Offset origin;
  final double progress;
  final Color color;
  final int seed;

  static const _particleCount = 28;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final maxRadius = size.shortestSide * 0.4;
    final radius = maxRadius * Curves.easeOutCubic.transform(progress);
    final alpha = (1.0 - progress).clamp(0.0, 1.0);
    for (var i = 0; i < _particleCount; i++) {
      final angle = (i / _particleCount) * 2 * math.pi +
          rng.nextDouble() * 0.15;
      final dx = origin.dx + math.cos(angle) * radius;
      final dy = origin.dy + math.sin(angle) * radius +
          // Slight gravity pulls particles down as they fade.
          progress * progress * 60;
      final paint = Paint()..color = color.withValues(alpha: alpha);
      canvas.drawCircle(Offset(dx, dy), 2.6 - 1.4 * progress, paint);
    }
  }

  @override
  bool shouldRepaint(_FireworksPainter old) =>
      old.progress != progress || old.origin != origin;
}
