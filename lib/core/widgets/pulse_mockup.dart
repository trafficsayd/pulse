import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class PulseBackdrop extends StatelessWidget {
  const PulseBackdrop({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.25,
          colors: [Color(0xFF111824), AppColors.background],
          stops: [0, 0.68],
        ),
      ),
      child: CustomPaint(
        painter: const _SoftSpecksPainter(),
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: child,
        ),
      ),
    );
  }
}

class PulsePanel extends StatelessWidget {
  const PulsePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    this.borderColor,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? borderColor;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? AppColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? AppColors.outlineSoft.withValues(alpha: 0.9),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      padding: padding,
      child: child,
    );
  }
}

class PulseHeader extends StatelessWidget {
  const PulseHeader({
    super.key,
    required this.title,
    this.titleKey,
    this.leading,
    this.trailing,
    this.onBack,
  });

  final String title;
  final Key? titleKey;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          leading ??
              PulseRoundButton(
                icon: Icons.arrow_back_rounded,
                onTap: onBack ?? () => Navigator.of(context).maybePop(),
                subtle: true,
              ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              key: titleKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                height: 1,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class PulseRoundButton extends StatelessWidget {
  const PulseRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color = AppColors.textPrimary,
    this.fill,
    this.subtle = false,
    this.size = 38,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final Color? fill;
  final bool subtle;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fill ??
                (subtle
                    ? AppColors.surface.withValues(alpha: 0.35)
                    : AppColors.surface.withValues(alpha: 0.78)),
            border: Border.all(color: AppColors.outlineSoft),
          ),
          child: Icon(icon, color: color, size: size * 0.52),
        ),
      ),
    );
  }
}

class PulseGlowCircle extends StatelessWidget {
  const PulseGlowCircle({
    super.key,
    required this.size,
    required this.color,
    required this.child,
    this.fill,
    this.borderWidth = 1.6,
    this.blur = 26,
  });

  final double size;
  final Color color;
  final Widget child;
  final Color? fill;
  final double borderWidth;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill ?? color.withValues(alpha: 0.13),
        border: Border.all(
            color: color.withValues(alpha: 0.95), width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.42),
            blurRadius: blur,
            spreadRadius: 1,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class PulseSegmentedPill extends StatelessWidget {
  const PulseSegmentedPill({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.all(3),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.outlineSoft),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _SoftSpecksPainter extends CustomPainter {
  const _SoftSpecksPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 24; i++) {
      final x = ((i * 73) % 389) / 389 * size.width;
      final y = ((i * 97) % 631) / 631 * size.height;
      final a = 0.02 + (i % 5) * 0.012;
      paint.color = AppColors.pulse.withValues(alpha: a);
      canvas.drawCircle(Offset(x, y), 1 + (i % 3) * 0.6, paint);
    }

    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = AppColors.pulse.withValues(alpha: 0.055);
    final center = Offset(size.width / 2, size.height * 0.45);
    for (var i = 0; i < 5; i++) {
      canvas.drawCircle(center, 64.0 + i * 34, paint);
    }

    paint
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: [
          AppColors.pulse.withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(
          Rect.fromCircle(center: center, radius: size.shortestSide));
    canvas.drawCircle(center, math.min(size.width, size.height) * 0.48, paint);
  }

  @override
  bool shouldRepaint(_SoftSpecksPainter oldDelegate) => false;
}
