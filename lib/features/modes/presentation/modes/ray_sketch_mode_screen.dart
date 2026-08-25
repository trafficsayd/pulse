import 'dart:async';
import 'dart:ui' show BlurStyle, ImageFilter, MaskFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/pulse_mockup.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';

enum _BrushEffect { clean, neon, glow, watercolor, sparkles }

class RaySketchModeScreen extends ConsumerStatefulWidget {
  const RaySketchModeScreen({super.key});

  @override
  ConsumerState<RaySketchModeScreen> createState() =>
      _RaySketchModeScreenState();
}

class _RaySketchModeScreenState extends ConsumerState<RaySketchModeScreen> {
  StreamSubscription<ModeEvent>? _partnerSub;
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
  static const List<Color> _canvasPalette = [
    Color(0xFF120D1D),
    Color(0xFF24113D),
    Color(0xFF101B35),
    Color(0xFF321827),
    Color(0xFFF3ECFF),
  ];

  List<_Stroke> _strokes = [];
  _Stroke? _activeStroke;
  _Stroke? _partnerStroke;
  static const Color _partnerColor = Color(0xFF60A5FA);
  Color _selectedColor = _palette[1];
  double _selectedWidth = _brushSizes[2];
  _BrushEffect _selectedEffect = _BrushEffect.neon;
  Color _canvasColor = _canvasPalette.first;
  bool _liveMode = true;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
        .where((e) => {
              'ray_point',
              'ray_end',
              'ray_clear',
              'ray_canvas',
              'ray_card',
            }.contains(e.type))
        .listen(_onPartnerEvent);
  }

  void _onPartnerEvent(ModeEvent event) {
    if (!mounted) return;
    if (event.type == 'ray_point') {
      // Render the partner's drawing point as a live overlay so both
      // screens mirror each other in real time.
      final x = (event.data['x'] as num?)?.toDouble() ?? 0.5;
      final y = (event.data['y'] as num?)?.toDouble() ?? 0.5;
      final size = context.size;
      if (size == null) return;
      final color = Color(
        (event.data['color'] as num?)?.toInt() ?? _partnerColor.toARGB32(),
      );
      final width =
          ((event.data['width'] as num?)?.toDouble() ?? 10).clamp(1.0, 32.0);
      final effectIndex = (event.data['effect'] as num?)?.toInt() ?? 1;
      final effect =
          effectIndex >= 0 && effectIndex < _BrushEffect.values.length
              ? _BrushEffect.values[effectIndex]
              : _BrushEffect.neon;
      setState(() {
        if (_partnerStroke == null) {
          _partnerStroke = _Stroke(
            points: [Offset(x * size.width, y * size.height)],
            color: color,
            width: width,
            effect: effect,
          );
        } else {
          _partnerStroke = _partnerStroke!.copyWith(
            points: [
              ..._partnerStroke!.points,
              Offset(x * size.width, y * size.height),
            ],
          );
        }
        _revision++;
      });
    } else if (event.type == 'ray_end') {
      final finished = _partnerStroke;
      setState(() {
        if (finished != null) _strokes = [..._strokes, finished];
        _partnerStroke = null;
        _revision++;
      });
    } else if (event.type == 'ray_clear') {
      setState(() {
        _strokes = [];
        _partnerStroke = null;
        _revision++;
      });
    } else if (event.type == 'ray_canvas') {
      final value = (event.data['color'] as num?)?.toInt();
      if (value != null) setState(() => _canvasColor = Color(value));
    } else if (event.type == 'ray_card') {
      _applyPartnerCard(event);
    }
  }

  void _applyPartnerCard(ModeEvent event) {
    final size = context.size;
    final rawStrokes = event.data['strokes'];
    if (size == null || rawStrokes is! List) return;
    final received = <_Stroke>[];
    for (final raw in rawStrokes.take(16)) {
      if (raw is! Map) continue;
      final rawPoints = raw['points'];
      if (rawPoints is! List) continue;
      final points = <Offset>[];
      for (final rawPoint in rawPoints.take(80)) {
        if (rawPoint is List && rawPoint.length >= 2) {
          final x = (rawPoint[0] as num?)?.toDouble();
          final y = (rawPoint[1] as num?)?.toDouble();
          if (x != null && y != null) {
            points.add(Offset(x * size.width, y * size.height));
          }
        }
      }
      if (points.isEmpty) continue;
      final effectIndex = (raw['effect'] as num?)?.toInt() ?? 1;
      received.add(_Stroke(
        points: points,
        color:
            Color((raw['color'] as num?)?.toInt() ?? _partnerColor.toARGB32()),
        width: ((raw['width'] as num?)?.toDouble() ?? 10).clamp(1, 32),
        effect: effectIndex >= 0 && effectIndex < _BrushEffect.values.length
            ? _BrushEffect.values[effectIndex]
            : _BrushEffect.neon,
      ));
    }
    setState(() {
      _strokes = received;
      _partnerStroke = null;
      final canvas = (event.data['canvas'] as num?)?.toInt();
      if (canvas != null) _canvasColor = Color(canvas);
      _revision++;
    });
  }

  @override
  void dispose() {
    _partnerSub?.cancel();
    super.dispose();
  }

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
    if (_liveMode) _sendPoint(details.localPosition);
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
    // Send drawing point to partner.
    if (_liveMode) _sendPoint(details.localPosition);
  }

  void _sendPoint(Offset point) {
    final size = context.size;
    if (size == null) return;
    unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
          type: 'ray_point',
          data: {
            'x': point.dx / size.width,
            'y': point.dy / size.height,
            'color': _selectedColor.toARGB32(),
            'width': _selectedWidth,
            'effect': _selectedEffect.index,
          },
        )));
  }

  void _endStroke() {
    if (_activeStroke == null) return;
    setState(() => _activeStroke = null);
    HapticFeedback.lightImpact();
    if (_liveMode) {
      ref.read(modeEventBusProvider).send(const ModeEvent(type: 'ray_end'));
    }
  }

  void _clear() {
    setState(() {
      _strokes = [];
      _activeStroke = null;
      _revision++;
    });
    HapticFeedback.mediumImpact();
    unawaited(
      ref.read(modeEventBusProvider).send(const ModeEvent(type: 'ray_clear')),
    );
  }

  Future<void> _sendPostcard() async {
    final size = context.size;
    if (size == null) return;
    final encoded = _strokes.take(16).map((stroke) {
      final step = (stroke.points.length / 80).ceil().clamp(1, 1000);
      final points = <List<double>>[];
      for (var i = 0; i < stroke.points.length; i += step) {
        final point = stroke.points[i];
        points.add([point.dx / size.width, point.dy / size.height]);
      }
      return {
        'color': stroke.color.toARGB32(),
        'width': stroke.width,
        'effect': stroke.effect.index,
        'points': points,
      };
    }).toList(growable: false);
    await ref.read(modeEventBusProvider).send(ModeEvent(
          type: 'ray_card',
          data: {'canvas': _canvasColor.toARGB32(), 'strokes': encoded},
        ));
    if (!mounted) return;
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
      body: Stack(
        children: [
          const Positioned.fill(child: PulseBackdrop(child: SizedBox())),
          SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    color: _canvasColor,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _startStroke,
                      onPanUpdate: _extendStroke,
                      onPanEnd: (_) => _endStroke(),
                      onPanCancel: _endStroke,
                      child: CustomPaint(
                        painter: _SketchPainter(
                          strokes: _strokes,
                          partnerStroke: _partnerStroke,
                          revision: _revision,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 20,
                  right: 20,
                  child: PulseHeader(
                    title: t.modeRay,
                    leading: PulseRoundButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => context.go(Routes.hub),
                      subtle: true,
                    ),
                  ),
                ),
                Positioned(
                  top: 70,
                  left: 28,
                  right: 28,
                  child: PulsePanel(
                    radius: 22,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Text(
                      t.sketchHint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: _SketchToolbar(
                    palette: _palette,
                    canvasPalette: _canvasPalette,
                    brushSizes: _brushSizes,
                    selectedColor: _selectedColor,
                    selectedWidth: _selectedWidth,
                    selectedEffect: _selectedEffect,
                    selectedCanvasColor: _canvasColor,
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
                    onCanvasSelected: (color) {
                      setState(() => _canvasColor = color);
                      HapticFeedback.selectionClick();
                      unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
                            type: 'ray_canvas',
                            data: {'color': color.toARGB32()},
                          )));
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
        ],
      ),
    );
  }
}

class _SketchToolbar extends StatelessWidget {
  const _SketchToolbar({
    required this.palette,
    required this.canvasPalette,
    required this.brushSizes,
    required this.selectedColor,
    required this.selectedWidth,
    required this.selectedEffect,
    required this.selectedCanvasColor,
    required this.liveMode,
    required this.onColorSelected,
    required this.onWidthSelected,
    required this.onEffectSelected,
    required this.onCanvasSelected,
    required this.onModeChanged,
    required this.onClear,
    required this.onSend,
  });

  final List<Color> palette;
  final List<Color> canvasPalette;
  final List<double> brushSizes;
  final Color selectedColor;
  final double selectedWidth;
  final _BrushEffect selectedEffect;
  final Color selectedCanvasColor;
  final bool liveMode;
  final ValueChanged<Color> onColorSelected;
  final ValueChanged<double> onWidthSelected;
  final ValueChanged<_BrushEffect> onEffectSelected;
  final ValueChanged<Color> onCanvasSelected;
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
              Row(
                children: [
                  Text(
                    t.sketchCanvas,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  for (final color in canvasPalette) ...[
                    _ColorDot(
                      color: color,
                      selected: color == selectedCanvasColor,
                      onTap: () => onCanvasSelected(color),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final width in brushSizes)
                    _BrushSizeDot(
                      width: width,
                      selected: width == selectedWidth,
                      onTap: () => onWidthSelected(width),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final effect in _BrushEffect.values)
                    _EffectButton(
                      effect: effect,
                      label: _effectLabel(t, effect),
                      selected: effect == selectedEffect,
                      onTap: () => onEffectSelected(effect),
                    ),
                ],
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
  const _SketchPainter({
    required this.strokes,
    required this.revision,
    this.partnerStroke,
  });

  final List<_Stroke> strokes;
  final _Stroke? partnerStroke;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }
    if (partnerStroke != null) {
      _drawStroke(canvas, partnerStroke!);
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
    return oldDelegate.revision != revision ||
        oldDelegate.strokes != strokes ||
        oldDelegate.partnerStroke != partnerStroke;
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _Stroke &&
          other.color == color &&
          other.width == width &&
          other.effect == effect &&
          _listEquals(other.points, points));

  @override
  int get hashCode => Object.hash(color, width, effect, points.length);

  // Deep list equality for [Offset] (which has no default ==).
  static bool _listEquals(List<Offset> a, List<Offset> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
