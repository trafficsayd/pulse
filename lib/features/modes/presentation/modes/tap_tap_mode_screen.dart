import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../../core/theme/app_colors.dart';
import 'mode_close_button.dart';

/// "Tap-Tap" — the simplest starter mode.
///
/// Each tap on this screen sends a single beat to the partner; a beat
/// inbound from the partner blooms a soft ring at a random position with a
/// short haptic pulse. The runner injects the inbound stream; for now we
/// simulate it locally so the screen is usable in isolation.
class TapTapModeScreen extends StatefulWidget {
  const TapTapModeScreen({super.key});

  @override
  State<TapTapModeScreen> createState() => _TapTapModeScreenState();
}

class _TapTapModeScreenState extends State<TapTapModeScreen>
    with TickerProviderStateMixin {
  final List<_Ring> _rings = [];
  final _rng = math.Random();

  void _addRing(Offset position, {required bool isLocal}) {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    final ring = _Ring(
      position: position,
      controller: controller,
      isLocal: isLocal,
    );
    setState(() => _rings.add(ring));
    controller.forward().whenComplete(() {
      if (!mounted) return;
      setState(() => _rings.remove(ring));
      controller.dispose();
    });
  }

  Future<void> _onTap(TapDownDetails details, Size size) async {
    _addRing(details.localPosition, isLocal: true);
    HapticFeedback.lightImpact();

    // Locally simulate the partner answering for development.
    // The mode runner replaces this once the real transport is wired up.
    Future.delayed(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      _addRing(
        Offset(
          _rng.nextDouble() * size.width,
          _rng.nextDouble() * size.height,
        ),
        isLocal: false,
      );
      HapticFeedback.selectionClick();
    });
  }

  @override
  void dispose() {
    for (final r in _rings) {
      r.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ScatterDotsPainter(seed: 7),
                  ),
                ),
                Positioned.fill(
                  child: Center(
                    child: CustomPaint(
                      size: Size.square(math.min(size.width, size.height) * 0.7),
                      painter: const _ConcentricRingsPainter(),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _onTap(d, size),
                  ),
                ),
                for (final ring in _rings)
                  Positioned(
                    left: ring.position.dx - 60,
                    top: ring.position.dy - 60,
                    width: 120,
                    height: 120,
                    child: AnimatedBuilder(
                      animation: ring.controller,
                      builder: (context, _) {
                        final progress = ring.controller.value;
                        final scale = 0.4 + progress * 1.6;
                        final opacity = (1 - progress).clamp(0.0, 1.0);
                        return Transform.scale(
                          scale: scale,
                          child: Opacity(
                            opacity: opacity,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: ring.isLocal
                                      ? AppColors.pulse
                                      : AppColors.pulsePink,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                Positioned(
                  top: 24,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Center(
                      child: Text(
                        t.tapTapHint,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  top: 16,
                  right: 16,
                  child: SafeArea(child: ModeCloseButton()),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ConcentricRingsPainter extends CustomPainter {
  const _ConcentricRingsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;
    for (var i = 0; i < 4; i++) {
      final r = maxR * (1 - i * 0.2);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = AppColors.pulse.withValues(alpha: 0.18 + i * 0.05),
      );
    }
    canvas.drawCircle(
      center,
      8,
      Paint()..color = AppColors.pulse,
    );
    canvas.drawCircle(
      center,
      24,
      Paint()..color = AppColors.pulseGlow,
    );
  }

  @override
  bool shouldRepaint(covariant _ConcentricRingsPainter oldDelegate) => false;
}

class _ScatterDotsPainter extends CustomPainter {
  _ScatterDotsPainter({required this.seed});
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    for (var i = 0; i < 60; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = 1.0 + rng.nextDouble() * 1.6;
      final alpha = 0.06 + rng.nextDouble() * 0.18;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = AppColors.pulse.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScatterDotsPainter oldDelegate) => false;
}

class _Ring {
  _Ring({
    required this.position,
    required this.controller,
    required this.isLocal,
  });

  final Offset position;
  final AnimationController controller;
  final bool isLocal;
}
