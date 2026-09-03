import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../application/fireworks/firework_models.dart';

/// One bounded renderer for every rocket, particle and joint culmination.
/// Particle geometry is derived solely from the contribution seed.
class SharedFireworksPainter extends CustomPainter {
  const SharedFireworksPainter({
    required this.snapshot,
    required this.localAuthorId,
    required this.activationById,
    required this.frameNowMs,
    required this.ambientPhase,
    required this.reduceMotion,
  });

  final FireworkSnapshot snapshot;
  final String localAuthorId;
  final Map<String, int> activationById;
  final int frameNowMs;
  final double ambientPhase;
  final bool reduceMotion;

  static const List<List<Color>> palettes = [
    [Color(0xFFC9B8FF), Color(0xFF8D75FF), Color(0xFFF7EFFF)],
    [Color(0xFFFF91D2), Color(0xFFFF5F8F), Color(0xFFFFE5F5)],
    [Color(0xFFFFD477), Color(0xFFFF8A5C), Color(0xFFFFF1C2)],
    [Color(0xFF76E8FF), Color(0xFF4B9FFF), Color(0xFFE1FAFF)],
    [Color(0xFF78F0BA), Color(0xFF5DC7A8), Color(0xFFE1FFF4)],
    [Color(0xFFFFF0A3), Color(0xFFE8B6FF), Color(0xFFFFFFFF)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    _paintAtmosphere(canvas, size);
    for (final contribution in snapshot.contributions) {
      _paintContribution(canvas, size, contribution);
    }
    for (final culmination in snapshot.culminations) {
      _paintCulmination(canvas, size, culmination);
    }
  }

  void _paintAtmosphere(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -.42),
          radius: 1.18,
          colors: [Color(0xFF171025), Color(0xFF080911), Color(0xFF040509)],
          stops: [0, .55, 1],
        ).createShader(bounds),
    );
    final dust = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 42; i++) {
      final flicker = reduceMotion
          ? .7
          : .55 + .35 * math.sin(ambientPhase * math.pi * 2 + i * .71).abs();
      dust.color = Colors.white.withValues(alpha: .035 + flicker * .07);
      canvas.drawCircle(
        Offset(
          _unit(31, i, 7) * size.width,
          _unit(47, i, 13) * size.height * .82,
        ),
        .35 + _unit(71, i, 3) * .55,
        dust,
      );
    }
  }

  void _paintContribution(
    Canvas canvas,
    Size size,
    FireworkContribution item,
  ) {
    final activatedAt = activationById[item.id];
    if (activatedAt == null) return;
    final age = frameNowMs - activatedAt;
    if (age < 0 ||
        (!reduceMotion && age > 3200) ||
        (reduceMotion && age > 6000)) {
      return;
    }
    final target = Offset(item.x * size.width, item.y * size.height);
    final start = Offset(
      (.2 + _unit(item.seed, 0, 91) * .6) * size.width,
      size.height + 20,
    );
    final colors = palettes[item.palette % palettes.length];
    if (reduceMotion) {
      _paintStaticBloom(canvas, target, colors, item.seed, 26, .13);
      return;
    }
    final progress = (age / 3000).clamp(0.0, 1.0).toDouble();
    if (progress < .27) {
      final t = _easeOutCubic(progress / .27);
      final current = Offset.lerp(start, target, t)!;
      final trail = Paint()
        ..color = colors.first.withValues(alpha: .64)
        ..strokeWidth = item.authorId == localAuthorId ? 1.7 : 1.15
        ..strokeCap = StrokeCap.round;
      if (item.authorId == localAuthorId) {
        canvas.drawLine(Offset.lerp(start, current, .5)!, current, trail);
      } else {
        _dashedLine(canvas, Offset.lerp(start, current, .5)!, current, trail);
      }
      canvas.drawCircle(
        current,
        3.2,
        Paint()..color = colors.last.withValues(alpha: .95),
      );
      return;
    }
    final burst = ((progress - .27) / .73).clamp(0.0, 1.0).toDouble();
    _paintBurst(
      canvas,
      target,
      colors,
      item.seed,
      progress: burst,
      count: 34,
      reach: size.shortestSide * .25,
      spiral: item.authorId != localAuthorId,
    );
  }

  void _paintCulmination(
    Canvas canvas,
    Size size,
    FireworkCulmination joint,
  ) {
    final firstActivation = activationById[joint.firstId];
    final secondActivation = activationById[joint.secondId];
    if (firstActivation == null || secondActivation == null) return;
    final activatedAt = math.max(firstActivation, secondActivation) + 720;
    final age = frameNowMs - activatedAt;
    if (age < 0 ||
        (!reduceMotion && age > 3700) ||
        (reduceMotion && age > 6500)) {
      return;
    }
    final center = Offset(joint.x * size.width, joint.y * size.height);
    final colors = [
      palettes[joint.paletteA % palettes.length][0],
      palettes[joint.paletteB % palettes.length][0],
      Colors.white,
    ];
    if (reduceMotion) {
      _paintStaticBloom(canvas, center, colors, joint.seed, 48, .22);
      return;
    }
    final p = (age / 3500).clamp(0.0, 1.0).toDouble();
    final haloAlpha = (1 - p).clamp(0.0, 1.0) * .2;
    canvas.drawCircle(
      center,
      size.shortestSide * (.08 + p * .24),
      Paint()
        ..color = colors.first.withValues(alpha: haloAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    _paintBurst(
      canvas,
      center,
      colors,
      joint.seed,
      progress: p,
      count: 84,
      reach: size.shortestSide * .44,
      spiral: true,
      joint: true,
    );
  }

  void _paintBurst(
    Canvas canvas,
    Offset origin,
    List<Color> colors,
    int seed, {
    required double progress,
    required int count,
    required double reach,
    required bool spiral,
    bool joint = false,
  }) {
    final eased = _easeOutCubic(progress);
    final fade = math.pow(1 - progress, .72).toDouble();
    for (var i = 0; i < count; i++) {
      final angle = _unit(seed, i, 17) * math.pi * 2 +
          (spiral ? eased * (.48 + _unit(seed, i, 41) * .65) : 0);
      final speed = .34 + _unit(seed, i, 23) * .66;
      final radius = reach * speed * eased;
      final gravity = reach * .2 * progress * progress;
      final point = Offset(
        origin.dx + math.cos(angle) * radius,
        origin.dy + math.sin(angle) * radius + gravity,
      );
      final color = colors[(i + seed) % colors.length];
      final particleRadius = (joint ? 2.2 : 1.8) * fade + .35;
      canvas.drawCircle(
        point,
        particleRadius * 2.2,
        Paint()..color = color.withValues(alpha: fade * .1),
      );
      canvas.drawCircle(
        point,
        particleRadius,
        Paint()..color = color.withValues(alpha: fade * .9),
      );
      if (i % 7 == 0) {
        final tail = Offset(
          point.dx - math.cos(angle) * particleRadius * 3.4,
          point.dy - math.sin(angle) * particleRadius * 3.4,
        );
        canvas.drawLine(
          tail,
          point,
          Paint()
            ..color = color.withValues(alpha: fade * .42)
            ..strokeWidth = .7
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  void _paintStaticBloom(
    Canvas canvas,
    Offset origin,
    List<Color> colors,
    int seed,
    int count,
    double reachFactor,
  ) {
    for (var i = 0; i < count; i++) {
      final angle = _unit(seed, i, 17) * math.pi * 2;
      final radius = (16 + _unit(seed, i, 23) * 190) * reachFactor;
      final point = origin + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(
        point,
        1.4 + _unit(seed, i, 31) * 1.5,
        Paint()..color = colors[i % colors.length].withValues(alpha: .75),
      );
    }
  }

  void _dashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    final vector = to - from;
    final length = vector.distance;
    if (length == 0) return;
    final direction = vector / length;
    for (var cursor = 0.0; cursor < length; cursor += 7) {
      canvas.drawLine(
        from + direction * cursor,
        from + direction * math.min(cursor + 3.4, length),
        paint,
      );
    }
  }

  double _unit(int seed, int index, int salt) {
    var value = (seed ^ (index * 374761393) ^ salt) & 0x7fffffff;
    value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff;
    return value / 0x7fffffff;
  }

  double _easeOutCubic(double value) => 1 - math.pow(1 - value, 3).toDouble();

  @override
  bool shouldRepaint(covariant SharedFireworksPainter oldDelegate) =>
      oldDelegate.snapshot.fingerprint != snapshot.fingerprint ||
      oldDelegate.frameNowMs != frameNowMs ||
      oldDelegate.ambientPhase != ambientPhase ||
      oldDelegate.reduceMotion != reduceMotion ||
      oldDelegate.activationById.length != activationById.length;
}
