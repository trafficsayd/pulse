import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../application/bell/bell_models.dart';

class BellPhysicalPainter extends CustomPainter {
  const BellPhysicalPainter({
    required this.state,
    required this.material,
    required this.ambientProgress,
    required this.strikePulse,
    required this.remotePulse,
    required this.reduceMotion,
  });

  final BellPhysicsState state;
  final BellMaterial material;
  final double ambientProgress;
  final double strikePulse;
  final bool remotePulse;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .49);
    final scale = math.min(size.width / 390, size.height / 650);
    _paintAtmosphere(canvas, center, scale);
    _paintShadow(canvas, center, scale);

    canvas.save();
    canvas.translate(center.dx, center.dy - 72 * scale);
    final visualAngle = reduceMotion ? state.angle * .25 : state.angle;
    canvas.rotate(visualAngle);
    canvas.scale(scale);
    _paintMount(canvas);
    _paintBell(canvas);
    _paintClapper(
      canvas,
      reduceMotion ? state.clapperAngle * .35 : state.clapperAngle,
    );
    canvas.restore();
  }

  void _paintAtmosphere(Canvas canvas, Offset center, double scale) {
    final energy = math.max(state.resonance, strikePulse);
    final glowColor = _palette.glow;
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          glowColor.withValues(alpha: .12 + energy * .16),
          glowColor.withValues(alpha: .025),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: 190 * scale));
    canvas.drawCircle(center, 190 * scale, glow);

    if (energy <= .015) return;
    final phase = reduceMotion ? .45 : ambientProgress;
    for (var i = 0; i < 3; i++) {
      final progress = (phase + i / 3) % 1;
      final wavePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = (remotePulse ? const Color(0xFFB995FF) : glowColor)
            .withValues(alpha: .2 * energy * (1 - progress));
      canvas.drawOval(
        Rect.fromCenter(
          center: center.translate(0, 52 * scale),
          width: (160 + progress * 260) * scale,
          height: (62 + progress * 92) * scale,
        ),
        wavePaint,
      );
    }
  }

  void _paintShadow(Canvas canvas, Offset center, double scale) {
    final shadowRect = Rect.fromCenter(
      center: center.translate(0, 156 * scale),
      width: 204 * scale,
      height: 34 * scale,
    );
    canvas.drawOval(
      shadowRect,
      Paint()
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 18 * scale)
        ..color = Colors.black.withValues(alpha: .54),
    );
  }

  void _paintMount(Canvas canvas) {
    final cord = Paint()
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [Color(0xFF6D4F2C), Color(0xFFE0BA74), Color(0xFF4E351F)],
      ).createShader(const Rect.fromLTWH(-4, -145, 8, 80));
    canvas.drawLine(const Offset(0, -148), const Offset(0, -96), cord);
    canvas.drawCircle(
      const Offset(0, -99),
      14,
      Paint()..color = _palette.dark,
    );
    canvas.drawCircle(
      const Offset(-3, -103),
      4.2,
      Paint()..color = _palette.highlight.withValues(alpha: .82),
    );
  }

  void _paintBell(Canvas canvas) {
    final body = Path()
      ..moveTo(-24, -92)
      ..cubicTo(-30, -62, -42, -45, -62, -24)
      ..cubicTo(-76, -8, -77, 34, -91, 78)
      ..cubicTo(-96, 94, -81, 105, -62, 108)
      ..cubicTo(-26, 115, 26, 115, 62, 108)
      ..cubicTo(81, 105, 96, 94, 91, 78)
      ..cubicTo(77, 34, 76, -8, 62, -24)
      ..cubicTo(42, -45, 30, -62, 24, -92)
      ..close();

    final palette = _palette;
    canvas.drawPath(
      body,
      Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 12)
        ..color = palette.glow.withValues(alpha: .22 + state.resonance * .18),
    );
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: palette.body,
          stops: const [0, .16, .38, .58, .8, 1],
        ).createShader(const Rect.fromLTWH(-96, -98, 192, 214)),
    );

    if (material == BellMaterial.crystal) {
      canvas.drawPath(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: .55),
      );
    }

    final highlight = Path()
      ..moveTo(-45, -60)
      ..cubicTo(-61, -13, -58, 49, -70, 82)
      ..cubicTo(-63, 86, -56, 87, -49, 86)
      ..cubicTo(-37, 32, -35, -18, -18, -67)
      ..cubicTo(-25, -72, -37, -70, -45, -60)
      ..close();
    canvas.drawPath(
      highlight,
      Paint()
        ..shader = LinearGradient(
          colors: [
            palette.highlight.withValues(alpha: .7),
            palette.highlight.withValues(alpha: .04),
          ],
        ).createShader(const Rect.fromLTWH(-75, -80, 65, 180)),
    );

    final rim = Rect.fromCenter(
      center: const Offset(0, 95),
      width: 190,
      height: 36,
    );
    canvas.drawOval(rim, Paint()..color = palette.dark);
    canvas.drawOval(
      rim.deflate(6),
      Paint()
        ..shader =
            LinearGradient(colors: palette.rim).createShader(rim.deflate(6)),
    );
    canvas.drawArc(
      rim.deflate(3),
      .08,
      math.pi - .16,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = palette.highlight.withValues(alpha: .72),
    );

    if (material == BellMaterial.porcelain) {
      canvas.drawArc(
        const Rect.fromLTWH(-52, 7, 104, 58),
        .12,
        math.pi - .24,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF8B6FD8).withValues(alpha: .62),
      );
    }
  }

  void _paintClapper(Canvas canvas, double clapperAngle) {
    canvas.save();
    canvas.translate(0, -18);
    canvas.rotate(clapperAngle);
    canvas.drawLine(
      Offset.zero,
      const Offset(0, 118),
      Paint()
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round
        ..color = _palette.dark,
    );
    const ballCenter = Offset(0, 121);
    canvas.drawCircle(
      ballCenter,
      16,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.35, -.4),
          colors: [_palette.highlight, _palette.mid, _palette.dark],
        ).createShader(Rect.fromCircle(center: ballCenter, radius: 16)),
    );
    canvas.restore();
  }

  _BellPalette get _palette => switch (material) {
        BellMaterial.brass => const _BellPalette(
            body: [
              Color(0xFF3A2412),
              Color(0xFF9A6725),
              Color(0xFFF7D98A),
              Color(0xFFB77A28),
              Color(0xFF654017),
              Color(0xFF24150B),
            ],
            rim: [Color(0xFF47301A), Color(0xFFF5D783), Color(0xFF5B3714)],
            dark: Color(0xFF3A2411),
            mid: Color(0xFFB47728),
            highlight: Color(0xFFFFE8A7),
            glow: Color(0xFFFFC85D),
          ),
        BellMaterial.crystal => const _BellPalette(
            body: [
              Color(0x55293F62),
              Color(0x994C769C),
              Color(0xCCE8FAFF),
              Color(0x887FBFD9),
              Color(0x88415F80),
              Color(0x4422324D),
            ],
            rim: [Color(0xFF527591), Color(0xFFE6FBFF), Color(0xFF45647D)],
            dark: Color(0xFF33475D),
            mid: Color(0xFF83BBD0),
            highlight: Color(0xFFF4FDFF),
            glow: Color(0xFF90E5FF),
          ),
        BellMaterial.porcelain => const _BellPalette(
            body: [
              Color(0xFF5A5570),
              Color(0xFFD5D0E7),
              Color(0xFFFFFCFF),
              Color(0xFFE1DCEF),
              Color(0xFF8E87A4),
              Color(0xFF3F3A50),
            ],
            rim: [Color(0xFF6A627C), Color(0xFFF8F2FF), Color(0xFF625873)],
            dark: Color(0xFF514A62),
            mid: Color(0xFFB9B0CB),
            highlight: Color(0xFFFFFFFF),
            glow: Color(0xFFC6A8FF),
          ),
      };

  @override
  bool shouldRepaint(BellPhysicalPainter oldDelegate) {
    return !state.approximatelyEquals(oldDelegate.state, epsilon: 1e-5) ||
        material != oldDelegate.material ||
        ambientProgress != oldDelegate.ambientProgress ||
        strikePulse != oldDelegate.strikePulse ||
        remotePulse != oldDelegate.remotePulse ||
        reduceMotion != oldDelegate.reduceMotion;
  }
}

class _BellPalette {
  const _BellPalette({
    required this.body,
    required this.rim,
    required this.dark,
    required this.mid,
    required this.highlight,
    required this.glow,
  });

  final List<Color> body;
  final List<Color> rim;
  final Color dark;
  final Color mid;
  final Color highlight;
  final Color glow;
}
