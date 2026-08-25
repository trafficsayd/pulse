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
  Offset? _partnerPointNormalized;
  StreamSubscription<ModeEvent>? _partnerSub;
  late final AnimationController _glow;
  DateTime? _lastSentAt;
  Timer? _partnerExpiry;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
        .where((e) => e.type == 'thread_point' || e.type == 'thread_end')
        .listen(_onPartnerEvent);
  }

  void _onPartnerEvent(ModeEvent event) {
    if (!mounted) return;
    if (event.type == 'thread_point') {
      final x = (event.data['x'] as num?)?.toDouble() ?? 0.5;
      final y = (event.data['y'] as num?)?.toDouble() ?? 0.5;
      setState(() => _partnerPointNormalized = Offset(x, y));
      _partnerExpiry?.cancel();
      _partnerExpiry = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _partnerPointNormalized = null);
      });
    } else if (event.type == 'thread_end') {
      _partnerExpiry?.cancel();
      setState(() => _partnerPointNormalized = null);
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _updateLocalPoint(details.localPosition);
  }

  void _updateLocalPoint(Offset position) {
    final size = context.size;
    setState(() => _localPoint = position);
    if (size == null) return;
    final now = DateTime.now();
    if (_lastSentAt != null &&
        now.difference(_lastSentAt!) < const Duration(milliseconds: 50)) {
      return;
    }
    _lastSentAt = now;
    ref.read(modeEventBusProvider).send(ModeEvent(
          type: 'thread_point',
          data: {
            'x': position.dx / size.width,
            'y': position.dy / size.height,
          },
        ));
  }

  void _onPanEnd() {
    setState(() => _localPoint = null);
    _lastSentAt = null;
    ref.read(modeEventBusProvider).send(const ModeEvent(type: 'thread_end'));
  }

  @override
  void dispose() {
    _partnerSub?.cancel();
    _partnerExpiry?.cancel();
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
                onPanStart: (details) =>
                    _updateLocalPoint(details.localPosition),
                onPanUpdate: _onPanUpdate,
                onPanEnd: (_) => _onPanEnd(),
                onPanCancel: _onPanEnd,
                child: AnimatedBuilder(
                  animation: _glow,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _ThreadPainter(
                        localPoint: _localPoint,
                        partnerPointNormalized: _partnerPointNormalized,
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
    required this.partnerPointNormalized,
    required this.glow,
  });

  final Offset? localPoint;
  final Offset? partnerPointNormalized;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final local = localPoint ?? Offset(size.width * 0.3, size.height * 0.7);
    final partner = partnerPointNormalized == null
        ? Offset(size.width * 0.7, size.height * 0.3)
        : Offset(
            partnerPointNormalized!.dx * size.width,
            partnerPointNormalized!.dy * size.height,
          );
    final bothActive = localPoint != null && partnerPointNormalized != null;
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
      old.partnerPointNormalized != partnerPointNormalized ||
      old.glow != glow;
}
