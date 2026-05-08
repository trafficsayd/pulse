import 'dart:ui' show BlurStyle, ImageFilter, MaskFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';

enum _BrushEffect { clean, neon, glow, watercolor, sparkles }

class RaySketchModeScreen extends StatefulWidget {
  const RaySketchModeScreen({super.key});

  @override
  State<RaySketchModeScreen> createState() => _RaySketchModeScreenState();
}

class _RaySketchModeScreenState extends State<RaySketchModeScreen> {
  static const List<Color> _palette = [
    Color(0xFFFFFFFF),
    Color(0xFF9747FF),
    Color(0xFFFF4D8B),
    Color(0xFFFFB05C),
    Color(0xFFFFD86A),
    Color(0xFF4ADE80),
    Color(0xFF7CE0A1),
    Color(0xFF6BD3FF),
    Color(0xFF60A5FA),
    Color(0xFFB39CFF),
    Color(0xFFE07CFF),
    Color(0xFFFF7CC8),
    Color(0xFF94A3B8),
    Color(0xFF111827),
  ];
  static const List<double> _brushSizes = [3, 6, 10, 16, 24];

  List<_Stroke> _strokes = [];
  _Stroke? _activeStroke;
  Color _selectedColor = _palette[1];
  double _selectedWidth = _brushSizes[2];
  _BrushEffect _selectedEffect = _BrushEffect.neon;
  bool _liveMode = true;
  int _revision = 0;

  void _startStroke(DragStartDetails details) {
    final stroke = _Stroke(
      points: [details.localPosition],
      color: _selectedColor,
      width: _selectedWidth,
      effect: _selectedEffect,
    );
    setState(() {
      _activeStroke = stroke;
      _strokes = [..._strokes, stroke];
      _revision++;
    });
    HapticFeedback.selectionClick();
  }

  void _extendStroke(DragUpdateDetails details) {
    final active = _activeStroke;
    if (active == null) return;
    final updated = active.copyWith(
      points: [...active.points, details.localPosition],
    );
    setState(() {
      _activeStroke = updated;
      _strokes = [
        for (final stroke in _strokes)
          if (identical(stroke, active)) updated else stroke,
      ];
      _revision++;
    });
  }

  void _endStroke() {
    if (_activeStroke == null) return;
    setState(() => _activeStroke = null);
    HapticFeedback.lightImpact();
  }

  void _clear() {
    setState(() {
      _strokes = [];
      _activeStroke = null;
      _revision++;
    });
    HapticFeedback.mediumImpact();
  }

  void _sendPostcard() {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.sketchSendReady)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: _startStroke,
                onPanUpdate: _extendStroke,
                onPanEnd: (_) => _endStroke(),
                onPanCancel: _endStroke,
                child: CustomPaint(
                  painter: _SketchPainter(
                    strokes: _strokes,
                    revision: _revision,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                onPressed: () => context.go(Routes.hub),
                icon: const Icon(Icons.arrow_back_rounded),
                color: AppColors.textPrimary,
                tooltip: t.hubExit,
              ),
            ),
            Positioned(
              top: 16,
              left: 72,
              right: 72,
              child: Column(
                children: [
                  Text(
                    t.modeRay,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.sketchHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _SketchToolbar(
                palette: _palette,
                brushSizes: _brushSizes,
                selectedColor: _selectedColor,
                selectedWidth: _selectedWidth,
                selectedEffect: _selectedEffect,
                liveMode: _liveMode,
                onColorSelected: (color) {
                  setState(() => _selectedColor = color);
                  HapticFeedback.selectionClick();
                },
                onWidthSelected: (width) {
                  setState(() => _selectedWidth = width);
                  HapticFeedback.selectionClick();
                },
                onEffectSelected: (effect) {
                  setState(() => _selectedEffect = effect);
                  HapticFeedback.selectionClick();
                },
                onModeChanged: (live) {
                  setState(() => _liveMode = live);
                  HapticFeedback.selectionClick();
                },
                onClear: _clear,
                onSend: _sendPostcard,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SketchToolbar extends StatelessWidget {
  const _SketchToolbar({
    required this.palette,
    required this.brushSizes,
    required this.selectedColor,
    required this.selectedWidth,
    required this.selectedEffect,
    required this.liveMode,
    required this.onColorSelected,
    required this.onWidthSelected,
    required this.onEffectSelected,
    required this.onModeChanged,
    required this.onClear,
    required this.onSend,
  });

  final List<Color> palette;
  final List<double> brushSizes;
  final Color selectedColor;
  final double selectedWidth;
  final _BrushEffect selectedEffect;
  final bool liveMode;
  final ValueChanged<Color> onColorSelected;
  final ValueChanged<double> onWidthSelected;
  final ValueChanged<_BrushEffect> onEffectSelected;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onClear;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.outlineSoft),
            boxShadow: [
              BoxShadow(
                color: AppColors.pulse.withValues(alpha: 0.16),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _ModeChip(
                    label: t.sketchLive,
                    selected: liveMode,
                    onTap: () => onModeChanged(true),
                  ),
                  const SizedBox(width: 8),
                  _ModeChip(
                    label: t.sketchCard,
                    selected: !liveMode,
                    onTap: () => onModeChanged(false),
                  ),
                  const Spacer(),
                  _IconAction(
                    icon: Icons.delete_outline_rounded,
                    label: t.sketchClear,
                    onTap: onClear,
                  ),
                  const SizedBox(width: 8),
                  _IconAction(
                    icon: liveMode ? Icons.sync_rounded : Icons.send_rounded,
                    label: t.sketchSend,
                    onTap: onSend,
                    highlighted: true,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final color in palette)
                    _ColorDot(
                      color: color,
                      selected: color == selectedColor,
                      onTap: () => onColorSelected(color),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final width in brushSizes) ...[
                      _BrushSizeDot(
                        width: width,
                        selected: width == selectedWidth,
                        onTap: () => onWidthSelected(width),
                      ),
                      const SizedBox(width: 10),
                    ],
                    const SizedBox(width: 16),
                    for (final effect in _BrushEffect.values) ...[
                      _EffectButton(
                        effect: effect,
                        label: _effectLabel(t, effect),
                        selected: effect == selectedEffect,
                        onTap: () => onEffectSelected(effect),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _effectLabel(AppLocalizations t, _BrushEffect effect) =>
      switch (effect) {
        _BrushEffect.clean => t.sketchEffectClean,
        _BrushEffect.neon => t.sketchEffectNeon,
        _BrushEffect.glow => t.sketchEffectGlow,
        _BrushEffect.watercolor => t.sketchEffectWatercolor,
        _BrushEffect.sparkles => t.sketchEffectSparkles,
      };
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.pulse.withValues(alpha: 0.22)
              : AppColors.background.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.pulse : AppColors.outline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: highlighted
                ? const LinearGradient(
                    colors: [AppColors.pulse, AppColors.heart],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: highlighted
                ? null
                : AppColors.background.withValues(alpha: 0.52),
            border: highlighted ? null : Border.all(color: AppColors.outline),
          ),
          child: Icon(
            icon,
            color: highlighted ? Colors.white : AppColors.textSecondary,
            size: 19,
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 28,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.pulse : AppColors.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: color == const Color(0xFF111827)
                ? Border.all(color: AppColors.textMuted)
                : null,
          ),
        ),
      ),
    );
  }
}

class _BrushSizeDot extends StatelessWidget {
  const _BrushSizeDot({
    required this.width,
    required this.selected,
    required this.onTap,
  });

  final double width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected
              ? AppColors.pulse.withValues(alpha: 0.2)
              : Colors.transparent,
          border: selected ? Border.all(color: AppColors.pulse) : null,
        ),
        alignment: Alignment.center,
        child: Container(
          width: width,
          height: width,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _EffectButton extends StatelessWidget {
  const _EffectButton({
    required this.effect,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final _BrushEffect effect;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected
                ? AppColors.pulse.withValues(alpha: 0.2)
                : AppColors.background.withValues(alpha: 0.38),
            border: Border.all(
              color: selected ? AppColors.pulse : AppColors.outline,
            ),
          ),
          child: Icon(
            _iconFor(effect),
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            size: 16,
          ),
        ),
      ),
    );
  }

  IconData _iconFor(_BrushEffect effect) => switch (effect) {
        _BrushEffect.clean => Icons.brush_rounded,
        _BrushEffect.neon => Icons.bolt_rounded,
        _BrushEffect.glow => Icons.blur_on_rounded,
        _BrushEffect.watercolor => Icons.water_drop_rounded,
        _BrushEffect.sparkles => Icons.auto_awesome_rounded,
      };
}

class _SketchPainter extends CustomPainter {
  const _SketchPainter({required this.strokes, required this.revision});

  final List<_Stroke> strokes;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }
  }

  void _paintBackground(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 0; i < 5; i++) {
      ringPaint.color = AppColors.pulse.withValues(alpha: 0.10 - i * 0.012);
      canvas.drawCircle(center, 56 + i * 44, ringPaint);
    }
  }

  void _drawStroke(Canvas canvas, _Stroke stroke) {
    if (stroke.points.isEmpty) return;
    if (stroke.points.length == 1) {
      final paint = _basePaint(stroke);
      canvas.drawCircle(stroke.points.first, stroke.width / 2, paint);
      return;
    }

    final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
    for (final point in stroke.points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }

    switch (stroke.effect) {
      case _BrushEffect.clean:
        canvas.drawPath(path, _basePaint(stroke));
      case _BrushEffect.neon:
        canvas.drawPath(path, _glowPaint(stroke, 4.2, 0.18));
        canvas.drawPath(path, _glowPaint(stroke, 2.3, 0.30));
        canvas.drawPath(path, _basePaint(stroke));
      case _BrushEffect.glow:
        canvas.drawPath(path, _glowPaint(stroke, 3.0, 0.22));
        canvas.drawPath(path, _basePaint(stroke));
      case _BrushEffect.watercolor:
        canvas.drawPath(path, _glowPaint(stroke, 2.8, 0.12));
        canvas.drawPath(path, _glowPaint(stroke, 1.6, 0.24));
      case _BrushEffect.sparkles:
        canvas.drawPath(path, _basePaint(stroke));
        _drawSparkles(canvas, stroke);
    }
  }

  Paint _basePaint(_Stroke stroke) {
    return Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = stroke.width;
  }

  Paint _glowPaint(_Stroke stroke, double multiplier, double alpha) {
    return Paint()
      ..color = stroke.color.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = stroke.width * multiplier
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke.width * 0.8);
  }

  void _drawSparkles(Canvas canvas, _Stroke stroke) {
    final paint = Paint()..color = stroke.color.withValues(alpha: 0.82);
    for (var i = 0; i < stroke.points.length; i += 8) {
      final point = stroke.points[i];
      final radius = 1.8 + (i % 3);
      canvas.drawCircle(point + Offset(radius * 2, -radius * 2), radius, paint);
      canvas.drawCircle(
          point + Offset(-radius * 2.4, radius), radius * 0.64, paint);
    }
  }

  @override
  bool shouldRepaint(_SketchPainter oldDelegate) {
    return oldDelegate.revision != revision || oldDelegate.strokes != strokes;
  }
}

class _Stroke {
  const _Stroke({
    required this.points,
    required this.color,
    required this.width,
    required this.effect,
  });

  final List<Offset> points;
  final Color color;
  final double width;
  final _BrushEffect effect;

  _Stroke copyWith({required List<Offset> points}) {
    return _Stroke(
      points: points,
      color: color,
      width: width,
      effect: effect,
    );
  }
}
