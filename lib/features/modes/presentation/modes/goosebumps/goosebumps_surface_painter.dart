import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../application/goosebumps/goosebumps_wave.dart';

class GoosebumpsSurfacePainter extends CustomPainter {
  GoosebumpsSurfacePainter({
    required this.waves,
    required this.now,
    required this.gesture,
    required this.reduceMotion,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final List<GoosebumpsVisualWave> waves;
  final DateTime Function() now;
  final List<Offset> gesture;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    _paintAtmosphere(canvas, size);
    for (final visual in waves) {
      _paintWave(canvas, size, visual);
    }
    _paintGesture(canvas);
  }

  void _paintAtmosphere(Canvas canvas, Size size) {
    final center = Offset(size.width * .48, size.height * .43);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.08, -.18),
          radius: 1.18,
          colors: [
            AppColors.pulse.withValues(alpha: .14),
            const Color(0xFF101020).withValues(alpha: .58),
            AppColors.background,
          ],
          stops: const [0, .48, 1],
        ).createShader(Offset.zero & size),
    );
    final haze = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFB7A2FF).withValues(alpha: .055),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: center,
        radius: size.shortestSide * .65,
      ));
    canvas.drawCircle(center, size.shortestSide * .65, haze);

    final grain = Paint()..color = Colors.white.withValues(alpha: .018);
    for (var i = 0; i < 54; i++) {
      final x = (math.sin(i * 91.73) * .5 + .5) * size.width;
      final y = (math.sin(i * 37.17 + 2.3) * .5 + .5) * size.height;
      canvas.drawCircle(Offset(x, y), i % 5 == 0 ? 1.1 : .55, grain);
    }
  }

  void _paintWave(Canvas canvas, Size size, GoosebumpsVisualWave visual) {
    final wave = visual.wave;
    final progress = reduceMotion
        ? .54
        : Curves.easeInOutCubic.transform(visual.progress(now()));
    final direction = Offset(wave.directionX, wave.directionY);
    final origin = visual.isLocal
        ? Offset(wave.startX * size.width, wave.startY * size.height)
        : _edgePoint(size, -direction);
    final destination = _edgePoint(size, direction);
    final position = Offset.lerp(origin, destination, progress)!;
    final angle = math.atan2(direction.dy, direction.dx);
    final energy = (math.sin(progress * math.pi) * .68 + .32) *
        (.42 + wave.intensity * .58);

    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(angle);
    final ridgeWidth = size.shortestSide * (.2 + wave.intensity * .16);
    final ridgeHeight = 28 + wave.intensity * 28;
    final glowRect = Rect.fromCenter(
      center: Offset.zero,
      width: ridgeWidth * 2.1,
      height: ridgeHeight * 3.6,
    );
    canvas.drawOval(
      glowRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFE8DEFF).withValues(alpha: .18 * energy),
            AppColors.pulse.withValues(alpha: .15 * energy),
            Colors.transparent,
          ],
          stops: const [0, .36, 1],
        ).createShader(glowRect)
        ..blendMode = BlendMode.screen,
    );

    final ringCount = reduceMotion ? 1 : 4;
    for (var ring = 0; ring < ringCount; ring++) {
      final lag = ring * .12;
      final phase = (progress - lag).clamp(0.0, 1.0);
      if (phase <= 0) continue;
      final rect = Rect.fromCenter(
        center: Offset(-ring * 13.0, 0),
        width: ridgeWidth * (1 + ring * .28),
        height: ridgeHeight * (1 + ring * .36),
      );
      canvas.drawArc(
        rect,
        -.76 * math.pi,
        1.52 * math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(1.0, 3.4 - ring * .62)
          ..color = (visual.isLocal
                  ? const Color(0xFFB995FF)
                  : const Color(0xFFFF8EC8))
              .withValues(alpha: (1 - ring / 5) * energy * .34),
      );
    }

    final bumpPaint = Paint()
      ..color =
          (visual.isLocal ? const Color(0xFFD8C9FF) : const Color(0xFFFFC6E1))
              .withValues(alpha: .22 + energy * .55)
      ..blendMode = BlendMode.screen;
    final bumpCount = reduceMotion ? 10 : 22 + (wave.intensity * 18).round();
    for (var i = 0; i < bumpCount; i++) {
      final seed = i * 2.399963;
      final x = -ridgeWidth * (.15 + .72 * ((i % 11) / 10));
      final y = math.sin(seed) * ridgeHeight * (.42 + (i % 3) * .12);
      final radius = (.75 + wave.intensity * 1.6) *
          (.68 + .32 * math.sin(progress * 12 + i).abs());
      canvas.drawCircle(Offset(x, y), radius, bumpPaint);
    }
    canvas.restore();
  }

  Offset _edgePoint(Size size, Offset direction) {
    final center = Offset(size.width / 2, size.height / 2);
    final dx = direction.dx.abs() < .0001 ? .0001 : direction.dx;
    final dy = direction.dy.abs() < .0001 ? .0001 : direction.dy;
    final tx = dx > 0 ? (size.width - center.dx) / dx : (0 - center.dx) / dx;
    final ty = dy > 0 ? (size.height - center.dy) / dy : (0 - center.dy) / dy;
    return center + direction * math.min(tx.abs(), ty.abs());
  }

  void _paintGesture(Canvas canvas) {
    if (gesture.length < 2) return;
    final path = Path()..moveTo(gesture.first.dx, gesture.first.dy);
    for (var i = 1; i < gesture.length; i++) {
      final previous = gesture[i - 1];
      final current = gesture[i];
      path.quadraticBezierTo(
        previous.dx,
        previous.dy,
        (previous.dx + current.dx) / 2,
        (previous.dy + current.dy) / 2,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round
        ..color = AppColors.pulse.withValues(alpha: .08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFDCCEFF).withValues(alpha: .74),
    );
    final end = gesture.last;
    canvas.drawCircle(
      end,
      18,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: .8),
          AppColors.pulse.withValues(alpha: .25),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: end, radius: 18)),
    );
  }

  @override
  bool shouldRepaint(covariant GoosebumpsSurfacePainter oldDelegate) => true;
}
