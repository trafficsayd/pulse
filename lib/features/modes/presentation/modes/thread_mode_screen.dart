import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';

/// "Thread" — a glowing thread that connects two points. Both users drag
/// their finger; the thread follows each drag and the partner sees the
/// other end move in real time. When both hold still, the thread glows
/// brighter and pulses.
///
/// Visual: a bezier curve from the local drag point to the partner's
/// drag point, rendered with a neon glow effect.
class ThreadModeScreen extends ConsumerStatefulWidget {
  const ThreadModeScreen({super.key});

  @override
  ConsumerState<ThreadModeScreen> createState() => _ThreadModeScreenState();
}

class _ThreadModeScreenState extends ConsumerState<ThreadModeScreen>
    with SingleTickerProviderStateMixin {
  Offset? _localPoint;
  Offset? _partnerPoint;
  StreamSubscription<ModeEvent>? _partnerSub;
  late final AnimationController _glow;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _partnerSub = ref.read(modeEventBusProvider).incoming
        .where((e) => e.type == 'thread_point' || e.type == 'thread_end')
        .listen(_onPartnerEvent);
  }

  void _onPartnerEvent(ModeEvent event) {
    if (!mounted) return;
    final size = context.size;
    if (size == null) return;
    if (event.type == 'thread_point') {
      final x = (event.data['x'] as num?)?.toDouble() ?? 0.5;
      final y = (event.data['y'] as num?)?.toDouble() ?? 0.5;
      setState(() => _partnerPoint = Offset(x * size.width, y * size.height));
    } else if (event.type == 'thread_end') {
      setState(() => _partnerPoint = null);
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final size = context.size;
    setState(() => _localPoint = details.localPosition);
    if (size == null) return;
    ref.read(modeEventBusProvider).send(ModeEvent(
      type: 'thread_point',
      data: {
        'x': details.localPosition.dx / size.width,
        'y': details.localPosition.dy / size.height,
      },
    ));
  }

  void _onPanEnd() {
    setState(() => _localPoint = null);
    ref.read(modeEventBusProvider).send(const ModeEvent(type: 'thread_end'));
  }

  @override
  void dispose() {
    _partnerSub?.cancel();
    _glow.dispose();
    super.dispose();
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
                onPanUpdate: _onPanUpdate,
                onPanEnd: (_) => _onPanEnd(),
                onPanCancel: _onPanEnd,
                child: AnimatedBuilder(
                  animation: _glow,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _ThreadPainter(
                        localPoint: _localPoint,
                        partnerPoint: _partnerPoint,
                        glow: _glow.value,
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  t.modeThread,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: t.hubExit,
                color: AppColors.textSecondary,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadPainter extends CustomPainter {
  _ThreadPainter({
    required this.localPoint,
    required this.partnerPoint,
    required this.glow,
  });

  final Offset? localPoint;
  final Offset? partnerPoint;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final local = localPoint ?? Offset(size.width * 0.3, size.height * 0.7);
    final partner = partnerPoint ?? Offset(size.width * 0.7, size.height * 0.3);
    final bothActive = localPoint != null && partnerPoint != null;
    final intensity = bothActive ? (0.5 + 0.5 * glow) : 0.3;

    // Sagging bezier between the two points.
    final mid = Offset(
      (local.dx + partner.dx) / 2,
      (local.dy + partner.dy) / 2 + 60,
    );
    final path = Path()
      ..moveTo(local.dx, local.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, partner.dx, partner.dy);

    // Outer glow.
    final glowPaint = Paint()
      ..color = AppColors.pulse.withValues(alpha: 0.25 * intensity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(path, glowPaint);

    // Main thread.
    final paint = Paint()
      ..color = AppColors.pulse.withValues(alpha: 0.8 + 0.2 * glow)
      ..style = PaintingStyle.stroke
      ..strokeWidth = bothActive ? 3.0 : 2.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(path, paint);

    // Endpoints.
    for (final point in [local, partner]) {
      final p = Paint()..color = AppColors.pulse.withValues(alpha: 0.9);
      canvas.drawCircle(point, 5, p);
      canvas.drawCircle(
        point,
        10,
        Paint()
          ..color = AppColors.pulse.withValues(alpha: 0.3 * glow)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ThreadPainter old) =>
      old.localPoint != localPoint ||
      old.partnerPoint != partnerPoint ||
      old.glow != glow;
}
