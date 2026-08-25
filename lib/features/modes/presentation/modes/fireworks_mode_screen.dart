import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import '../../primitives/haptic_pattern_player.dart';
import '../../primitives/primitive_providers.dart';

/// "Fireworks" — tap to launch a firework that explodes into colorful
/// particles. Both screens see the explosion at the same coordinates.
///
/// Visual: a rocket trail rises from the bottom to the tap point, then
/// bursts into 20+ colored particles that expand outward and fade.
/// Haptic: a triple-tap pattern plays on explosion.
class FireworksModeScreen extends ConsumerStatefulWidget {
  const FireworksModeScreen({super.key});

  @override
  ConsumerState<FireworksModeScreen> createState() =>
      _FireworksModeScreenState();
}

class _FireworksModeScreenState extends ConsumerState<FireworksModeScreen>
    with TickerProviderStateMixin {
  final List<_Firework> _fireworks = [];
  StreamSubscription<ModeEvent>? _partnerSub;
  late final HapticPatternPlayer _player;
  static final _random = math.Random();

  static const _colors = [
    Color(0xFFFF4D8B),
    Color(0xFF9747FF),
    Color(0xFFFFB05C),
    Color(0xFF4ADE80),
    Color(0xFF6BD3FF),
    Color(0xFFFFD86A),
    Color(0xFFE07CFF),
  ];

  @override
  void initState() {
    super.initState();
    _player = HapticPatternPlayer(ref.read(hapticEngineProvider));
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
        .where((e) => e.type == 'firework')
        .listen(_onPartnerFirework);
  }

  void _onPartnerFirework(ModeEvent event) {
    if (!mounted) return;
    final x = (event.data['x'] as num?)?.toDouble() ?? 0.5;
    final y = (event.data['y'] as num?)?.toDouble() ?? 0.3;
    final rawColor = (event.data['color'] as num?)?.toInt();
    final color = rawColor == null
        ? _colors[_random.nextInt(_colors.length)]
        : Color(rawColor);
    _launch(Offset(x, y), color: color, isLocal: false);
  }

  Future<void> _onTap(TapDownDetails details) async {
    final size = context.size;
    if (size == null) return;
    final normalized = Offset(
      details.localPosition.dx / size.width,
      details.localPosition.dy / size.height,
    );
    final color = _colors[_random.nextInt(_colors.length)];
    _launch(normalized, color: color, isLocal: true);
    HapticFeedback.lightImpact();
    await ref.read(modeEventBusProvider).send(ModeEvent(
          type: 'firework',
          data: {
            'x': normalized.dx,
            'y': normalized.dy,
            'color': color.toARGB32(),
          },
        ));
  }

  void _launch(
    Offset normalizedTarget, {
    required Color color,
    required bool isLocal,
  }) {
    final rocketController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    final burstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    final firework = _Firework(
      target: normalizedTarget,
      color: color,
      rocketController: rocketController,
      burstController: burstController,
      isLocal: isLocal,
    );
    setState(() => _fireworks.add(firework));

    rocketController.forward().then((_) {
      if (!mounted) return;
      unawaited(_player.play(HapticPatterns.triple));
      burstController.forward().whenComplete(() {
        if (!mounted) return;
        setState(() => _fireworks.remove(firework));
        rocketController.dispose();
        burstController.dispose();
      });
    });
  }

  @override
  void dispose() {
    _partnerSub?.cancel();
    for (final f in _fireworks) {
      f.rocketController.dispose();
      f.burstController.dispose();
    }
    unawaited(_player.stop());
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
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _onTap,
                child: CustomPaint(
                  painter: _FireworksPainter(fireworks: _fireworks),
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  t.modeFireworks,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: t.hubExit,
                color: AppColors.textSecondary,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Firework {
  _Firework({
    required this.target,
    required this.color,
    required this.rocketController,
    required this.burstController,
    required this.isLocal,
  });
  final Offset target;
  final Color color;
  final AnimationController rocketController;
  final AnimationController burstController;
  final bool isLocal;
}

class _FireworksPainter extends CustomPainter {
  _FireworksPainter({required this.fireworks})
      : super(
          repaint: Listenable.merge(
            fireworks
                .expand(
                  (firework) => [
                    firework.rocketController,
                    firework.burstController,
                  ],
                )
                .toList(growable: false),
          ),
        );
  final List<_Firework> fireworks;

  @override
  void paint(Canvas canvas, Size size) {
    for (final fw in fireworks) {
      final target = Offset(
        fw.target.dx * size.width,
        fw.target.dy * size.height,
      );
      // Rocket phase: trail from bottom to target.
      if (fw.rocketController.isAnimating) {
        final p = fw.rocketController.value;
        final startY = size.height;
        final current = Offset(
          target.dx,
          startY + (target.dy - startY) * p,
        );
        final trailPaint = Paint()
          ..color = fw.color.withValues(alpha: 0.6)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(target.dx, startY),
          current,
          trailPaint,
        );
        canvas.drawCircle(current, 4, Paint()..color = fw.color);
      }
      // Burst phase: expanding particles.
      if (fw.burstController.isAnimating || fw.rocketController.isCompleted) {
        final p = fw.burstController.value;
        if (p > 0) {
          const particleCount = 24;
          final radius = p * size.shortestSide * 0.3;
          final fade = (1 - p).clamp(0.0, 1.0);
          for (var i = 0; i < particleCount; i++) {
            final theta = (i / particleCount) * 2 * math.pi;
            final drift = i * 0.7;
            final px = target.dx + math.cos(theta) * radius;
            final py = target.dy + math.sin(theta) * radius + drift * p;
            final paint = Paint()
              ..color = fw.color.withValues(alpha: fade)
              ..style = PaintingStyle.fill;
            canvas.drawCircle(Offset(px, py), 3 * fade, paint);
            // Glow.
            canvas.drawCircle(
              Offset(px, py),
              6 * fade,
              Paint()
                ..color = fw.color.withValues(alpha: 0.3 * fade)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
            );
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FireworksPainter old) =>
      old.fireworks.length != fireworks.length;
}
