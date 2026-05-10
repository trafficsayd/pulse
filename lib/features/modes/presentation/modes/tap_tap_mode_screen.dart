import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pulse/l10n/app_localizations.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/pulse_mockup.dart';

/// "Tap-Tap" — concentric pulse rings on a near-black canvas.
///
/// Each tap drops a soft ring at the touch point that expands and fades
/// out. A continuous central pair of rings keeps the screen alive even
/// when nobody is tapping, mirroring the "Тук-Тук" tile on the design.
class TapTapModeScreen extends StatefulWidget {
  const TapTapModeScreen({super.key});

  @override
  State<TapTapModeScreen> createState() => _TapTapModeScreenState();
}

class _TapTapModeScreenState extends State<TapTapModeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _ambient;
  final List<_Ring> _rings = [];
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

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
    _ambient.dispose();
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final center = Offset(size.width / 2, size.height / 2);
          return Stack(
            children: [
              const Positioned.fill(child: PulseBackdrop(child: SizedBox())),
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _ambient,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _AmbientRingsPainter(
                        center: center,
                        progress: _ambient.value,
                      ),
                    );
                  },
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
                                    : AppColors.heart,
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
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: PulseHeader(
                      title: t.modeTapTapTitle,
                      trailing: PulseRoundButton(
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.of(context).maybePop(),
                        subtle: true,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 34,
                child: PulsePanel(
                  radius: 24,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Text(
                    t.tapTapHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AmbientRingsPainter extends CustomPainter {
  _AmbientRingsPainter({required this.center, required this.progress});

  final Offset center;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (var i = 0; i < 4; i++) {
      final t = ((progress + i / 4) % 1.0);
      final radius = 60 + t * 220;
      final alpha = (1 - t).clamp(0.0, 1.0) * 0.4;
      paint.color = AppColors.pulse.withValues(alpha: alpha);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_AmbientRingsPainter old) =>
      old.progress != progress || old.center != center;
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
