import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';

/// "Sandbox" — a free-form particle playground. Drag your finger to
/// scatter glowing particles; they fall and settle like sand. Both users
/// see each other's particles in real time.
class SandboxModeScreen extends ConsumerStatefulWidget {
  const SandboxModeScreen({super.key});

  @override
  ConsumerState<SandboxModeScreen> createState() => _SandboxModeScreenState();
}

class _SandboxModeScreenState extends ConsumerState<SandboxModeScreen>
    with SingleTickerProviderStateMixin {
  final List<_Particle> _particles = [];
  StreamSubscription<ModeEvent>? _partnerSub;
  late final AnimationController _physics;
  static final _random = math.Random();
  Size _canvasSize = Size.zero;

  static const _palette = [
    Color(0xFF9747FF),
    Color(0xFFFF4D8B),
    Color(0xFF6BD3FF),
    Color(0xFFFFD86A),
    Color(0xFF4ADE80),
  ];

  @override
  void initState() {
    super.initState();
    _physics = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _physics.addListener(_tick);
    _partnerSub = ref.read(modeEventBusProvider).incoming
        .where((e) => e.type == 'sandbox_particle')
        .listen(_onPartnerParticle);
  }

  void _tick() {
    if (!mounted) return;
    setState(() {
      for (final p in _particles) {
        // Gravity.
        p.vy += 0.3;
        p.x += p.vx;
        p.y += p.vy;
        // Floor collision.
        if (_canvasSize != Size.zero && p.y > _canvasSize.height - 4) {
          p.y = _canvasSize.height - 4;
          p.vy *= -0.4;
          p.vx *= 0.8;
        }
        // Slow horizontal drift.
        p.vx *= 0.99;
      }
      // Remove faded particles.
      _particles.removeWhere((p) => p.life <= 0);
    });
  }

  void _onPartnerParticle(ModeEvent event) {
    if (!mounted || _canvasSize == Size.zero) return;
    final x = (event.data['x'] as num?)?.toDouble() ?? 0.5;
    final y = (event.data['y'] as num?)?.toDouble() ?? 0.5;
    _spawn(Offset(x * _canvasSize.width, y * _canvasSize.height), isLocal: false);
  }

  void _spawn(Offset pos, {required bool isLocal}) {
    for (var i = 0; i < 3; i++) {
      _particles.add(_Particle(
        x: pos.dx,
        y: pos.dy,
        vx: (_random.nextDouble() - 0.5) * 4,
        vy: -_random.nextDouble() * 3,
        color: _palette[_random.nextInt(_palette.length)],
        radius: 3 + _random.nextDouble() * 3,
        life: 1.0,
        isLocal: isLocal,
      ));
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _spawn(details.localPosition, isLocal: true);
    if (_canvasSize == Size.zero) return;
    ref.read(modeEventBusProvider).send(ModeEvent(
      type: 'sandbox_particle',
      data: {
        'x': details.localPosition.dx / _canvasSize.width,
        'y': details.localPosition.dy / _canvasSize.height,
      },
    ));
  }

  @override
  void dispose() {
    _physics.removeListener(_tick);
    _physics.dispose();
    _partnerSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: _onPanUpdate,
                    child: CustomPaint(
                      painter: _SandboxPainter(particles: _particles),
                    ),
                  ),
                ),
                Positioned(
                  top: 14,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      t.modeSandbox,
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
                    onPressed: () {
                      setState(_particles.clear);
                      Navigator.of(context).maybePop();
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.radius,
    required this.life,
    required this.isLocal,
  });
  double x, y, vx, vy;
  Color color;
  double radius;
  double life;
  bool isLocal;
}

class _SandboxPainter extends CustomPainter {
  _SandboxPainter({required this.particles});
  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = p.color.withValues(alpha: p.life.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x, p.y), p.radius, paint);
      // Glow.
      canvas.drawCircle(
        Offset(p.x, p.y),
        p.radius * 2,
        Paint()
          ..color = p.color.withValues(alpha: 0.2 * p.life)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SandboxPainter old) => true;
}
