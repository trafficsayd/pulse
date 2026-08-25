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
  DateTime? _lastEmissionAt;
  final List<(Offset, int)> _pendingPartnerBursts = [];

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
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
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
        p.life -= 0.004;
      }
      // Remove faded particles.
      _particles.removeWhere((p) => p.life <= 0);
    });
  }

  void _onPartnerParticle(ModeEvent event) {
    if (!mounted) return;
    final x = (event.data['x'] as num?)?.toDouble() ?? 0.5;
    final y = (event.data['y'] as num?)?.toDouble() ?? 0.5;
    final seed =
        (event.data['seed'] as num?)?.toInt() ?? _random.nextInt(0x7fffffff);
    if (_canvasSize == Size.zero) {
      _pendingPartnerBursts.add((Offset(x, y), seed));
      if (_pendingPartnerBursts.length > 100) {
        _pendingPartnerBursts.removeAt(0);
      }
      return;
    }
    setState(() {
      _spawn(
        Offset(x * _canvasSize.width, y * _canvasSize.height),
        isLocal: false,
        seed: seed,
      );
    });
  }

  void _spawn(Offset pos, {required bool isLocal, required int seed}) {
    final random = math.Random(seed);
    for (var i = 0; i < 3; i++) {
      _particles.add(_Particle(
        x: pos.dx,
        y: pos.dy,
        vx: (random.nextDouble() - 0.5) * 4,
        vy: -random.nextDouble() * 3,
        color: _palette[random.nextInt(_palette.length)],
        radius: 3 + random.nextDouble() * 3,
        life: 1.0,
        isLocal: isLocal,
      ));
    }
    if (_particles.length > 600) {
      _particles.removeRange(0, _particles.length - 600);
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final now = DateTime.now();
    if (_lastEmissionAt != null &&
        now.difference(_lastEmissionAt!) < const Duration(milliseconds: 40)) {
      return;
    }
    _lastEmissionAt = now;
    final seed = _random.nextInt(0x7fffffff);
    setState(() {
      _spawn(details.localPosition, isLocal: true, seed: seed);
    });
    if (_canvasSize == Size.zero) return;
    ref.read(modeEventBusProvider).send(ModeEvent(
          type: 'sandbox_particle',
          data: {
            'x': details.localPosition.dx / _canvasSize.width,
            'y': details.localPosition.dy / _canvasSize.height,
            'seed': seed,
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
            if (_pendingPartnerBursts.isNotEmpty) {
              for (final (normalized, seed) in _pendingPartnerBursts) {
                _spawn(
                  Offset(
                    normalized.dx * _canvasSize.width,
                    normalized.dy * _canvasSize.height,
                  ),
                  isLocal: false,
                  seed: seed,
                );
              }
              _pendingPartnerBursts.clear();
            }
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
