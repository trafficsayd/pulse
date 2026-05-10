import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import 'mode_close_button.dart';

/// Paid "Thread" mode: drag your finger to spin a fading thread between
/// successive points on the canvas. Symbolises a delicate connecting
/// filament between partners.
class ThreadModeScreen extends ConsumerStatefulWidget {
  const ThreadModeScreen({super.key});

  @override
  ConsumerState<ThreadModeScreen> createState() => _ThreadModeScreenState();
}

class _ThreadModeScreenState extends ConsumerState<ThreadModeScreen> {
  final List<_ThreadPoint> _points = [];

  void _add(Offset p) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _points.add(_ThreadPoint(p, stamp));
      // Drop points older than 1.6s to keep the thread short and lively.
      _points.removeWhere((pt) => stamp - pt.bornAt > 1600);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onPanStart: (d) => _add(d.localPosition),
        onPanUpdate: (d) => _add(d.localPosition),
        behavior: HitTestBehavior.opaque,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: AppColors.backgroundGradient,
          ),
          child: Stack(
            children: [
              CustomPaint(
                size: Size.infinite,
                painter: _ThreadPainter(_points),
              ),
              const ModeCloseButton(),
              Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Text(
                  t.threadHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreadPoint {
  const _ThreadPoint(this.offset, this.bornAt);
  final Offset offset;
  final int bornAt;
}

class _ThreadPainter extends CustomPainter {
  _ThreadPainter(this.points);
  final List<_ThreadPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke;
    for (var i = 1; i < points.length; i++) {
      final age = (now - points[i].bornAt) / 1600.0;
      paint.color = AppColors.pulse.withValues(alpha: (1.0 - age).clamp(0, 1));
      canvas.drawLine(points[i - 1].offset, points[i].offset, paint);
    }
  }

  @override
  bool shouldRepaint(_ThreadPainter old) => true;
}
