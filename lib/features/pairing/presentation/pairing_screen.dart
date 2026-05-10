import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../connections/application/connections_controller.dart';

/// First-launch screen: create a new pair (host) or join one (guest).
///
/// In production this orchestrates the Curve25519 ECDH exchange behind a
/// 6-digit short code. For the foundation PR we only wire up the UI flow
/// and persist a stub Connection so the rest of the app can be exercised.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  // Stub deterministic 6-digit short code. The real pairing layer will
  // derive this from a Curve25519 ECDH handshake.
  static const _stubCode = '532 871';

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              _PairingHeader(title: t.pairingScreenTitle),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const _PairingRing(),
                        const SizedBox(height: 28),
                        const Text(
                          _stubCode,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 42,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 6,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          t.pairingShowCodeOrQr,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _onCreatePair(context, ref),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(t.pairingCreate),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _onJoinPair(context, ref),
                        icon: const Icon(Icons.add_link_rounded, size: 18),
                        label: Text(t.pairingJoin),
                      ),
                    ),
                  ],
                ),
              ),
              const _LanguageToggle(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onCreatePair(BuildContext context, WidgetRef ref) async {
    // TODO(pairing): generate Curve25519 keypair, derive 6-digit code, show
    // it via a sheet, await partner's acknowledgement, persist via PairKeys.
    await ref.read(connectionsControllerProvider.notifier).createStubConnection(
          nickname: 'Demo',
        );
    if (context.mounted) context.go(Routes.hub);
  }

  Future<void> _onJoinPair(BuildContext context, WidgetRef ref) async {
    // TODO(pairing): show 6-digit numeric input, complete ECDH on submit.
    await ref.read(connectionsControllerProvider.notifier).createStubConnection(
          nickname: 'Demo',
        );
    if (context.mounted) context.go(Routes.hub);
  }
}

class _PairingHeader extends StatelessWidget {
  const _PairingHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.textSecondary,
            onPressed: () {},
          ),
          Expanded(
            child: Center(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            color: AppColors.textSecondary,
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

/// Big purple ring with a stylised QR placeholder in the middle.
///
/// Real QR rendering is intentionally deferred to its own follow-up. The
/// placeholder keeps the visual rhythm of the mockup so the rest of the
/// pairing flow can be reviewed.
class _PairingRing extends StatefulWidget {
  const _PairingRing();

  @override
  State<_PairingRing> createState() => _PairingRingState();
}

class _PairingRingState extends State<_PairingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void dispose() {
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _orbit,
            builder: (context, _) => CustomPaint(
              size: const Size.square(240),
              painter: _RingPainter(phase: _orbit.value),
            ),
          ),
          Container(
            width: 152,
            height: 152,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(color: AppColors.pulseHalo, blurRadius: 24),
              ],
            ),
            alignment: Alignment.center,
            child: const _QrGlyph(),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.phase});

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 6;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..shader = AppColors.heroGradient.createShader(
          Rect.fromCircle(center: center, radius: radius),
        ),
    );

    canvas.drawCircle(
      center,
      radius - 14,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.outline,
    );

    // Orbiting violet dot.
    final angle = phase * 2 * math.pi - math.pi / 2;
    final dot = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
    canvas.drawCircle(
      dot,
      6,
      Paint()..color = AppColors.pulse,
    );
    canvas.drawCircle(
      dot,
      14,
      Paint()..color = AppColors.pulseGlow,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.phase != phase;
}

class _QrGlyph extends StatelessWidget {
  const _QrGlyph();

  @override
  Widget build(BuildContext context) {
    // 7×7 deterministic pseudo-QR pattern. Real QR encoding will replace
    // this when the pairing handshake produces a payload.
    const pattern = [
      [1, 1, 1, 0, 1, 1, 1],
      [1, 0, 1, 0, 1, 0, 1],
      [1, 1, 1, 0, 1, 1, 1],
      [0, 0, 0, 1, 0, 0, 0],
      [1, 1, 1, 0, 1, 1, 1],
      [1, 0, 1, 0, 1, 0, 1],
      [1, 1, 1, 0, 1, 1, 1],
    ];
    return SizedBox(
      width: 96,
      height: 96,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 1.5,
          crossAxisSpacing: 1.5,
        ),
        itemCount: 49,
        itemBuilder: (context, i) {
          final row = i ~/ 7;
          final col = i % 7;
          final on = pattern[row][col] == 1;
          return Container(
            decoration: BoxDecoration(
              color: on ? AppColors.textPrimary : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        },
      ),
    );
  }
}

class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(4),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          _languageChip(t.pairingLanguageRu, selected: true),
          _languageChip(t.pairingLanguageEn, selected: false),
        ],
      ),
    );
  }

  Widget _languageChip(String label, {required bool selected}) {
    return Expanded(
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.pulse.withValues(alpha: 0.2) : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.pulse : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _PulseGlyph extends StatefulWidget {
  const _PulseGlyph();

  @override
  State<_PulseGlyph> createState() => _PulseGlyphState();
}

class _PulseGlyphState extends State<_PulseGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final phase = _c.value;
        return SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (final delay in const [0.0, 0.33, 0.66])
                Transform.scale(
                  scale: 0.4 + ((phase + delay) % 1.0) * 1.4,
                  child: Opacity(
                    opacity: (1 - ((phase + delay) % 1.0)).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.pulse, width: 1.4),
                      ),
                    ),
                  ),
                ),
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: AppColors.pulse,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: AppColors.pulseGlow, blurRadius: 24),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
