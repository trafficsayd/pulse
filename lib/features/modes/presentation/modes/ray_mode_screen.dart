import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../../core/theme/app_colors.dart';
import 'mode_close_button.dart';

/// "Ray" — drag a finger across the screen to draw a thin line of light.
/// The trail fades over ~1.6 s. The partner sees a mirrored ghost trail in
/// the simulated foundation; the real runner replaces this with the inbound
/// pointer stream.
class RayModeScreen extends StatefulWidget {
  const RayModeScreen({super.key});

  @override
  State<RayModeScreen> createState() => _RayModeScreenState();
}

class _RayModeScreenState extends State<RayModeScreen>
    with TickerProviderStateMixin {
  final List<_RayStroke> _strokes = [];
  _RayStroke? _current;

  void _begin(Offset position) {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    final stroke = _RayStroke(
      points: [position],
      controller: controller,
      isLocal: true,
    );
    setState(() {
      _strokes.add(stroke);
      _current = stroke;
    });
    HapticFeedback.selectionClick();
  }

  void _extend(Offset position) {
    final stroke = _current;
    if (stroke == null) return;
    setState(() => stroke.points.add(position));
  }

  void _end(Size size) {
    final stroke = _current;
    if (stroke == null) return;
    _current = null;
    stroke.controller.forward().whenComplete(() {
      if (!mounted) return;
      setState(() => _strokes.remove(stroke));
      stroke.controller.dispose();
    });

    // Simulated partner echo — mirror the stroke horizontally with a delay.
    Future.delayed(const Duration(milliseconds: 240), () {
      if (!mounted) return;
      final ghostController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1600),
      );
      final ghost = _RayStroke(
        points: stroke.points
            .map((p) => Offset(size.width - p.dx, p.dy))
            .toList(),
        controller: ghostController,
        isLocal: false,
      );
      setState(() => _strokes.add(ghost));
      ghostController.forward().whenComplete(() {
        if (!mounted) return;
        setState(() => _strokes.remove(ghost));
        ghostController.dispose();
      });
    });
  }

  @override
  void dispose() {
    for (final s in _strokes) {
      s.controller.dispose();
    }
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
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) => _begin(e.localPosition),
                    onPointerMove: (e) => _extend(e.localPosition),
                    onPointerUp: (_) => _end(size),
                    onPointerCancel: (_) => _end(size),
                    child: AnimatedBuilder(
                      animation: Listenable.merge(
                        _strokes.map((s) => s.controller).toList(),
                      ),
                      builder: (context, _) {
                        return CustomPaint(
                          size: size,
                          painter: _RayPainter(strokes: _strokes),
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      t.rayHint,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  top: 8,
                  right: 8,
                  child: ModeCloseButton(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RayStroke {
  _RayStroke({
    required this.points,
    required this.controller,
    required this.isLocal,
  });

  final List<Offset> points;
  final AnimationController controller;
  final bool isLocal;
}

class _RayPainter extends CustomPainter {
  _RayPainter({required this.strokes});

  final List<_RayStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;
      final progress = stroke.controller.value;
      final opacity = (1 - progress).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = (stroke.isLocal
                ? AppColors.pulse
                : AppColors.transportLocal)
            .withValues(alpha: opacity * 0.85)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (var i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RayPainter oldDelegate) =>
      oldDelegate.strokes != strokes;
}
