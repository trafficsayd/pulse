import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../application/sketch_usage_controller.dart';
import 'mode_close_button.dart';

/// "Sketch" — LoveSketch-inspired drawing canvas. Draws a colored stroke
/// on a shared canvas; the partner sees the same line appear in real time.
///
/// The free / trial tier uses the per-day quota in [SketchUsageController];
/// each completed stroke counts as one charge. When the quota is exhausted,
/// new strokes are dropped and the user sees a snackbar.
///
/// The partner side is not yet wired to the transport — the foundation
/// renders only local strokes. Once the transport layer is real, inbound
/// strokes will be appended to the same [_SketchPainter] list.
class SketchModeScreen extends ConsumerStatefulWidget {
  const SketchModeScreen({super.key});

  @override
  ConsumerState<SketchModeScreen> createState() => _SketchModeScreenState();
}

class _SketchModeScreenState extends ConsumerState<SketchModeScreen> {
  final List<_SketchStroke> _strokes = [];
  _SketchStroke? _current;
  Color _color = _palette.first;
  double _brushSize = _brushSizes[2];

  /// Curated 14-color palette (matches the LoveSketch free-tier count).
  static const List<Color> _palette = [
    Color(0xFFFF5C7A), // pink (pulse accent)
    Color(0xFFFFFFFF), // white
    Color(0xFFFF6B5C), // coral
    Color(0xFFFFB05C), // amber
    Color(0xFFFFE16A), // yellow
    Color(0xFF7CE0A1), // mint
    Color(0xFF60A5FA), // sky
    Color(0xFF8A7CFF), // periwinkle
    Color(0xFFE07CFF), // orchid
    Color(0xFFFF7CC8), // rose
    Color(0xFF55585F), // graphite
    Color(0xFF4ADE80), // green
    Color(0xFFFBBF24), // gold
    Color(0xFF6BD3FF), // ice
  ];

  /// Five brush sizes from hairline to bold.
  static const List<double> _brushSizes = [2.0, 4.0, 7.0, 11.0, 16.0];

  void _begin(Offset position) {
    final allowed = ref
        .read(sketchUsageControllerProvider.notifier)
        .canDrawStroke();
    if (!allowed) {
      _flashLimit();
      return;
    }
    setState(() {
      _current = _SketchStroke(
        points: [position],
        color: _color,
        width: _brushSize,
      );
      _strokes.add(_current!);
    });
    HapticFeedback.selectionClick();
  }

  void _extend(Offset position) {
    final stroke = _current;
    if (stroke == null) return;
    setState(() => stroke.points.add(position));
  }

  Future<void> _end() async {
    final stroke = _current;
    if (stroke == null) return;
    _current = null;
    final ok = await ref
        .read(sketchUsageControllerProvider.notifier)
        .tryRecordStroke();
    if (!ok && mounted) _flashLimit();
  }

  void _flashLimit() {
    final t = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.sketchLimitReached)),
    );
  }

  void _clear() {
    setState(_strokes.clear);
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final remaining = ref.watch(sketchUsageControllerProvider.select(
      (_) => ref
          .read(sketchUsageControllerProvider.notifier)
          .remaining(),
    ));
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _SketchTopBar(
              remainingLabel: t.sketchStrokesRemaining(remaining),
              onClear: _strokes.isEmpty ? null : _clear,
            ),
            Expanded(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => _begin(e.localPosition),
                onPointerMove: (e) => _extend(e.localPosition),
                onPointerUp: (_) => _end(),
                onPointerCancel: (_) => _end(),
                child: CustomPaint(
                  painter: _SketchPainter(strokes: _strokes),
                  size: Size.infinite,
                ),
              ),
            ),
            _PalettePicker(
              palette: _palette,
              selected: _color,
              onPick: (c) => setState(() => _color = c),
            ),
            const SizedBox(height: 8),
            _BrushSizePicker(
              sizes: _brushSizes,
              selected: _brushSize,
              color: _color,
              onPick: (s) => setState(() => _brushSize = s),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _SketchTopBar extends StatelessWidget {
  const _SketchTopBar({
    required this.remainingLabel,
    required this.onClear,
  });

  final String remainingLabel;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const ModeCloseButton(),
          const Spacer(),
          Text(
            remainingLabel,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.delete_outline_rounded),
            color: AppColors.textSecondary,
            tooltip: t.sketchClear,
          ),
        ],
      ),
    );
  }
}

class _PalettePicker extends StatelessWidget {
  const _PalettePicker({
    required this.palette,
    required this.selected,
    required this.onPick,
  });

  final List<Color> palette;
  final Color selected;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemBuilder: (context, i) {
          final color = palette[i];
          final isSelected = color == selected;
          return GestureDetector(
            onTap: () => onPick(color),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              margin: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? AppColors.textPrimary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemCount: palette.length,
      ),
    );
  }
}

class _BrushSizePicker extends StatelessWidget {
  const _BrushSizePicker({
    required this.sizes,
    required this.selected,
    required this.color,
    required this.onPick,
  });

  final List<double> sizes;
  final double selected;
  final Color color;
  final ValueChanged<double> onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final size in sizes)
          GestureDetector(
            onTap: () => onPick(size),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: size == selected
                      ? AppColors.textPrimary
                      : AppColors.outline,
                  width: 1.4,
                ),
              ),
              child: Container(
                width: size + 2,
                height: size + 2,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SketchStroke {
  _SketchStroke({
    required this.points,
    required this.color,
    required this.width,
  });

  final List<Offset> points;
  final Color color;
  final double width;
}

class _SketchPainter extends CustomPainter {
  _SketchPainter({required this.strokes});

  final List<_SketchStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.width;
      final path = Path()
        ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (var i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }
      if (stroke.points.length == 1) {
        canvas.drawCircle(
          stroke.points.first,
          stroke.width / 2,
          Paint()..color = stroke.color,
        );
      } else {
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SketchPainter oldDelegate) =>
      oldDelegate.strokes != strokes;
}
