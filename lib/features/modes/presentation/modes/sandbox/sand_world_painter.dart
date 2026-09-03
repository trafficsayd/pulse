import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../application/sandbox/sand_models.dart';
import '../../../application/sandbox/sand_simulation.dart';

class SandWorldPainter extends CustomPainter {
  SandWorldPainter({
    required this.world,
    required this.localGesture,
    required this.remoteTraces,
    required this.now,
    required this.reduceMotion,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final SandWorld world;
  final List<Offset> localGesture;
  final List<SandRemoteTrace> remoteTraces;
  final DateTime Function() now;
  final bool reduceMotion;

  static const _colors = <Color>[
    Color(0xFFAA77FF),
    Color(0xFFFF78AD),
    Color(0xFFD9DDFF),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    _paintSurface(canvas, size);
    _paintSand(canvas, size);
    _paintRemoteTraces(canvas, size);
    _paintLocalGesture(canvas);
  }

  void _paintSurface(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF11111D), Color(0xFF090A10), AppColors.background],
          stops: [0, .58, 1],
        ).createShader(Offset.zero & size),
    );
    final bedRect =
        Rect.fromLTWH(0, size.height * .7, size.width, size.height * .3);
    canvas.drawRect(
      bedRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.pulse.withValues(alpha: .025),
            AppColors.pulse.withValues(alpha: .075),
          ],
        ).createShader(bedRect),
    );
  }

  void _paintSand(Canvas canvas, Size size) {
    final groups = List.generate(3, (_) => <Offset>[]);
    final cellWidth = size.width / world.columns;
    final cellHeight = size.height / world.rows;
    for (var y = 0; y < world.rows; y++) {
      for (var x = 0; x < world.columns; x++) {
        final material = world.at(x, y);
        if (material <= 0 || material > groups.length) continue;
        groups[material - 1].add(Offset(
          (x + .5) * cellWidth,
          (y + .5) * cellHeight,
        ));
      }
    }
    for (var material = 0; material < groups.length; material++) {
      final points = groups[material];
      if (points.isEmpty) continue;
      canvas.drawPoints(
        ui.PointMode.points,
        points,
        Paint()
          ..color = _colors[material].withValues(alpha: .18)
          ..strokeWidth = math.max(cellWidth, cellHeight) * 1.8
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4),
      );
      canvas.drawPoints(
        ui.PointMode.points,
        points,
        Paint()
          ..color = _colors[material].withValues(alpha: .87)
          ..strokeWidth = math.min(cellWidth, cellHeight) * .82
          ..strokeCap = StrokeCap.round,
      );
      if (!reduceMotion) {
        final highlights = <Offset>[];
        for (var index = 0; index < points.length; index += 7) {
          highlights.add(points[index] + const Offset(-.7, -.8));
        }
        canvas.drawPoints(
          ui.PointMode.points,
          highlights,
          Paint()
            ..color = Colors.white.withValues(alpha: .32)
            ..strokeWidth = 1
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  void _paintRemoteTraces(Canvas canvas, Size size) {
    final current = now();
    for (final trace in remoteTraces) {
      final age = current.difference(trace.createdAt).inMilliseconds;
      if (age < 0 || age > 900 || trace.command.points.isEmpty) continue;
      final alpha = (1 - age / 900).clamp(0.0, 1.0);
      final path = Path();
      for (var i = 0; i < trace.command.points.length; i++) {
        final point = trace.command.points[i];
        final scaled = Offset(point.x * size.width, point.y * size.height);
        if (i == 0) {
          path.moveTo(scaled.dx, scaled.dy);
        } else {
          path.lineTo(scaled.dx, scaled.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = trace.command.tool == SandTool.erase ? 18 : 10
          ..color = const Color(0xFFFFA5D0).withValues(alpha: alpha * .16)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.4
          ..color = const Color(0xFFFFCAE3).withValues(alpha: alpha * .7),
      );
    }
  }

  void _paintLocalGesture(Canvas canvas) {
    if (localGesture.length < 2) return;
    final path = Path()..moveTo(localGesture.first.dx, localGesture.first.dy);
    for (var i = 1; i < localGesture.length; i++) {
      path.lineTo(localGesture[i].dx, localGesture[i].dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 10
        ..color = const Color(0xFFB98CFF).withValues(alpha: .11)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.4
        ..color = const Color(0xFFE1D4FF).withValues(alpha: .72),
    );
  }

  @override
  bool shouldRepaint(covariant SandWorldPainter oldDelegate) => true;
}
