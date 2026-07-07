import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import '../../primitives/painting_canvas.dart';

/// "Constellation" — tap to place stars, idle to draw the lines.
///
/// Backed by [PaintingCanvas] (Track C). Every `onTapDown` places a
/// star (a single-point [PaintStroke]) at the touch point, and after
/// [idleBeforeConnect] of no taps the screen animates Bezier curves
/// connecting every star in tap order. Partner stars arrive via the
/// event bus — each local tap sends a `star` event, and incoming
/// `star` events render as faint remote stars.
///
/// Disposal: cancels the idle timer, partner subscription and the
/// connector animation controller before [super.dispose].
class ConstellationModeScreen extends ConsumerStatefulWidget {
  const ConstellationModeScreen({
    super.key,
    this.canvasKey,
    this.random,
    this.idleBeforeConnect = const Duration(seconds: 3),
  });

  /// Lets tests inject a [GlobalKey] so they can assert against the
  /// underlying [PaintingCanvasState].
  final GlobalKey<PaintingCanvasState>? canvasKey;

  /// Optional RNG override for deterministic widget tests.
  final math.Random? random;

  /// Idle duration with no taps before Bezier lines animate in.
  final Duration idleBeforeConnect;

  @override
  ConsumerState<ConstellationModeScreen> createState() =>
      _ConstellationModeScreenState();
}

class _ConstellationModeScreenState
    extends ConsumerState<ConstellationModeScreen>
    with SingleTickerProviderStateMixin {
  late final GlobalKey<PaintingCanvasState> _canvasKey;
  late final AnimationController _connector;
  StreamSubscription<ModeEvent>? _partnerSub;
  Timer? _idleTimer;

  final List<Offset> _localStars = [];
  Size _canvasSize = Size.zero;
  bool _showConnections = false;

  static const Color _localStarColor = Color(0xFFB39CFF);
  static const Color _remoteStarColor = Color(0xFFE07CFF);
  static const Color _connectionColor = Color(0xFF6BD3FF);

  @override
  void initState() {
    super.initState();
    _canvasKey = widget.canvasKey ?? GlobalKey<PaintingCanvasState>();
    _connector = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _partnerSub = ref.read(modeEventBusProvider).incoming
        .where((e) => e.type == 'star')
        .listen(_onPartnerStar);
  }

  void _onPartnerStar(ModeEvent event) {
    if (!mounted || _canvasSize == Size.zero) return;
    final x = (event.data['x'] as num?)?.toDouble() ?? 0.5;
    final y = (event.data['y'] as num?)?.toDouble() ?? 0.5;
    _canvasKey.currentState?.pushRemoteStroke(
      PaintStroke(
        color: _remoteStarColor.withValues(alpha: 0.45),
        strokeWidth: 10,
        points: [PaintPoint(Offset(x * _canvasSize.width, y * _canvasSize.height))],
      ),
    );
  }

  @override
  void dispose() {
    _partnerSub?.cancel();
    _idleTimer?.cancel();
    _connector.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    final position = details.localPosition;
    setState(() {
      _localStars.add(position);
      _showConnections = false;
    });
    _connector.reset();
    // Push the local star as a 1-point stroke so PaintingCanvas
    // renders it as a single dot.
    _canvasKey.currentState?.pushRemoteStroke(
      PaintStroke(
        color: _localStarColor,
        strokeWidth: 14,
        points: [PaintPoint(position)],
      ),
    );
    // Send star event to partner.
    if (_canvasSize != Size.zero) {
      ref.read(modeEventBusProvider).send(ModeEvent(
            type: 'star',
            data: {
              'x': position.dx / _canvasSize.width,
              'y': position.dy / _canvasSize.height,
            },
          ));
    }
    _resetIdleTimer();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(widget.idleBeforeConnect, _onIdleElapsed);
  }

  void _onIdleElapsed() {
    if (!mounted) return;
    if (_localStars.length < 2) return;
    setState(() => _showConnections = true);
    _connector
      ..reset()
      ..forward();
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _canvasSize =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  return RepaintBoundary(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: PaintingCanvas(
                            key: _canvasKey,
                            color: _localStarColor,
                            strokeWidth: 14,
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedBuilder(
                              animation: _connector,
                              builder: (context, _) {
                                return CustomPaint(
                                  painter: _ConstellationPainter(
                                    stars: List.unmodifiable(_localStars),
                                    progress: _showConnections
                                        ? _connector.value
                                        : 0.0,
                                    color: _connectionColor,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: _onTapDown,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  t.constellationHint,
                  textAlign: TextAlign.center,
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

class _ConstellationPainter extends CustomPainter {
  _ConstellationPainter({
    required this.stars,
    required this.progress,
    required this.color,
  });

  final List<Offset> stars;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (stars.length < 2 || progress <= 0) return;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Draw [stars.length - 1] Bezier curves, each easing in as
    // `progress` advances. Each segment owns a fraction of the
    // animation window so the lines appear sequentially.
    final segmentCount = stars.length - 1;
    final perSegment = 1.0 / segmentCount;
    for (var i = 0; i < segmentCount; i++) {
      final start = stars[i];
      final end = stars[i + 1];
      final segmentProgress =
          ((progress - i * perSegment) / perSegment).clamp(0.0, 1.0);
      if (segmentProgress <= 0) continue;
      final control = _curveControlPoint(start, end, i);
      final path = Path()..moveTo(start.dx, start.dy);
      // Quadratic Bezier sampled at `segmentProgress` so the line
      // draws toward the endpoint instead of popping in fully.
      const samples = 24;
      final lastSample = (samples * segmentProgress).round().clamp(1, samples);
      for (var s = 1; s <= lastSample; s++) {
        final t = s / samples;
        final point = _quadBezier(start, control, end, t);
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  Offset _curveControlPoint(Offset a, Offset b, int seed) {
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    // Perpendicular offset, alternating sign so successive arcs
    // bend opposite directions for visual rhythm.
    final perp = Offset(-dy, dx);
    final norm = math.sqrt(perp.dx * perp.dx + perp.dy * perp.dy);
    if (norm == 0) return mid;
    final unit = Offset(perp.dx / norm, perp.dy / norm);
    final amount = (seed.isEven ? 1 : -1) * 24.0;
    return mid + unit * amount;
  }

  Offset _quadBezier(Offset p0, Offset p1, Offset p2, double t) {
    final inv = 1 - t;
    return Offset(
      inv * inv * p0.dx + 2 * inv * t * p1.dx + t * t * p2.dx,
      inv * inv * p0.dy + 2 * inv * t * p1.dy + t * t * p2.dy,
    );
  }

  @override
  bool shouldRepaint(covariant _ConstellationPainter old) =>
      old.progress != progress ||
      old.stars.length != stars.length ||
      old.color != color;
}
