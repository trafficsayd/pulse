import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../../core/theme/app_colors.dart';
import 'mode_close_button.dart';

/// "Whisper" — touch and hold to speak softly. Concentric pulses radiate
/// from the touch point on both sides; each pulse arrival on the partner is
/// accompanied by a low-amplitude haptic tick. The microphone capture is
/// not yet wired (transport layer); a periodic timer simulates breath
/// amplitude so the mode is interactive in isolation.
class WhisperModeScreen extends StatefulWidget {
  const WhisperModeScreen({super.key});

  @override
  State<WhisperModeScreen> createState() => _WhisperModeScreenState();
}

class _WhisperModeScreenState extends State<WhisperModeScreen>
    with TickerProviderStateMixin {
  Offset? _touch;
  Timer? _emitTimer;
  final List<_Wave> _waves = [];
  final _rng = math.Random();

  void _start(Offset position) {
    setState(() => _touch = position);
    _emitTimer?.cancel();
    _emitTimer = Timer.periodic(
      const Duration(milliseconds: 220),
      (_) => _emitWave(),
    );
    _emitWave();
    HapticFeedback.selectionClick();
  }

  void _move(Offset position) {
    setState(() => _touch = position);
  }

  void _stop() {
    setState(() => _touch = null);
    _emitTimer?.cancel();
    _emitTimer = null;
  }

  void _emitWave() {
    final origin = _touch;
    if (origin == null) return;
    final amplitude = 0.6 + _rng.nextDouble() * 0.4;
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    final wave = _Wave(
      origin: origin,
      controller: controller,
      amplitude: amplitude,
    );
    setState(() => _waves.add(wave));
    controller.forward().whenComplete(() {
      if (!mounted) return;
      setState(() => _waves.remove(wave));
      controller.dispose();
    });
    HapticFeedback.lightImpact();
  }

  @override
  void dispose() {
    _emitTimer?.cancel();
    for (final w in _waves) {
      w.controller.dispose();
    }
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
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => _start(e.localPosition),
                onPointerMove: (e) => _move(e.localPosition),
                onPointerUp: (_) => _stop(),
                onPointerCancel: (_) => _stop(),
              ),
            ),
            for (final wave in _waves)
              AnimatedBuilder(
                animation: wave.controller,
                builder: (context, _) {
                  final p = wave.controller.value;
                  final radius = 24 + p * 200 * wave.amplitude;
                  final opacity = (1 - p).clamp(0.0, 1.0) * 0.7;
                  return Positioned(
                    left: wave.origin.dx - radius,
                    top: wave.origin.dy - radius,
                    width: radius * 2,
                    height: radius * 2,
                    child: Opacity(
                      opacity: opacity,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.transportLocal,
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  t.whisperHint,
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

class _Wave {
  _Wave({
    required this.origin,
    required this.controller,
    required this.amplitude,
  });

  final Offset origin;
  final AnimationController controller;
  final double amplitude;
}
