import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../../core/theme/app_colors.dart';
import 'mode_close_button.dart';

/// "Constellation" — tap on a black sky to drop stars. After ~1.4 s of
/// inactivity, the placed stars are connected in placement order to form a
/// constellation. Long-press anywhere to reset the canvas.
///
/// The partner side is simulated locally — placed stars are echoed at a
/// random offset so the screen looks alive in isolation.
class ConstellationModeScreen extends StatefulWidget {
  const ConstellationModeScreen({super.key});

  @override
  State<ConstellationModeScreen> createState() =>
      _ConstellationModeScreenState();
}

class _ConstellationModeScreenState extends State<ConstellationModeScreen>
    with SingleTickerProviderStateMixin {
  final List<_Star> _stars = [];
  Timer? _connectTimer;
  bool _connected = false;
  late final AnimationController _twinkle;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _twinkle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _connectTimer?.cancel();
    _twinkle.dispose();
    super.dispose();
  }

  void _placeStar(Offset position, Size size) {
    setState(() {
      _stars.add(_Star(position: position, isLocal: true));
      _connected = false;
    });
    HapticFeedback.selectionClick();

    _connectTimer?.cancel();
    _connectTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _connected = true);
      HapticFeedback.lightImpact();
    });

    // Simulated partner echo — drops a ghost star nearby.
    Future.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final dx = (_rng.nextDouble() - 0.5) * 80;
      final dy = (_rng.nextDouble() - 0.5) * 80;
      setState(() {
        _stars.add(_Star(
          position: Offset(
            (position.dx + dx).clamp(20.0, size.width - 20),
            (position.dy + dy).clamp(20.0, size.height - 20),
          ),
          isLocal: false,
        ));
      });
    });
  }

  void _reset() {
    setState(() {
      _stars.clear();
      _connected = false;
    });
    _connectTimer?.cancel();
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _placeStar(d.localPosition, size),
                    onLongPress: _reset,
                    child: AnimatedBuilder(
                      animation: _twinkle,
                      builder: (context, _) {
                        return CustomPaint(
                          size: size,
                          painter: _ConstellationPainter(
                            stars: _stars,
                            connected: _connected,
                            twinkle: _twinkle.value,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      t.constellationHint,
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
            );
          },
        ),
      ),
    );
  }
}

class _Star {
  _Star({required this.position, required this.isLocal});

  final Offset position;
  final bool isLocal;
}

class _ConstellationPainter extends CustomPainter {
  _ConstellationPainter({
    required this.stars,
    required this.connected,
    required this.twinkle,
  });

  final List<_Star> stars;
  final bool connected;
  final double twinkle;

  @override
  void paint(Canvas canvas, Size size) {
    if (stars.isEmpty) return;
    final localStars = stars.where((s) => s.isLocal).toList();

    if (connected && localStars.length >= 2) {
      final linePaint = Paint()
        ..color = AppColors.pulse.withValues(alpha: 0.45)
        ..strokeWidth = 1.4;
      for (var i = 0; i < localStars.length - 1; i++) {
        canvas.drawLine(
          localStars[i].position,
          localStars[i + 1].position,
          linePaint,
        );
      }
    }

    for (final star in stars) {
      final color = star.isLocal ? AppColors.pulse : AppColors.transportLocal;
      final radius = 3.6 + twinkle * 1.4;
      canvas.drawCircle(
        star.position,
        radius,
        Paint()..color = color.withValues(alpha: 0.9),
      );
      canvas.drawCircle(
        star.position,
        radius * 2.6,
        Paint()..color = color.withValues(alpha: 0.18),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConstellationPainter oldDelegate) =>
      oldDelegate.stars != stars ||
      oldDelegate.connected != connected ||
      oldDelegate.twinkle != twinkle;
}
