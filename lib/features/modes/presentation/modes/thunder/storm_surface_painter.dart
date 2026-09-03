import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../application/thunder/thunder_choreography.dart';
import '../../../application/thunder/thunder_models.dart';

class StormSurfacePainter extends CustomPainter {
  StormSurfacePainter({
    required this.strikes,
    required this.gesture,
    required this.now,
    required this.reduceMotion,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final List<ThunderVisualStrike> strikes;
  final List<Offset> gesture;
  final DateTime Function() now;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    _paintSky(canvas, size);
    for (final visual in strikes) {
      _paintStrike(canvas, size, visual);
    }
    _paintGesture(canvas);
  }

  void _paintSky(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF12132A), Color(0xFF080913), AppColors.background],
          stops: [0, .54, 1],
        ).createShader(Offset.zero & size),
    );
    for (var cloud = 0; cloud < 6; cloud++) {
      final center = Offset(
        size.width * (.05 + cloud * .19),
        size.height * (.14 + .035 * math.sin(cloud * 1.7)),
      );
      final rect = Rect.fromCenter(
        center: center,
        width: size.width * .46,
        height: size.height * .17,
      );
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(colors: [
            const Color(0xFF6E69A8).withValues(alpha: .095),
            Colors.transparent,
          ]).createShader(rect),
      );
    }
    if (!reduceMotion) {
      final rain = Paint()
        ..color = const Color(0xFFB9C5FF).withValues(alpha: .055)
        ..strokeWidth = .8;
      for (var i = 0; i < 38; i++) {
        final x = (math.sin(i * 88.31) * .5 + .5) * size.width;
        final y = (math.sin(i * 29.77 + 1.9) * .5 + .5) * size.height;
        canvas.drawLine(Offset(x, y), Offset(x - 4, y + 18), rain);
      }
    }
  }

  void _paintStrike(Canvas canvas, Size size, ThunderVisualStrike visual) {
    final strike = visual.strike;
    final cues = ThunderChoreography.cues(
      strike,
      reduceMotion: reduceMotion,
    );
    final elapsed = now().difference(visual.startedAt).inMilliseconds;
    if (elapsed < 0 || elapsed > cues.totalDurationMs + 240) return;

    final flashDelta = elapsed - cues.flashDelayMs;
    final flashWindow = reduceMotion ? 90 : 170;
    if (flashDelta >= 0 && flashDelta < flashWindow) {
      final flash = 1 - flashDelta / flashWindow;
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = const Color(0xFFE7E4FF).withValues(
            alpha: flash * strike.intensity * (reduceMotion ? .09 : .24),
          )
          ..blendMode = BlendMode.screen,
      );
    }

    final boltDelta = elapsed - cues.impactDelayMs;
    if (boltDelta >= 0 && boltDelta < (reduceMotion ? 520 : 700)) {
      final reveal = (boltDelta / 105).clamp(0.0, 1.0);
      final fade = (1 - boltDelta / (reduceMotion ? 520 : 700)).clamp(0.0, 1.0);
      _paintGeometry(
        canvas,
        size,
        visual.geometry,
        reveal: reduceMotion ? 1 : Curves.easeOutCubic.transform(reveal),
        alpha: fade * (.58 + strike.intensity * .42),
      );
    }

    final rumbleDelta = elapsed - cues.rumbleDelayMs;
    if (rumbleDelta >= 0 && rumbleDelta < cues.rumbleDurationMs) {
      final progress = rumbleDelta / cues.rumbleDurationMs;
      final direction = Offset(strike.directionX, strike.directionY);
      final start = visual.isLocal
          ? Offset(strike.originX * size.width, strike.originY * size.height)
          : Offset(
              strike.directionX >= 0 ? 0 : size.width,
              strike.directionY >= 0 ? 0 : size.height,
            );
      final center = start +
          direction *
              size.shortestSide *
              (reduceMotion ? .16 : progress * 1.15);
      final glowRect = Rect.fromCircle(
        center: center,
        radius: size.shortestSide * (.12 + progress * .34),
      );
      canvas.drawCircle(
        center,
        glowRect.width / 2,
        Paint()
          ..shader = RadialGradient(colors: [
            AppColors.pulse.withValues(
              alpha: (1 - progress) * strike.intensity * .12,
            ),
            Colors.transparent,
          ]).createShader(glowRect),
      );
      if (!reduceMotion) {
        for (var ring = 0; ring < 3; ring++) {
          final ringProgress = (progress - ring * .09).clamp(0.0, 1.0);
          if (ringProgress <= 0) continue;
          canvas.drawCircle(
            center,
            size.shortestSide * (.08 + ringProgress * .5),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4
              ..color = const Color(0xFF9E9AFF).withValues(
                alpha: (1 - ringProgress) * .14 * strike.intensity,
              ),
          );
        }
      }
    }
  }

  void _paintGeometry(
    Canvas canvas,
    Size size,
    ThunderGeometry geometry, {
    required double reveal,
    required double alpha,
  }) {
    final trunk = _path(geometry.trunk, size, reveal);
    canvas.drawPath(
      trunk,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 18
        ..color = AppColors.pulse.withValues(alpha: .2 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11),
    );
    canvas.drawPath(
      trunk,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 6
        ..color = const Color(0xFFA59EFF).withValues(alpha: .5 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      trunk,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 1.8
        ..color = const Color(0xFFF7F5FF).withValues(alpha: alpha),
    );
    for (final branch in geometry.branches) {
      final path = _path(branch.points, size, reveal);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.1
          ..color =
              const Color(0xFFD3CEFF).withValues(alpha: alpha * branch.opacity),
      );
    }
  }

  Path _path(List<ThunderPoint> geometry, Size size, double reveal) {
    final path = Path();
    if (geometry.isEmpty) return path;
    final visible = math.max(2, (geometry.length * reveal).ceil());
    path.moveTo(geometry.first.x * size.width, geometry.first.y * size.height);
    for (var i = 1; i < math.min(visible, geometry.length); i++) {
      path.lineTo(geometry[i].x * size.width, geometry[i].y * size.height);
    }
    return path;
  }

  void _paintGesture(Canvas canvas) {
    if (gesture.length < 2) return;
    final path = Path()..moveTo(gesture.first.dx, gesture.first.dy);
    for (var i = 1; i < gesture.length; i++) {
      path.lineTo(gesture[i].dx, gesture[i].dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 12
        ..color = AppColors.pulse.withValues(alpha: .1)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.5
        ..color = const Color(0xFFDCD8FF).withValues(alpha: .7),
    );
  }

  @override
  bool shouldRepaint(covariant StormSurfacePainter oldDelegate) => true;
}
