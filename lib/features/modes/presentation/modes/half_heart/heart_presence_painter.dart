import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../application/half_heart/heart_presence_models.dart';

abstract final class HeartPresenceVisualTokens {
  static const double restingGap = 38;
  static const double activeGap = 16;
  static const double auraBlur = 36;
  static const double seamWidth = 1.4;
  static const double contourWidth = 1.2;
  static const double particleRadius = 2.2;
}

/// Renders two distinct halves which physically converge into one living
/// heart. It draws only from shared design tokens and a deterministic state,
/// so both devices show the same relationship even at different frame rates.
class HeartPresencePainter extends CustomPainter {
  const HeartPresencePainter({
    required this.snapshot,
    required this.phase,
    required this.reduceMotion,
  });

  final HeartPresenceSnapshot snapshot;
  final double phase;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = math.min(size.width, size.height);
    final heartWidth = math.min(size.width * .72, shortest * .86);
    final heartHeight = heartWidth * .88;
    final center = Offset(size.width / 2, size.height * .50);
    final rect = Rect.fromCenter(
      center: center,
      width: heartWidth,
      height: heartHeight,
    );
    final heartbeat = reduceMotion || !snapshot.isMutual
        ? 0.0
        : math.pow(math.sin(phase * math.pi), 12).toDouble();
    final breath = reduceMotion ? 0.0 : math.sin(phase * math.pi * 2) * .5 + .5;
    final unity = Curves.easeOutCubic.transform(snapshot.unity);
    final scale =
        1 + heartbeat * .035 + (snapshot.isUnited ? breath * .008 : 0);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);

    if (snapshot.isMutual || snapshot.phase == HeartPresencePhase.fading) {
      _drawAura(canvas, rect, unity, heartbeat);
    }
    _drawParticles(canvas, rect, unity, breath);

    final restingGap = snapshot.localHeld || snapshot.partnerHeld
        ? HeartPresenceVisualTokens.activeGap
        : HeartPresenceVisualTokens.restingGap;
    final gap = ui.lerpDouble(restingGap, 0, unity)!;
    final localNudge = snapshot.localHeld ? 7.0 : 0.0;
    final partnerNudge = snapshot.partnerHeld ? 7.0 : 0.0;
    _drawHalf(
      canvas,
      rect,
      isLeft: true,
      translation: -gap / 2 + localNudge * (1 - unity),
      active: snapshot.localHeld,
      strength: snapshot.localStrength,
      unity: unity,
      breath: breath,
    );
    _drawHalf(
      canvas,
      rect,
      isLeft: false,
      translation: gap / 2 - partnerNudge * (1 - unity),
      active: snapshot.partnerHeld,
      strength: snapshot.partnerStrength,
      unity: unity,
      breath: 1 - breath,
    );

    if (snapshot.isUnited) {
      _drawLivingContour(canvas, rect, heartbeat, breath);
    }
    canvas.restore();
  }

  void _drawAura(Canvas canvas, Rect rect, double unity, double heartbeat) {
    final aura = Paint()
      ..color = AppColors.heart.withValues(alpha: .12 + unity * .22)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        HeartPresenceVisualTokens.auraBlur + heartbeat * 14,
      );
    canvas.drawPath(_heartPath(rect.inflate(8 + heartbeat * 8)), aura);
    final sharedAura = Paint()
      ..color = AppColors.pulse.withValues(alpha: unity * .13)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 54);
    canvas.drawOval(
      Rect.fromCenter(
        center: rect.center,
        width: rect.width * (1.05 + heartbeat * .06),
        height: rect.height * .82,
      ),
      sharedAura,
    );
  }

  void _drawHalf(
    Canvas canvas,
    Rect rect, {
    required bool isLeft,
    required double translation,
    required bool active,
    required double strength,
    required double unity,
    required double breath,
  }) {
    canvas.save();
    canvas.translate(translation, (isLeft ? -1 : 1) * (1 - unity) * 2.5);
    final clip = isLeft
        ? Rect.fromLTRB(
            rect.left - 64, rect.top - 64, rect.center.dx, rect.bottom + 64)
        : Rect.fromLTRB(
            rect.center.dx, rect.top - 64, rect.right + 64, rect.bottom + 64);
    canvas.clipRect(clip);

    final alpha = active ? .94 : .34;
    final fill = Paint()
      ..shader = ui.Gradient.radial(
        Offset(
          rect.center.dx + (isLeft ? -rect.width * .18 : rect.width * .18),
          rect.top + rect.height * (.30 + breath * .05),
        ),
        rect.width * .72,
        [
          Color.lerp(AppColors.heart, AppColors.textPrimary, .18)!
              .withValues(alpha: alpha),
          AppColors.heart.withValues(alpha: alpha * (.82 + strength * .12)),
          AppColors.pulseDeep.withValues(alpha: alpha * .78),
        ],
        const [.02, .46, 1],
      );
    canvas.drawPath(_heartPath(rect), fill);

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = HeartPresenceVisualTokens.contourWidth
      ..color = (active ? AppColors.heart : AppColors.outline)
          .withValues(alpha: active ? .62 : .82);
    canvas.drawPath(_heartPath(rect), rim);

    if (unity < .98) {
      final seam = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = HeartPresenceVisualTokens.seamWidth
        ..color = (active ? AppColors.textPrimary : AppColors.textMuted)
            .withValues(alpha: active ? .28 : .18);
      final seamPath = Path()
        ..moveTo(rect.center.dx, rect.top + rect.height * .23)
        ..cubicTo(
          rect.center.dx - (isLeft ? 5 : -5),
          rect.top + rect.height * .43,
          rect.center.dx + (isLeft ? 4 : -4),
          rect.top + rect.height * .67,
          rect.center.dx,
          rect.bottom,
        );
      canvas.drawPath(seamPath, seam);
    }
    canvas.restore();
  }

  void _drawLivingContour(
    Canvas canvas,
    Rect rect,
    double heartbeat,
    double breath,
  ) {
    final contour = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = HeartPresenceVisualTokens.contourWidth + heartbeat * 1.2
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        [
          AppColors.textPrimary.withValues(alpha: .54),
          AppColors.heart.withValues(alpha: .92),
          AppColors.pulse.withValues(alpha: .62),
        ],
        const [0, .48, 1],
      );
    canvas.drawPath(_heartPath(rect.inflate(2 + breath * 1.5)), contour);
  }

  void _drawParticles(Canvas canvas, Rect rect, double unity, double breath) {
    final count = snapshot.localHeld || snapshot.partnerHeld ? 7 : 4;
    for (var index = 0; index < count; index++) {
      final angle = index / count * math.pi * 2 + breath * .45;
      final radius = rect.width * (.43 + .05 * math.sin(index * 1.7));
      final point =
          rect.center + Offset(math.cos(angle), math.sin(angle)) * radius;
      final paint = Paint()
        ..color = (index.isEven ? AppColors.heart : AppColors.pulse).withValues(
          alpha: .08 + unity * .22,
        );
      canvas.drawCircle(
        point,
        HeartPresenceVisualTokens.particleRadius + unity * 1.2,
        paint,
      );
    }
  }

  Path _heartPath(Rect rect) {
    final x = rect.left;
    final y = rect.top;
    final w = rect.width;
    final h = rect.height;
    return Path()
      ..moveTo(x + w * .50, y + h)
      ..cubicTo(x + w * .42, y + h * .88, x, y + h * .66, x, y + h * .34)
      ..cubicTo(
          x, y + h * .10, x + w * .29, y - h * .01, x + w * .50, y + h * .25)
      ..cubicTo(
          x + w * .71, y - h * .01, x + w, y + h * .10, x + w, y + h * .34)
      ..cubicTo(
          x + w, y + h * .66, x + w * .58, y + h * .88, x + w * .50, y + h)
      ..close();
  }

  @override
  bool shouldRepaint(HeartPresencePainter oldDelegate) =>
      oldDelegate.snapshot.phase != snapshot.phase ||
      oldDelegate.snapshot.unity != snapshot.unity ||
      oldDelegate.snapshot.localHeld != snapshot.localHeld ||
      oldDelegate.snapshot.partnerHeld != snapshot.partnerHeld ||
      oldDelegate.snapshot.localStrength != snapshot.localStrength ||
      oldDelegate.snapshot.partnerStrength != snapshot.partnerStrength ||
      oldDelegate.phase != phase ||
      oldDelegate.reduceMotion != reduceMotion;
}
