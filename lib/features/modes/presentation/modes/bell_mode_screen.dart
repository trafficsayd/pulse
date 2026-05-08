import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../../core/theme/app_colors.dart';
import 'mode_close_button.dart';

/// "Bell" — tap the bell to ring it. Strength of the tap (placeholder for
/// shake intensity until the accelerometer plugin lands) controls amplitude
/// and pitch. The partner sees a mirrored ring expand from their bell with
/// a short haptic pulse.
class BellModeScreen extends StatefulWidget {
  const BellModeScreen({super.key});

  @override
  State<BellModeScreen> createState() => _BellModeScreenState();
}

class _BellModeScreenState extends State<BellModeScreen>
    with TickerProviderStateMixin {
  final List<_Ring> _rings = [];
  late final AnimationController _swing;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _swing = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _swing.dispose();
    for (final r in _rings) {
      r.controller.dispose();
    }
    super.dispose();
  }

  void _ring() {
    final intensity = 0.6 + _rng.nextDouble() * 0.4;
    _swing.forward(from: 0);
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    final ring = _Ring(controller: controller, intensity: intensity);
    setState(() => _rings.add(ring));
    controller.forward().whenComplete(() {
      if (!mounted) return;
      setState(() => _rings.remove(ring));
      controller.dispose();
    });
    HapticFeedback.mediumImpact();
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
                onTap: _ring,
                child: const SizedBox.expand(),
              ),
            ),
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  for (final r in _rings)
                    AnimatedBuilder(
                      animation: r.controller,
                      builder: (context, _) {
                        final p = r.controller.value;
                        final radius = 80 + p * 220 * r.intensity;
                        final opacity = (1 - p).clamp(0.0, 1.0) * 0.7;
                        return SizedBox(
                          width: radius * 2,
                          height: radius * 2,
                          child: Opacity(
                            opacity: opacity,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.pulse,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  AnimatedBuilder(
                    animation: _swing,
                    builder: (context, _) {
                      final angle = math.sin(_swing.value * math.pi * 4) *
                          0.18 *
                          (1 - _swing.value);
                      return Transform.rotate(
                        angle: angle,
                        child: const Icon(
                          Icons.notifications_rounded,
                          size: 96,
                          color: AppColors.pulse,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  t.bellHint,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const Positioned(
              top: 8,
              right: 8,
              child: ModeCloseButton(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ring {
  _Ring({required this.controller, required this.intensity});

  final AnimationController controller;
  final double intensity;
}
