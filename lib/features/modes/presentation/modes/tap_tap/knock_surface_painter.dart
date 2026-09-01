import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../application/tap_tap/knock_models.dart';
import '../../../../../core/theme/app_colors.dart';

class KnockResonanceVisual {
  const KnockResonanceVisual({
    required this.from,
    required this.to,
    required this.createdAt,
  });

  final Offset from;
  final Offset to;
  final DateTime createdAt;
}

class KnockSurfacePainter extends CustomPainter {
  const KnockSurfacePainter({
    required this.hits,
    required this.now,
    required this.ambientProgress,
    this.pressedPosition,
    this.resonance,
    this.reduceMotion = false,
  });

  final List<KnockVisualHit> hits;
  final DateTime now;
  final double ambientProgress;
  final Offset? pressedPosition;
  final KnockResonanceVisual? resonance;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    _drawAmbient(canvas, size);
    final pressed = pressedPosition;
    if (pressed != null) _drawPressed(canvas, pressed);
    for (final visual in hits) {
      _drawHit(canvas, size, visual);
    }
    final link = resonance;
    if (link != null) _drawResonance(canvas, link);
  }

  void _drawAmbient(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = math.min(size.width, size.height) * .43;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final t = (ambientProgress + i / 3) % 1;
      paint.color = AppColors.pulse.withValues(alpha: (1 - t) * .10);
      canvas.drawCircle(center, 42 + maxRadius * t, paint);
    }
  }

  void _drawPressed(Canvas canvas, Offset point) {
    final radius = reduceMotion ? 28.0 : 42.0;
    canvas.drawCircle(
      point,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.black.withValues(alpha: .32),
            AppColors.pulse.withValues(alpha: .12),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: point, radius: radius)),
    );
  }

  void _drawHit(Canvas canvas, Size size, KnockVisualHit visual) {
    final progress = visual.progress(now);
    if (progress >= 1) return;
    final point = Offset(visual.hit.x * size.width, visual.hit.y * size.height);
    final character = visual.hit.character;
    final baseColor = visual.isLocal ? AppColors.pulse : AppColors.heart;
    final eased = Curves.easeOutCubic.transform(progress);
    final opacity = math.pow(1 - progress, 1.7).toDouble();
    final radius = reduceMotion
        ? 24 + 34 * eased
        : 18 + (105 + character.intensity * 70) * eased;

    final contactRadius = 9 + character.intensity * 13;
    canvas.drawCircle(
      point,
      contactRadius * (1 - progress * .25),
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: opacity * .86),
            baseColor.withValues(alpha: opacity * .42),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(center: point, radius: contactRadius * 1.8),
        ),
    );
    canvas.drawCircle(
      point,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 + character.sharpness * 1.7
        ..color = baseColor.withValues(alpha: opacity * .72),
    );
    if (!reduceMotion && character.intensity > .55) {
      canvas.drawCircle(
        point,
        radius * .72,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: opacity * .19),
      );
    }
  }

  void _drawResonance(Canvas canvas, KnockResonanceVisual link) {
    final age = now.difference(link.createdAt).inMilliseconds / 1250;
    if (age >= 1) return;
    final opacity = Curves.easeOut.transform(1 - age);
    final path = Path()
      ..moveTo(link.from.dx, link.from.dy)
      ..quadraticBezierTo(
        (link.from.dx + link.to.dx) / 2,
        (link.from.dy + link.to.dy) / 2 - 24 * math.sin(age * math.pi),
        link.to.dx,
        link.to.dy,
      );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..shader = LinearGradient(
          colors: [
            AppColors.pulse.withValues(alpha: opacity),
            Colors.white.withValues(alpha: opacity),
            const Color(0xFF7CEFD0).withValues(alpha: opacity),
          ],
        ).createShader(Rect.fromPoints(link.from, link.to)),
    );
  }

  @override
  bool shouldRepaint(KnockSurfacePainter oldDelegate) => true;
}
