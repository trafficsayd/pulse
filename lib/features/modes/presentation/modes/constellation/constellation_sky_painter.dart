import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../application/constellation/constellation_models.dart';

/// OLED-friendly renderer for a shared, deterministic sky.
///
/// Geometry comes entirely from [snapshot]. [phase] only adds a slow local
/// shimmer, so peers always see the same stars and story lines.
class ConstellationSkyPainter extends CustomPainter {
  const ConstellationSkyPainter({
    required this.snapshot,
    required this.localAuthorId,
    required this.phase,
    required this.revealProgress,
    required this.reduceMotion,
  });

  final ConstellationSnapshot snapshot;
  final String localAuthorId;
  final double phase;
  final double revealProgress;
  final bool reduceMotion;

  static const _local = Color(0xFFC4B5FD);
  static const _partner = Color(0xFFFF8AD8);
  static const _bridge = Color(0xFF7DDCFF);
  static const _background = Color(0xFF05050A);

  @override
  void paint(Canvas canvas, Size size) {
    _paintAtmosphere(canvas, size);
    _paintDust(canvas, size);
    if (snapshot.stars.isEmpty) {
      _paintInvitation(canvas, size);
      return;
    }
    final byId = <String, ConstellationStar>{
      for (final star in snapshot.stars) star.id: star,
    };
    _paintEdges(canvas, size, byId);
    _paintStars(canvas, size);
  }

  void _paintAtmosphere(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.42, -.28),
          radius: 1.18,
          colors: [Color(0xFF17102C), Color(0xFF090A14), _background],
          stops: [0, .49, 1],
        ).createShader(Offset.zero & size),
    );
    canvas.drawCircle(
      Offset(size.width * .82, size.height * .72),
      size.shortestSide * .44,
      Paint()
        ..shader = RadialGradient(
          colors: [_partner.withValues(alpha: .055), Colors.transparent],
        ).createShader(
          Rect.fromCircle(
            center: Offset(size.width * .82, size.height * .72),
            radius: size.shortestSide * .44,
          ),
        ),
    );
  }

  void _paintDust(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 58; i++) {
      final x = _unit(i * 92821 + 17);
      final y = _unit(i * 68917 + 71);
      final shimmer = reduceMotion
          ? .72
          : .55 + .35 * math.sin(phase * math.pi * 2 + i * .83).abs();
      paint.color = Colors.white.withValues(alpha: .05 + shimmer * .11);
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        .35 + _unit(i * 4177) * .75,
        paint,
      );
    }
  }

  void _paintInvitation(Canvas canvas, Size size) {
    final center = Offset(size.width * .5, size.height * .52);
    final breath = reduceMotion ? 1.0 : .9 + .1 * math.sin(phase * math.pi * 2);
    canvas.drawCircle(
      center,
      42 * breath,
      Paint()
        ..color = _local.withValues(alpha: .035)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawCircle(
      center,
      5.5,
      Paint()..color = _local.withValues(alpha: .22),
    );
    canvas.drawCircle(center, 1.7, Paint()..color = Colors.white);
  }

  void _paintEdges(
    Canvas canvas,
    Size size,
    Map<String, ConstellationStar> byId,
  ) {
    if (snapshot.edges.isEmpty || revealProgress <= 0) return;
    for (var i = 0; i < snapshot.edges.length; i++) {
      final edge = snapshot.edges[i];
      final from = byId[edge.fromId];
      final to = byId[edge.toId];
      if (from == null || to == null) continue;
      final startWindow = i / snapshot.edges.length * .7;
      final progress =
          ((revealProgress - startWindow) / .3).clamp(0.0, 1.0).toDouble();
      if (progress <= 0) continue;

      final a = _point(from, size);
      final b = _point(to, size);
      final end = Offset.lerp(a, b, _easeOutQuint(progress))!;
      final color = edge.bridgesPeople ? _bridge : _local;
      final alpha = .12 + edge.weight * .34;
      final stroke = .55 + edge.weight * .85;
      final linePaint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final glowPaint = Paint()
        ..color = color.withValues(alpha: alpha * .22)
        ..strokeWidth = stroke + 5
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

      if (edge.pauseMs > 4500) {
        _drawDashed(canvas, a, end, glowPaint);
        _drawDashed(canvas, a, end, linePaint);
      } else {
        canvas.drawLine(a, end, glowPaint);
        canvas.drawLine(a, end, linePaint);
      }
      if (edge.crossesStory && progress > .92) {
        final midpoint = Offset.lerp(a, b, .5)!;
        canvas.drawCircle(
          midpoint,
          8,
          Paint()
            ..color = _bridge.withValues(alpha: .16)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawCircle(
          midpoint,
          1.35,
          Paint()..color = Colors.white.withValues(alpha: .8),
        );
      }
    }
  }

  void _paintStars(Canvas canvas, Size size) {
    for (var i = 0; i < snapshot.stars.length; i++) {
      final star = snapshot.stars[i];
      final point = _point(star, size);
      final isLocal = star.authorId == localAuthorId;
      final color = isLocal ? _local : _partner;
      final pulse = reduceMotion
          ? 1.0
          : .94 + .08 * math.sin(phase * math.pi * 2 + i * 1.37);
      final radius = (2.55 + star.energy * 1.7) * pulse;

      canvas.drawCircle(
        point,
        radius * 3.8,
        Paint()
          ..color = color.withValues(alpha: .15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
      if (!isLocal) {
        canvas.drawCircle(
          point,
          radius + 3.4,
          Paint()
            ..color = color.withValues(alpha: .34)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .65,
        );
      }
      canvas.drawCircle(point, radius, Paint()..color = color);
      canvas.drawCircle(
        point.translate(-radius * .22, -radius * .24),
        radius * .36,
        Paint()..color = Colors.white.withValues(alpha: .92),
      );
    }
  }

  void _drawDashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    final vector = b - a;
    final length = vector.distance;
    if (length <= 0) return;
    final direction = vector / length;
    const dash = 5.0;
    const gap = 5.0;
    for (var cursor = 0.0; cursor < length; cursor += dash + gap) {
      canvas.drawLine(
        a + direction * cursor,
        a + direction * math.min(cursor + dash, length),
        paint,
      );
    }
  }

  Offset _point(ConstellationStar star, Size size) =>
      Offset(star.x * size.width, star.y * size.height);

  double _unit(int seed) {
    var value = seed & 0x7fffffff;
    value = (value * 1103515245 + 12345) & 0x7fffffff;
    return value / 0x7fffffff;
  }

  double _easeOutQuint(double value) => 1 - math.pow(1 - value, 5).toDouble();

  @override
  bool shouldRepaint(covariant ConstellationSkyPainter oldDelegate) =>
      oldDelegate.snapshot.fingerprint != snapshot.fingerprint ||
      oldDelegate.phase != phase ||
      oldDelegate.revealProgress != revealProgress ||
      oldDelegate.localAuthorId != localAuthorId ||
      oldDelegate.reduceMotion != reduceMotion;
}
