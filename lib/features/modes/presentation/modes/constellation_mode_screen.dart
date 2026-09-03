import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import '../../application/constellation/constellation_engine.dart';
import '../../application/constellation/constellation_models.dart';
import '../../application/constellation/constellation_protocol.dart';
import '../../primitives/painting_canvas.dart';
import 'constellation/constellation_sky_painter.dart';

/// Two people build one deterministic personal sky.
///
/// Every new packet carries a compact recent history. Reordered, replayed or
/// duplicated delivery therefore converges instead of creating extra stars.
class ConstellationModeScreen extends ConsumerStatefulWidget {
  const ConstellationModeScreen({
    super.key,
    this.canvasKey,
    this.random,
    this.idleBeforeConnect = const Duration(milliseconds: 2100),
    this.now,
    this.idFactory,
  });

  /// Kept as a compatibility/QA hook for existing canvas assertions.
  final GlobalKey<PaintingCanvasState>? canvasKey;
  final math.Random? random;
  final Duration idleBeforeConnect;
  final DateTime Function()? now;
  final String Function()? idFactory;

  @override
  ConsumerState<ConstellationModeScreen> createState() =>
      _ConstellationModeScreenState();
}

class _ConstellationModeScreenState
    extends ConsumerState<ConstellationModeScreen>
    with TickerProviderStateMixin {
  static const int _compatibilityStrokeLimit = 96;
  late final GlobalKey<PaintingCanvasState> _canvasKey;
  late final String _localAuthorId;
  late final ConstellationEngine _engine;
  late final AnimationController _ambient;
  late final AnimationController _reveal;
  StreamSubscription<ModeEvent>? _partnerSub;
  Timer? _idleTimer;
  Size _surfaceSize = Size.zero;
  int _fallbackId = 0;
  int _legacyReceiveTick = 0;

  int get _nowMs =>
      (widget.now?.call() ?? DateTime.now()).millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _canvasKey = widget.canvasKey ?? GlobalKey<PaintingCanvasState>();
    final entropy = widget.random ?? math.Random();
    _localAuthorId =
        'participant-${entropy.nextInt(0x7fffffff).toRadixString(16)}';
    _engine = ConstellationEngine(localAuthorId: _localAuthorId);
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 7600),
    )..repeat();
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    );
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
        .where((event) => event.type == ConstellationProtocol.eventType)
        .listen(_onPartnerEvent);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _ambient.stop();
      _ambient.value = .22;
      if (_engine.snapshot.edges.isNotEmpty) _reveal.value = 1;
    } else if (!_ambient.isAnimating) {
      _ambient.repeat();
    }
  }

  void _onPartnerEvent(ModeEvent event) {
    if (!mounted) return;
    final receivedAt = _nowMs + _legacyReceiveTick++;
    final packet = ConstellationProtocol.tryDecode(
      event,
      receivedAtMs: receivedAt,
    );
    if (packet == null) return;
    final before = _engine.snapshot.stars.map((star) => star.id).toSet();
    final changed = _engine.merge(packet.records);
    if (changed == 0) return;
    for (final star in packet.records) {
      if (before.contains(star.id) || star.authorId == _localAuthorId) continue;
      _pushCompatibilityStar(star, isLocal: false);
    }
    _restartStoryReveal();
    setState(() {});
  }

  void _onPointerDown(PointerDownEvent details) {
    if (_surfaceSize.isEmpty) return;
    if (details.localPosition.dy < 112 &&
        details.localPosition.dx > _surfaceSize.width - 76) {
      return;
    }
    final x = (details.localPosition.dx / _surfaceSize.width)
        .clamp(0.0, 1.0)
        .toDouble();
    final y = (details.localPosition.dy / _surfaceSize.height)
        .clamp(0.0, 1.0)
        .toDouble();
    _placeLocalStar(x, y);
  }

  void _placeLocalStar(double x, double y) {
    final now = _nowMs;
    final id =
        widget.idFactory?.call() ?? '$_localAuthorId-$now-${_fallbackId++}';
    final star = _engine.addLocal(
      id: id,
      x: x,
      y: y,
      authoredAtMs: now,
      energy: .68 + ((x * 17 + y * 31) % .28),
    );
    _pushCompatibilityStar(star, isLocal: true);
    _restartStoryReveal();
    setState(() {});
    unawaited(HapticFeedback.selectionClick());
    final snapshot = _engine.snapshot;
    unawaited(
      ref.read(modeEventBusProvider).send(
            ConstellationProtocol.encode(star, history: snapshot.stars),
          ),
    );
  }

  void _pushCompatibilityStar(
    ConstellationStar star, {
    required bool isLocal,
  }) {
    final point = Offset(
      star.x * _surfaceSize.width,
      star.y * _surfaceSize.height,
    );
    final compatibilityCanvas = _canvasKey.currentState;
    if (compatibilityCanvas == null) return;
    // This canvas is an invisible legacy/QA hook. Keep it bounded alongside
    // the real engine so a long constellation session cannot retain every tap.
    if (compatibilityCanvas.strokes.length >= _compatibilityStrokeLimit) {
      compatibilityCanvas.clear();
    }
    compatibilityCanvas.pushRemoteStroke(
      PaintStroke(
        color: isLocal
            ? const Color(0xFFB39CFF)
            : const Color(0xFFE07CFF).withValues(alpha: .45),
        strokeWidth: isLocal ? 14 : 10,
        points: [PaintPoint(point)],
      ),
    );
  }

  void _restartStoryReveal() {
    _idleTimer?.cancel();
    _reveal.reset();
    _idleTimer = Timer(widget.idleBeforeConnect, () {
      if (!mounted || _engine.snapshot.edges.isEmpty) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _reveal.value = 1;
      } else {
        unawaited(_reveal.forward());
      }
    });
  }

  @override
  void dispose() {
    _partnerSub?.cancel();
    _idleTimer?.cancel();
    _ambient.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final snapshot = _engine.snapshot;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Listener(
          key: const ValueKey('constellation-touch-surface'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          child: Stack(
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _surfaceSize = constraints.biggest;
                    return Semantics(
                      label: t.constellationHint,
                      value: '${snapshot.stars.length}',
                      button: true,
                      onTap: () => _placeLocalStar(.5, .52),
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: Listenable.merge([_ambient, _reveal]),
                          builder: (context, _) => CustomPaint(
                            key: ValueKey(
                                'constellation-sky-${snapshot.fingerprint}'),
                            painter: ConstellationSkyPainter(
                              snapshot: snapshot,
                              localAuthorId: _localAuthorId,
                              phase: _ambient.value,
                              revealProgress: _reveal.value,
                              reduceMotion: reduceMotion,
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                child: Offstage(
                  offstage: true,
                  child: SizedBox.square(
                    dimension: 1,
                    child: PaintingCanvas(
                      key: _canvasKey,
                      color: const Color(0xFFB39CFF),
                      strokeWidth: 14,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: _ConstellationHeader(
                  title: t.modeConstellation,
                  hint: t.constellationHint,
                  onClose: () => Navigator.of(context).maybePop(),
                  closeTooltip: t.hubExit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConstellationHeader extends StatelessWidget {
  const _ConstellationHeader({
    required this.title,
    required this.hint,
    required this.onClose,
    required this.closeTooltip,
  });

  final String title;
  final String hint;
  final VoidCallback onClose;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(27),
        border: Border.all(color: Colors.white.withValues(alpha: .075)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xE60C0C15),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: .055)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 13, 7, 13),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -.25,
                                ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        hint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.25,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: closeTooltip,
                  child: Semantics(
                    button: true,
                    label: closeTooltip,
                    child: InkResponse(
                      key: const ValueKey('constellation-close'),
                      radius: 24,
                      onTap: onClose,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: .07),
                        ),
                        child: CustomPaint(painter: _ThinClosePainter()),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThinClosePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textSecondary
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round;
    final inset = size.width * .36;
    canvas.drawLine(
      Offset(inset, inset),
      Offset(size.width - inset, size.height - inset),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - inset, inset),
      Offset(inset, size.height - inset),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
