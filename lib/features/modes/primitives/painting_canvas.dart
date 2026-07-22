import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// One point in a [PaintStroke]. We keep [pressure] so future devices /
/// stylus support can vary line weight per sample without a schema bump.
class PaintPoint {
  const PaintPoint(this.position, {this.pressure = 1.0, this.timestamp});

  final Offset position;
  final double pressure;
  final DateTime? timestamp;
}

/// A finished or in-progress brushstroke.
class PaintStroke {
  PaintStroke({
    required this.color,
    required this.strokeWidth,
    List<PaintPoint>? points,
  }) : points = points ?? [];

  final Color color;
  final double strokeWidth;
  final List<PaintPoint> points;

  PaintStroke copy() => PaintStroke(
        color: color,
        strokeWidth: strokeWidth,
        points: List.of(points),
      );
}

/// Drop-in painting widget for Ray-Sketch / Doodle / Constellation modes.
///
/// Why centralise:
///   * One canvas implementation == one place to optimise.
///   * Uses a [RepaintBoundary] so partner overlays redrawing at 60fps
///     don't invalidate the rest of the mode screen.
///   * Optional [onStrokeFinished] for the network layer (Track B) —
///     publish strokes as they finish, not on every pointer move.
class PaintingCanvas extends StatefulWidget {
  const PaintingCanvas({
    super.key,
    required this.color,
    this.strokeWidth = 4.0,
    this.background = Colors.transparent,
    this.onStrokeFinished,
  });

  final Color color;
  final double strokeWidth;
  final Color background;
  final ValueChanged<PaintStroke>? onStrokeFinished;

  @override
  State<PaintingCanvas> createState() => PaintingCanvasState();
}

class PaintingCanvasState extends State<PaintingCanvas> {
  final List<PaintStroke> _strokes = [];
  PaintStroke? _active;

  /// Read-only snapshot of finished + in-progress strokes. The network
  /// layer can call this from outside (e.g. on a re-sync) instead of
  /// listening to [PaintingCanvas.onStrokeFinished].
  List<PaintStroke> get strokes => List.unmodifiable([
        ..._strokes,
        if (_active != null) _active!.copy(),
      ]);

  void clear() => setState(() {
        _strokes.clear();
        _active = null;
      });

  /// Programmatically push a stroke (e.g. from the partner).
  void pushRemoteStroke(PaintStroke stroke) {
    setState(() {
      _strokes.add(stroke);
    });
  }

  void _begin(Offset position) {
    setState(() {
      _active =
          PaintStroke(color: widget.color, strokeWidth: widget.strokeWidth)
            ..points.add(PaintPoint(position, timestamp: DateTime.now()));
    });
  }

  void _extend(Offset position) {
    if (_active == null) return;
    setState(() {
      _active!.points.add(PaintPoint(position, timestamp: DateTime.now()));
    });
  }

  void _end() {
    final finished = _active;
    if (finished == null) return;
    setState(() {
      _strokes.add(finished);
      _active = null;
    });
    if (finished.points.isNotEmpty) {
      widget.onStrokeFinished?.call(finished);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) => _begin(details.localPosition),
        onPanUpdate: (details) => _extend(details.localPosition),
        onPanEnd: (_) => _end(),
        onPanCancel: _end,
        child: CustomPaint(
          painter: _PaintingPainter(
            background: widget.background,
            strokes: [..._strokes, ?_active],
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _PaintingPainter extends CustomPainter {
  _PaintingPainter({required this.background, required this.strokes});

  final Color background;
  final List<PaintStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    if (background.a > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = background,
      );
    }
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;
      if (stroke.points.length == 1) {
        canvas.drawCircle(
          stroke.points.first.position,
          stroke.strokeWidth / 2,
          Paint()
            ..color = stroke.color
            ..isAntiAlias = true,
        );
        continue;
      }
      final path = ui.Path()
        ..moveTo(
            stroke.points.first.position.dx, stroke.points.first.position.dy);
      for (var i = 1; i < stroke.points.length; i++) {
        path.lineTo(
          stroke.points[i].position.dx,
          stroke.points[i].position.dy,
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PaintingPainter old) {
    return old.background != background || old.strokes != strokes;
  }
}
