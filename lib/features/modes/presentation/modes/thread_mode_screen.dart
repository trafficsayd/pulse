import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import '../../application/thread/thread_dynamics.dart';
import '../../primitives/haptic_pattern_player.dart';
import '../../primitives/primitive_providers.dart';

/// An inhabitable filament between two people: drag to pull it, release to
/// send a physical-looking wave, and see the partner's end through a jitter
/// buffer rather than raw packet positions.
class ThreadModeScreen extends ConsumerStatefulWidget {
  const ThreadModeScreen({
    super.key,
    this.hapticEngine,
    this.frameDuration = const Duration(seconds: 7),
  });

  final HapticEngine? hapticEngine;
  final Duration frameDuration;

  @override
  ConsumerState<ThreadModeScreen> createState() => _ThreadModeScreenState();
}

class _ThreadModeScreenState extends ConsumerState<ThreadModeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _clock;
  late final AnimationController _pulse;
  late final HapticPatternPlayer _haptics;
  final ThreadPhysics _physics = ThreadPhysics();
  final ThreadRemoteReconciler _remote = ThreadRemoteReconciler();
  final ThreadPacketDeduplicator _deduplicator = ThreadPacketDeduplicator();
  final List<_TouchTrace> _traces = [];

  StreamSubscription<ModeEvent>? _partnerSub;
  Timer? _reducedTickTimer;
  Size _surfaceSize = Size.zero;
  ThreadPoint? _local;
  ThreadPoint? _partner;
  ThreadPoint _localVelocity = const ThreadPoint(0, 0);
  ThreadPhysicsFrame _frame = const ThreadPhysicsFrame(
    tension: 0,
    sag: .13,
    releaseWave: 0,
    shimmerSpeed: .35,
  );
  DateTime? _lastFrameAt;
  DateTime? _lastGestureAt;
  DateTime? _lastSentAt;
  ThreadPoint? _lastGesturePoint;
  bool _localActive = false;
  bool _partnerActive = false;
  bool _pulseFromPartner = false;
  bool _reduceMotion = false;
  late final int _epoch;
  int _sequence = 0;

  @override
  void initState() {
    super.initState();
    _epoch = DateTime.now().microsecondsSinceEpoch;
    _haptics = HapticPatternPlayer(
      widget.hapticEngine ?? ref.read(hapticEngineProvider),
    );
    _clock = AnimationController(vsync: this, duration: widget.frameDuration)
      ..addListener(_tick)
      ..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
      value: 1,
    );
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
        .where((event) =>
            event.type == 'thread_point' || event.type == 'thread_end')
        .listen(_onPartnerEvent);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.maybeOf(context);
    final reduce =
        media?.disableAnimations == true || media?.accessibleNavigation == true;
    if (reduce == _reduceMotion) return;
    _reduceMotion = reduce;
    if (reduce) {
      _clock.stop();
      _reducedTickTimer ??= Timer.periodic(
        const Duration(milliseconds: 80),
        (_) => _tick(),
      );
    } else {
      _reducedTickTimer?.cancel();
      _reducedTickTimer = null;
      if (!_clock.isAnimating) _clock.repeat();
    }
  }

  int _nowUs() => DateTime.now().microsecondsSinceEpoch;

  void _tick() {
    if (!mounted) return;
    final now = DateTime.now();
    final previous = _lastFrameAt;
    _lastFrameAt = now;
    final delta = previous == null
        ? 1 / 60
        : now.difference(previous).inMicroseconds / 1000000;
    final remotePosition = _remote.positionAt(now.microsecondsSinceEpoch);
    if (remotePosition != null) _partner = remotePosition;
    if (_remote.isStaleAt(now.microsecondsSinceEpoch)) _partnerActive = false;
    final local = _local ?? const ThreadPoint(.27, .68);
    final partner = _partner ?? const ThreadPoint(.73, .34);
    _frame = _physics.update(
      local: local,
      partner: partner,
      localVelocity: _localVelocity,
      deltaSeconds: delta,
      bothActive: _localActive && _partnerActive,
    );
    for (final trace in _traces) {
      trace.age += delta;
    }
    _traces.removeWhere((trace) => trace.age > 3.2);
    setState(() {});
  }

  void _onPartnerEvent(ModeEvent event) {
    if (!mounted) return;
    if (event.type == 'thread_end') {
      _partnerActive = false;
      _remote.end();
      setState(() {});
      return;
    }
    final packet = ThreadProtocol.parse(event.data);
    if (packet == null || !_deduplicator.accept(packet)) return;
    final receivedAtUs = _nowUs();
    _partnerActive = packet.phase != 'release';
    _remote.push(ThreadRemoteSample(
      point: packet.point,
      velocity: packet.velocity,
      sentAtUs: packet.sentAtUs ?? receivedAtUs,
      receivedAtUs: receivedAtUs,
      active: _partnerActive,
    ));
    if (packet.phase == 'release') {
      _physics.replayRemoteRelease(packet.tension);
      _pulseFromPartner = true;
      _pulse.forward(from: 0);
      _addTrace(packet.point, remote: true, strength: packet.tension);
      unawaited(_haptics.play(HapticPatterns.syncEcho));
    }
    setState(() {});
  }

  ThreadPoint _normalize(Offset point) {
    if (_surfaceSize.isEmpty) return ThreadPoint.center;
    return ThreadPoint(
      point.dx / _surfaceSize.width,
      point.dy / _surfaceSize.height,
    ).clamp();
  }

  void _onPanStart(DragStartDetails details) {
    final point = _normalize(details.localPosition);
    _local = point;
    _localActive = true;
    _localVelocity = const ThreadPoint(0, 0);
    _lastGesturePoint = point;
    _lastGestureAt = DateTime.now();
    _addTrace(point, remote: false, strength: .22);
    unawaited(_haptics.play(HapticPatterns.syncTouch));
    _sendGesture('begin', point, force: true);
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final point = _normalize(details.localPosition);
    final now = DateTime.now();
    final previousPoint = _lastGesturePoint;
    final previousTime = _lastGestureAt;
    if (previousPoint != null && previousTime != null) {
      final seconds = math.max(
        .001,
        now.difference(previousTime).inMicroseconds / 1000000,
      );
      final measured = (point - previousPoint) * (1 / seconds);
      _localVelocity = ThreadPoint.lerp(_localVelocity, measured, .42);
    }
    _local = point;
    _lastGesturePoint = point;
    _lastGestureAt = now;
    _sendGesture('move', point);
    setState(() {});
  }

  void _onPanEnd() {
    final point = _local;
    if (point == null) return;
    final strength = _physics.release(
      strength: (_frame.tension + _localVelocity.magnitude * .08),
    );
    _localActive = false;
    _pulseFromPartner = false;
    _pulse.forward(from: 0);
    _addTrace(point, remote: false, strength: strength);
    _sendGesture('release', point, force: true, tension: strength);
    unawaited(_haptics.play(
      strength > .55 ? HapticPatterns.syncNear : HapticPatterns.syncTouch,
    ));
    _lastSentAt = null;
    setState(() {});
  }

  void _sendGesture(
    String phase,
    ThreadPoint point, {
    bool force = false,
    double? tension,
  }) {
    final now = DateTime.now();
    if (!force &&
        _lastSentAt != null &&
        now.difference(_lastSentAt!) < const Duration(milliseconds: 33)) {
      return;
    }
    _lastSentAt = now;
    unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
          type: 'thread_point',
          data: ThreadProtocol.gesture(
            epoch: _epoch,
            sequence: ++_sequence,
            sentAtUs: now.microsecondsSinceEpoch,
            phase: phase,
            point: point,
            velocity: _localVelocity,
            tension: tension ?? _frame.tension,
          ),
        )));
  }

  void _addTrace(
    ThreadPoint point, {
    required bool remote,
    required double strength,
  }) {
    _traces.add(_TouchTrace(
      point: point,
      remote: remote,
      strength: strength.clamp(.12, 1.0),
    ));
    if (_traces.length > 12) _traces.removeAt(0);
  }

  @override
  void dispose() {
    _partnerSub?.cancel();
    _reducedTickTimer?.cancel();
    _clock
      ..removeListener(_tick)
      ..dispose();
    _pulse.dispose();
    unawaited(_haptics.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            _surfaceSize = constraints.biggest;
            return Stack(
              children: [
                Positioned.fill(
                  child: Semantics(
                    container: true,
                    label: t.modeThread,
                    child: GestureDetector(
                      excludeFromSemantics: true,
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: (_) => _onPanEnd(),
                      onPanCancel: _onPanEnd,
                      child: AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, _) => RepaintBoundary(
                          child: CustomPaint(
                            painter: _LivingThreadPainter(
                              local: _local,
                              partner: _partner,
                              frame: _frame,
                              phase: _clock.value,
                              pulse: _pulse.value,
                              pulseFromPartner: _pulseFromPartner,
                              localActive: _localActive,
                              partnerActive: _partnerActive,
                              traces: List<_TouchTrace>.of(_traces),
                              reduceMotion: _reduceMotion,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 14,
                  left: 52,
                  right: 52,
                  child: Column(
                    children: [
                      Text(
                        t.modeThread,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .25,
                        ),
                      ),
                      const SizedBox(height: 9),
                      _TensionIndicator(value: _frame.tension),
                    ],
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
                const Positioned(
                  bottom: 28,
                  left: 0,
                  right: 0,
                  child: Center(child: _GestureGlyph()),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TouchTrace {
  _TouchTrace({
    required this.point,
    required this.remote,
    required this.strength,
  });

  final ThreadPoint point;
  final bool remote;
  final double strength;
  double age = 0;
}

class _TensionIndicator extends StatelessWidget {
  const _TensionIndicator({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) => Container(
        width: 46,
        height: 7,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .045),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white.withValues(alpha: .07)),
        ),
        alignment: Alignment.centerLeft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 4 + 36 * value,
          height: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            gradient: const LinearGradient(
              colors: [Color(0xFF8B62FF), Color(0xFFFF80B3)],
            ),
          ),
        ),
      );
}

class _GestureGlyph extends StatelessWidget {
  const _GestureGlyph();

  @override
  Widget build(BuildContext context) => Container(
        width: 58,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .045),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white.withValues(alpha: .07)),
        ),
        child: const Icon(
          Icons.swipe_rounded,
          size: 16,
          color: AppColors.textMuted,
        ),
      );
}

class _LivingThreadPainter extends CustomPainter {
  const _LivingThreadPainter({
    required this.local,
    required this.partner,
    required this.frame,
    required this.phase,
    required this.pulse,
    required this.pulseFromPartner,
    required this.localActive,
    required this.partnerActive,
    required this.traces,
    required this.reduceMotion,
  });

  final ThreadPoint? local;
  final ThreadPoint? partner;
  final ThreadPhysicsFrame frame;
  final double phase;
  final double pulse;
  final bool pulseFromPartner;
  final bool localActive;
  final bool partnerActive;
  final List<_TouchTrace> traces;
  final bool reduceMotion;

  Offset _offset(ThreadPoint point, Size size) =>
      Offset(point.x * size.width, point.y * size.height);

  @override
  void paint(Canvas canvas, Size size) {
    final localPoint = _offset(local ?? const ThreadPoint(.27, .68), size);
    final partnerPoint = _offset(partner ?? const ThreadPoint(.73, .34), size);
    _drawBackground(canvas, size, localPoint, partnerPoint);
    for (final trace in traces) {
      _drawTrace(canvas, size, trace);
    }

    final curve = _curvePoints(localPoint, partnerPoint, size);
    final path = Path()..moveTo(curve.first.dx, curve.first.dy);
    for (final point in curve.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final bounds = path.getBounds().inflate(20);
    final shader = const LinearGradient(
      colors: [Color(0xFF8D6BFF), Color(0xFFE58CFF), Color(0xFFFF82B3)],
      stops: [0, .52, 1],
    ).createShader(bounds);

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 18 - frame.tension * 6
        ..color = const Color(0xFFB66CFF).withValues(alpha: .08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5.5 - frame.tension * 1.6
        ..shader = shader
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.8),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.25 + frame.tension * .8
        ..shader = shader,
    );
    _drawFibres(canvas, curve);
    _drawImpulse(canvas, curve);
    _drawEndpoint(canvas, localPoint, false, localActive);
    _drawEndpoint(canvas, partnerPoint, true, partnerActive);
  }

  List<Offset> _curvePoints(Offset a, Offset b, Size size) {
    final values = <Offset>[];
    final phaseRadians = phase * math.pi * 2;
    final sagPixels = frame.sag * size.height;
    final delta = b - a;
    final length = math.max(1.0, delta.distance);
    final normal = Offset(-delta.dy / length, delta.dx / length);
    for (var i = 0; i <= 72; i++) {
      final t = i / 72;
      final base = Offset.lerp(a, b, t)!;
      final sag = math.sin(math.pi * t) * sagPixels;
      final living = reduceMotion
          ? 0.0
          : math.sin(t * math.pi * 5 - phaseRadians * frame.shimmerSpeed) *
              math.sin(math.pi * t) *
              (1.5 + (1 - frame.tension) * 2.8);
      final release = math.sin(t * math.pi * 3 + phaseRadians * 2.2) *
          math.sin(math.pi * t) *
          frame.releaseWave *
          13;
      values.add(base + Offset(0, sag) + normal * (living + release));
    }
    return values;
  }

  void _drawBackground(Canvas canvas, Size size, Offset a, Offset b) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -.12),
          radius: 1.05,
          colors: [Color(0xFF191126), Color(0xFF0C0913), AppColors.background],
          stops: [0, .58, 1],
        ).createShader(Offset.zero & size),
    );
    for (final entry in [
      (a, const Color(0xFF8D68FF)),
      (b, const Color(0xFFFF78AE))
    ]) {
      canvas.drawCircle(
        entry.$1,
        size.shortestSide * .34,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [entry.$2.withValues(alpha: .035), Colors.transparent],
          ).createShader(Rect.fromCircle(
            center: entry.$1,
            radius: size.shortestSide * .34,
          )),
      );
    }
  }

  void _drawFibres(Canvas canvas, List<Offset> curve) {
    final motion = reduceMotion ? 0.0 : math.sin(phase * math.pi * 2) * .45;
    for (final offset in [-1.3, 1.25]) {
      final path = Path();
      for (var i = 0; i < curve.length; i++) {
        final point = curve[i] + Offset(0, offset + motion * offset);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .45
          ..color = Colors.white.withValues(alpha: .32),
      );
    }
  }

  void _drawImpulse(Canvas canvas, List<Offset> curve) {
    if (pulse >= 1 || curve.isEmpty) return;
    final eased = Curves.easeInOutCubic.transform(pulse);
    final travel = pulseFromPartner ? 1 - eased : eased;
    final index = (travel * (curve.length - 1)).round();
    final point = curve[index.clamp(0, curve.length - 1)];
    canvas.drawCircle(
      point,
      4 + math.sin(math.pi * pulse) * 7,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = const Color(0xFFFFD7F0)
            .withValues(alpha: math.sin(math.pi * pulse) * .72)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
  }

  void _drawEndpoint(Canvas canvas, Offset point, bool remote, bool active) {
    final color = remote ? const Color(0xFFFF83B5) : const Color(0xFF9B75FF);
    final breath = reduceMotion ? 0.0 : math.sin(phase * math.pi * 2) * 1.4;
    canvas.drawCircle(
      point,
      23 + breath,
      Paint()
        ..color = color.withValues(alpha: active ? .11 : .045)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      point,
      active ? 7.5 : 5.5,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.35, -.38),
          colors: [Colors.white, color, color.withValues(alpha: .35)],
        ).createShader(Rect.fromCircle(center: point, radius: 8)),
    );
    canvas.drawCircle(
      point,
      13 + frame.tension * 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .75
        ..color = color.withValues(alpha: active ? .42 : .14),
    );
  }

  void _drawTrace(Canvas canvas, Size size, _TouchTrace trace) {
    final life = (1 - trace.age / 3.2).clamp(0.0, 1.0);
    final point = _offset(trace.point, size);
    final color =
        trace.remote ? const Color(0xFFFF8DBB) : const Color(0xFFAA86FF);
    canvas.drawCircle(
      point,
      10 + trace.age * 13 * trace.strength,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ui.lerpDouble(.4, 1.5, life)!
        ..color = color.withValues(alpha: life * .24),
    );
  }

  @override
  bool shouldRepaint(covariant _LivingThreadPainter old) =>
      old.local != local ||
      old.partner != partner ||
      old.frame != frame ||
      old.phase != phase ||
      old.pulse != pulse ||
      old.pulseFromPartner != pulseFromPartner ||
      old.localActive != localActive ||
      old.partnerActive != partnerActive ||
      old.traces != traces ||
      old.reduceMotion != reduceMotion;
}
