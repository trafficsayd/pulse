import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import 'mode_close_button.dart';

/// Paid "Sandbox" mode: drag your finger to scatter sand grains that
/// settle into a quiet trail. Particles persist for a few seconds then
/// gently fade.
class SandboxModeScreen extends ConsumerStatefulWidget {
  const SandboxModeScreen({super.key});

  @override
  ConsumerState<SandboxModeScreen> createState() => _SandboxModeScreenState();
}

class _SandboxModeScreenState extends ConsumerState<SandboxModeScreen> {
  final List<_Grain> _grains = [];
  final _rng = math.Random();

  void _scatter(Offset p) {
    final now = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      for (var i = 0; i < 6; i++) {
        final jitter = Offset(
          _rng.nextDouble() * 24 - 12,
          _rng.nextDouble() * 24 - 12,
        );
        _grains.add(_Grain(p + jitter, now));
      }
      // Trim the trail so the canvas never exceeds ~600 grains.
      _grains.removeWhere((g) => now - g.bornAt > 3000);
      while (_grains.length > 600) {
        _grains.removeAt(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onPanStart: (d) => _scatter(d.localPosition),
        onPanUpdate: (d) => _scatter(d.localPosition),
        behavior: HitTestBehavior.opaque,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: AppColors.backgroundGradient,
          ),
          child: Stack(
            children: [
              CustomPaint(
                size: Size.infinite,
                painter: _SandboxPainter(_grains),
              ),
              const ModeCloseButton(),
              Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Text(
                  t.sandboxHint,
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

class _Grain {
  const _Grain(this.at, this.bornAt);
  final Offset at;
  final int bornAt;
}

class _SandboxPainter extends CustomPainter {
  _SandboxPainter(this.grains);
  final List<_Grain> grains;

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final paint = Paint();
    for (final g in grains) {
      final age = (now - g.bornAt) / 3000.0;
      paint.color = AppColors.pulsePink.withValues(
        alpha: (1.0 - age).clamp(0, 1) * 0.7,
      );
      canvas.drawCircle(g.at, 1.6, paint);
    }
  }

  @override
  bool shouldRepaint(_SandboxPainter old) => true;
}
