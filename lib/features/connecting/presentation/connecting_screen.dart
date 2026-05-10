import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pulse/l10n/app_localizations.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/pulse_mockup.dart';

/// "Establishing connection..." — animated handshake screen shown right
/// after a pair is initiated.
///
/// Two phone glyphs face each other across a dotted ring; below, three
/// progressive checklist items light up as the handshake advances:
///   1. Key exchange
///   2. Channel encrypted
///   3. Secure link established
///
/// After the third item lights, the screen auto-routes into the hub.
class ConnectingScreen extends StatefulWidget {
  const ConnectingScreen({super.key});

  @override
  State<ConnectingScreen> createState() => _ConnectingScreenState();
}

class _ConnectingScreenState extends State<ConnectingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _orbit;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _runHandshake();
  }

  Future<void> _runHandshake() async {
    for (var i = 1; i <= 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      setState(() => _step = i);
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    context.go(Routes.hub);
  }

  @override
  void dispose() {
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: PulseBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            child: Column(
              children: [
                PulseHeader(title: t.connectingTitle),
                const SizedBox(height: 34),
                Text(
                  t.connectingTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.35,
                  ),
                ),
                const SizedBox(height: 34),
                PulsePanel(
                  radius: 34,
                  padding: const EdgeInsets.all(18),
                  child: SizedBox(
                    width: 286,
                    height: 286,
                    child: AnimatedBuilder(
                      animation: _orbit,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _DottedRingPainter(progress: _orbit.value),
                          child: const Stack(
                            alignment: Alignment.center,
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: _PhoneGlyph(rotated: false),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: _PhoneGlyph(rotated: true),
                              ),
                              PulseGlowCircle(
                                size: 72,
                                color: AppColors.pulse,
                                fill: AppColors.surface,
                                blur: 28,
                                borderWidth: 1,
                                child: Icon(
                                  Icons.lock_rounded,
                                  color: AppColors.pulse,
                                  size: 28,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const Spacer(),
                PulsePanel(
                  radius: 28,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _StepRow(
                        done: _step >= 1,
                        inProgress: _step == 0,
                        label: t.connectingKeyExchange,
                      ),
                      const SizedBox(height: 14),
                      _StepRow(
                        done: _step >= 2,
                        inProgress: _step == 1,
                        label: t.connectingChannelEncrypted,
                      ),
                      const SizedBox(height: 14),
                      _StepRow(
                        done: _step >= 3,
                        inProgress: _step == 2,
                        label: t.connectingSecuredLink,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneGlyph extends StatelessWidget {
  const _PhoneGlyph({required this.rotated});

  final bool rotated;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotated ? 0.18 : -0.18,
      child: Container(
        width: 56,
        height: 96,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.pulse, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.pulse.withValues(alpha: 0.4),
              blurRadius: 24,
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.smartphone_rounded,
            color: AppColors.pulse,
            size: 28,
          ),
        ),
      ),
    );
  }
}

class _DottedRingPainter extends CustomPainter {
  _DottedRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 8;
    final paint = Paint()..style = PaintingStyle.fill;

    const totalDots = 48;
    for (var i = 0; i < totalDots; i++) {
      final angle = (i / totalDots) * 2 * math.pi;
      final shifted = (i / totalDots + progress) % 1.0;
      paint.color = AppColors.pulse.withValues(
        alpha: 0.18 + 0.6 * (1 - (shifted - 0.5).abs() * 2).clamp(0.0, 1.0),
      );
      final p = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawCircle(p, 1.6, paint);
    }
  }

  @override
  bool shouldRepaint(_DottedRingPainter old) => old.progress != progress;
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.done,
    required this.inProgress,
    required this.label,
  });

  final bool done;
  final bool inProgress;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? AppColors.transportDirect
        : inProgress
            ? AppColors.pulse
            : AppColors.textMuted;
    return Row(
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: done
              ? Container(
                  decoration: const BoxDecoration(
                    color: AppColors.transportDirect,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                )
              : inProgress
                  ? const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.pulse),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.outline),
                      ),
                    ),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
