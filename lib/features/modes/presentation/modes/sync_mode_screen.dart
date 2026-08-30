import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import '../../application/sync_dynamics.dart';
import '../../primitives/haptic_pattern_player.dart';
import '../../primitives/primitive_providers.dart';

/// "Shared Pulse" — two people gradually converge on one tactile rhythm.
/// Timing is compensated with a lightweight four-timestamp clock exchange;
/// no audio, sensor data or personal information is sent.
class SyncModeScreen extends ConsumerStatefulWidget {
  const SyncModeScreen({
    super.key,
    this.hapticEngine,
    this.guideBeatDuration = const Duration(milliseconds: 1600),
  });

  final HapticEngine? hapticEngine;
  final Duration guideBeatDuration;

  @override
  ConsumerState<SyncModeScreen> createState() => _SyncModeScreenState();
}

class _SyncModeScreenState extends ConsumerState<SyncModeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _ambient;
  late final AnimationController _beat;
  late final AnimationController _localTap;
  late final AnimationController _partnerTap;
  late final AnimationController _progressAnimation;
  late final HapticPatternPlayer _player;
  final SyncClockEstimator _clock = SyncClockEstimator();
  final SyncProgressTracker _progress = SyncProgressTracker();

  StreamSubscription<ModeEvent>? _partnerSub;
  Timer? _beatTimer;
  Timer? _pingTimer;
  Timer? _partnerHoldTimer;
  int _pingSequence = 0;
  int _tapSequence = 0;
  final Map<int, int> _pendingPings = {};
  int? _localTapUs;
  int? _partnerTapLocalUs;
  int? _localTapId;
  int? _partnerTapId;
  String? _lastScoredPair;
  bool _localHolding = false;
  bool _partnerHolding = false;
  bool _completed = false;
  double _progressFrom = 0;
  double _progressTo = 0;
  DateTime? _lastInteractionAt;

  @override
  void initState() {
    super.initState();
    _player = HapticPatternPlayer(
      widget.hapticEngine ?? ref.read(hapticEngineProvider),
    );
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
    _beat = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _localTap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
      value: 1,
    );
    _partnerTap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
      value: 1,
    );
    _progressAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
        .where((event) => event.type.startsWith('sync_'))
        .listen(_onPartnerEvent);
    _scheduleNextBeat();
    _sendPing();
    _pingTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _sendPing(),
    );
  }

  int _nowUs() => DateTime.now().microsecondsSinceEpoch;

  void _onPartnerEvent(ModeEvent event) {
    switch (event.type) {
      case 'sync_ping':
        _replyToPing(event);
        break;
      case 'sync_pong':
        _receivePong(event);
        break;
      case 'sync_tap':
        _receiveTap(event);
        break;
      case 'sync_state':
        _receiveState(event);
        break;
      case 'sync_hold':
        _receiveHold(event);
        break;
    }
  }

  void _sendPing() {
    final id = ++_pingSequence;
    final sentAtUs = _nowUs();
    _pendingPings[id] = sentAtUs;
    if (_pendingPings.length > 8) {
      _pendingPings.remove(_pendingPings.keys.first);
    }
    unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
          type: 'sync_ping',
          data: {'id': id, 'sentAtUs': sentAtUs},
        )));
  }

  void _replyToPing(ModeEvent event) {
    final id = (event.data['id'] as num?)?.toInt();
    final localSentAtUs = (event.data['sentAtUs'] as num?)?.toInt();
    if (id == null || localSentAtUs == null) return;
    final receivedAtUs = _nowUs();
    final sentAtUs = _nowUs();
    unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
          type: 'sync_pong',
          data: {
            'id': id,
            'localSentAtUs': localSentAtUs,
            'partnerReceivedAtUs': receivedAtUs,
            'partnerSentAtUs': sentAtUs,
          },
        )));
  }

  void _receivePong(ModeEvent event) {
    final id = (event.data['id'] as num?)?.toInt();
    if (id == null) return;
    final localSentAtUs = _pendingPings.remove(id) ??
        (event.data['localSentAtUs'] as num?)?.toInt();
    final partnerReceivedAtUs =
        (event.data['partnerReceivedAtUs'] as num?)?.toInt();
    final partnerSentAtUs = (event.data['partnerSentAtUs'] as num?)?.toInt();
    if (localSentAtUs == null ||
        partnerReceivedAtUs == null ||
        partnerSentAtUs == null) {
      return;
    }
    _clock.observeExchange(
      localSentUs: localSentAtUs,
      partnerReceivedUs: partnerReceivedAtUs,
      partnerSentUs: partnerSentAtUs,
      localReceivedUs: _nowUs(),
    );
    _beatTimer?.cancel();
    _scheduleNextBeat();
  }

  Future<void> _onTap() async {
    final nowUs = _nowUs();
    final tapId = ++_tapSequence;
    _lastInteractionAt = DateTime.now();
    _localTapUs = nowUs;
    _localTapId = tapId;
    _localTap.forward(from: 0);
    setState(() {});
    HapticFeedback.lightImpact();
    unawaited(_player.play(HapticPatterns.syncTouch));
    final matched = _scoreCurrentPair();
    await ref.read(modeEventBusProvider).send(ModeEvent(
          type: 'sync_tap',
          data: {
            'id': tapId,
            'sentAtUs': nowUs,
            'progress': _progress.progress,
          },
        ));
    if (!matched && mounted) setState(() {});
  }

  void _receiveTap(ModeEvent event) {
    if (!mounted) return;
    final receivedAtUs = _nowUs();
    final partnerSentAtUs = (event.data['sentAtUs'] as num?)?.toInt();
    final partnerId = (event.data['id'] as num?)?.toInt();
    if (partnerSentAtUs == null || partnerId == null) return;
    _partnerTapLocalUs = _clock.hasSample
        ? _clock.partnerToLocalUs(partnerSentAtUs)
        : receivedAtUs;
    _partnerTapId = partnerId;
    _lastInteractionAt = DateTime.now();
    final remoteProgress = (event.data['progress'] as num?)?.toDouble();
    if (remoteProgress != null) {
      _progress.mergeRemote(remoteProgress);
      _animateProgressTo(_progress.progress);
    }
    _partnerTap.forward(from: 0);
    final matched = _scoreCurrentPair();
    if (!matched) unawaited(_player.play(HapticPatterns.syncEcho));
    setState(() {});
  }

  bool _scoreCurrentPair() {
    final localUs = _localTapUs;
    final partnerUs = _partnerTapLocalUs;
    final localId = _localTapId;
    final partnerId = _partnerTapId;
    if (localUs == null ||
        partnerUs == null ||
        localId == null ||
        partnerId == null) {
      return false;
    }
    final pair = '$localId:$partnerId';
    if (_lastScoredPair == pair) return false;
    final differenceMs = ((localUs - partnerUs).abs() / 1000).round();
    if (differenceMs > 1400) return false;
    _lastScoredPair = pair;
    final update = _progress.scoreDifference(differenceMs);
    // A physical touch can take part in only one pair. This prevents several
    // rapid partner packets from advancing the journey against one old tap.
    _localTapUs = null;
    _partnerTapLocalUs = null;
    _localTapId = null;
    _partnerTapId = null;
    _animateProgressTo(update.progress);
    if (update.matched) {
      unawaited(_player.play(
        update.completedNow
            ? HapticPatterns.syncTogether
            : HapticPatterns.syncNear,
      ));
    }
    if (update.completedNow) _completed = true;
    unawaited(_sendState());
    setState(() {});
    return update.matched;
  }

  Future<void> _sendState() => ref.read(modeEventBusProvider).send(ModeEvent(
        type: 'sync_state',
        data: {
          'progress': _progress.progress,
          'streak': _progress.streak,
          'completed': _completed,
        },
      ));

  void _receiveState(ModeEvent event) {
    if (!mounted) return;
    final remoteProgress = (event.data['progress'] as num?)?.toDouble();
    if (remoteProgress != null) {
      _progress.mergeRemote(remoteProgress);
      _animateProgressTo(_progress.progress);
    }
    final remoteCompleted = event.data['completed'] as bool? ?? false;
    if (remoteCompleted && !_completed) {
      _completed = true;
      _animateProgressTo(1);
      unawaited(_player.play(HapticPatterns.syncTogether));
    }
    setState(() {});
  }

  void _onLongPressStart(LongPressStartDetails _) {
    _lastInteractionAt = DateTime.now();
    setState(() => _localHolding = true);
    _localTap.forward(from: 0);
    unawaited(_player.play(HapticPatterns.syncHold));
    unawaited(ref.read(modeEventBusProvider).send(const ModeEvent(
          type: 'sync_hold',
          data: {'active': true},
        )));
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    if (!mounted) return;
    setState(() => _localHolding = false);
    unawaited(ref.read(modeEventBusProvider).send(const ModeEvent(
          type: 'sync_hold',
          data: {'active': false},
        )));
  }

  void _receiveHold(ModeEvent event) {
    if (!mounted) return;
    final active = event.data['active'] as bool? ?? false;
    _partnerHoldTimer?.cancel();
    setState(() => _partnerHolding = active);
    if (active) {
      _partnerTap.forward(from: 0);
      unawaited(_player.play(HapticPatterns.syncHold));
      _partnerHoldTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _partnerHolding = false);
      });
    }
  }

  void _animateProgressTo(double target) {
    _progressFrom = _visualProgress;
    _progressTo = target.clamp(0.0, 1.0);
    _progressAnimation.forward(from: 0);
  }

  double get _visualProgress => ui.lerpDouble(
        _progressFrom,
        _progressTo,
        Curves.easeOutCubic.transform(_progressAnimation.value),
      )!;

  void _scheduleNextBeat() {
    if (!mounted) return;
    final intervalUs = widget.guideBeatDuration.inMicroseconds;
    final sharedNow = _clock.sharedNowUs(_nowUs());
    final remainder = sharedNow % intervalUs;
    final delayUs = remainder == 0 ? intervalUs : intervalUs - remainder;
    _beatTimer = Timer(Duration(microseconds: delayUs), () {
      if (!mounted) return;
      _beat.forward(from: 0);
      final quietFor = _lastInteractionAt == null
          ? const Duration(days: 1)
          : DateTime.now().difference(_lastInteractionAt!);
      if (_progress.progress >= .36 &&
          quietFor > const Duration(milliseconds: 520)) {
        unawaited(_player.play(HapticPatterns.syncGuide));
      }
      _scheduleNextBeat();
    });
  }

  String _statusText(AppLocalizations t) {
    final value = _progress.progress;
    if (_completed || value >= .995) return t.syncTogether;
    if (value >= .76) return t.syncHintAlmost;
    if (value >= .38) return t.syncHintCloser;
    if (value > 0) return t.syncHintListen;
    return t.syncHintStart;
  }

  @override
  void dispose() {
    _beatTimer?.cancel();
    _pingTimer?.cancel();
    _partnerHoldTimer?.cancel();
    _partnerSub?.cancel();
    _ambient.dispose();
    _beat.dispose();
    _localTap.dispose();
    _partnerTap.dispose();
    _progressAnimation.dispose();
    unawaited(_player.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final animations = Listenable.merge([
      _ambient,
      _beat,
      _localTap,
      _partnerTap,
      _progressAnimation,
    ]);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onTap,
                onLongPressStart: _onLongPressStart,
                onLongPressEnd: _onLongPressEnd,
                child: AnimatedBuilder(
                  animation: animations,
                  builder: (context, _) => CustomPaint(
                    painter: _SharedPulsePainter(
                      ambient: _ambient.value,
                      beat: _beat.value,
                      localTap: _localTap.value,
                      partnerTap: _partnerTap.value,
                      progress: _visualProgress,
                      completed: _completed,
                      localHolding: _localHolding,
                      partnerHolding: _partnerHolding,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 64,
              right: 64,
              child: Column(
                children: [
                  Text(
                    t.modeSync,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    child: Text(
                      _statusText(t),
                      key: ValueKey(_statusText(t)),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _completed
                            ? const Color(0xFFFFD98B)
                            : AppColors.textPrimary,
                        fontSize: _completed ? 12 : 14,
                        fontWeight:
                            _completed ? FontWeight.w700 : FontWeight.w500,
                        letterSpacing: _completed ? 1 : 0,
                      ),
                    ),
                  ),
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
            Positioned(
              left: 42,
              right: 42,
              bottom: 38,
              child: Column(
                children: [
                  _SyncJourney(progress: _progress.progress),
                  const SizedBox(height: 15),
                  Text(
                    t.syncHoldHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      letterSpacing: .15,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncJourney extends StatelessWidget {
  const _SyncJourney({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final fill = (progress * 5 - index).clamp(0.0, 1.0);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
          width: index == 4 ? 24 : 14,
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            color: Color.lerp(
              Colors.white.withValues(alpha: .08),
              index == 4 ? const Color(0xFFFFD98B) : const Color(0xFFB474FF),
              fill,
            ),
            boxShadow: fill > .7
                ? [
                    BoxShadow(
                      color: (index == 4
                              ? const Color(0xFFFFD98B)
                              : AppColors.pulse)
                          .withValues(alpha: .28),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

class _SharedPulsePainter extends CustomPainter {
  const _SharedPulsePainter({
    required this.ambient,
    required this.beat,
    required this.localTap,
    required this.partnerTap,
    required this.progress,
    required this.completed,
    required this.localHolding,
    required this.partnerHolding,
  });

  final double ambient;
  final double beat;
  final double localTap;
  final double partnerTap;
  final double progress;
  final bool completed;
  final bool localHolding;
  final bool partnerHolding;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero) + const Offset(0, -18);
    final phase = ambient * math.pi * 2;
    final easedProgress = Curves.easeInOutCubic.transform(progress);
    _drawBackground(canvas, size, center, phase, easedProgress);

    final baseRadius = math.min(size.shortestSide * .135, 76.0);
    final startSeparation = math.min(size.width * .255, 132.0);
    final endSeparation = baseRadius * .34;
    final separation = ui.lerpDouble(
      startSeparation,
      endSeparation,
      easedProgress,
    )!;
    final breath = math.sin(phase * 1.13) * 4;
    final localCenter =
        center + Offset(-separation, breath + math.sin(phase * .7) * 2.5);
    final partnerCenter =
        center + Offset(separation, -breath + math.cos(phase * .74) * 2.5);
    final individualOpacity =
        (1 - ((easedProgress - .80) / .20).clamp(0.0, 1.0) * .78)
            .clamp(.22, 1.0);

    _drawGuideBeat(canvas, center, baseRadius, beat, easedProgress);
    _drawConnection(
      canvas,
      localCenter,
      partnerCenter,
      phase,
      easedProgress,
      baseRadius,
    );
    _drawLiquidOrb(
      canvas,
      center: localCenter,
      radius: baseRadius * (1 + (1 - localTap) * .045),
      phase: phase,
      seed: .8,
      primary: const Color(0xFF9B5CFF),
      secondary: const Color(0xFF5D2BC8),
      energy: math.max(1 - localTap, localHolding ? 1 : 0),
      opacity: individualOpacity,
    );
    _drawLiquidOrb(
      canvas,
      center: partnerCenter,
      radius: baseRadius * (1 + (1 - partnerTap) * .045),
      phase: -phase * .91,
      seed: 2.4,
      primary: const Color(0xFFFF67A6),
      secondary: const Color(0xFF9D3C89),
      energy: math.max(1 - partnerTap, partnerHolding ? 1 : 0),
      opacity: individualOpacity,
    );
    _drawTapRipple(
      canvas,
      localCenter,
      baseRadius,
      localTap,
      const Color(0xFFB98BFF),
    );
    _drawTapRipple(
      canvas,
      partnerCenter,
      baseRadius,
      partnerTap,
      const Color(0xFFFF8FBC),
    );

    if (easedProgress > .72) {
      _drawSharedCore(
        canvas,
        center,
        baseRadius,
        phase,
        ((easedProgress - .72) / .28).clamp(0.0, 1.0),
      );
    }
  }

  void _drawBackground(
    Canvas canvas,
    Size size,
    Offset center,
    double phase,
    double value,
  ) {
    final pulse = .94 + math.sin(phase * .82) * .06;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -.08),
          radius: .88,
          colors: [
            Color.lerp(
              const Color(0xFF171126),
              const Color(0xFF30203D),
              value,
            )!
                .withValues(alpha: .88 * pulse),
            const Color(0xFF090711),
            AppColors.background,
          ],
          stops: const [0, .52, 1],
        ).createShader(Offset.zero & size),
    );
    canvas.drawCircle(
      center,
      size.shortestSide * (.36 + value * .16),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFAA68FF)
                .withValues(alpha: (.025 + value * .055) * pulse),
            const Color(0xFFFF79B2).withValues(alpha: value * .026),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(
          center: center,
          radius: size.shortestSide * .52,
        )),
    );
  }

  void _drawGuideBeat(
    Canvas canvas,
    Offset center,
    double radius,
    double beatValue,
    double value,
  ) {
    if (beatValue <= 0 || beatValue >= 1) return;
    final eased = Curves.easeOutCubic.transform(beatValue);
    canvas.drawCircle(
      center,
      radius * (1.15 + eased * (1.4 + value)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ui.lerpDouble(2.2, .4, eased)!
        ..color = Color.lerp(
          const Color(0xFFAB73FF),
          const Color(0xFFFFD98B),
          value,
        )!
            .withValues(alpha: (1 - eased) * (.15 + value * .18)),
    );
  }

  void _drawConnection(
    Canvas canvas,
    Offset from,
    Offset to,
    double phase,
    double value,
    double radius,
  ) {
    if (value <= .015) return;
    final rect = Rect.fromPoints(from, to).inflate(radius * .3);
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(
        from.dx + (to.dx - from.dx) * .34,
        from.dy + math.sin(phase * 1.4) * (8 - value * 5),
        from.dx + (to.dx - from.dx) * .66,
        to.dy - math.sin(phase * 1.4) * (8 - value * 5),
        to.dx,
        to.dy,
      );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.4 + value * 11
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + value * 8)
        ..shader = const LinearGradient(
          colors: [Color(0xFF9D64FF), Color(0xFFFF78AE)],
        ).createShader(rect),
    );

    final particleCount = 3 + (value * 5).round();
    for (var i = 0; i < particleCount; i++) {
      final travel = (ambient * (.55 + i * .07) + i / particleCount) % 1;
      final point = Offset.lerp(from, to, travel)! +
          Offset(0, math.sin(phase + i * 1.7) * (5 - value * 3));
      canvas.drawCircle(
        point,
        1.2 + value * 1.5,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = Color.lerp(
            const Color(0xFFC9A8FF),
            const Color(0xFFFFC0D9),
            travel,
          )!
              .withValues(alpha: .22 + value * .42),
      );
    }
  }

  void _drawLiquidOrb(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required double phase,
    required double seed,
    required Color primary,
    required Color secondary,
    required double energy,
    double opacity = 1,
  }) {
    final path = _blobPath(
      center: center,
      radius: radius,
      phase: phase,
      seed: seed,
      energy: energy,
    );
    final bounds = path.getBounds();
    canvas.drawPath(
      path,
      Paint()
        ..color = primary.withValues(alpha: (.24 + energy * .08) * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
    );
    canvas.saveLayer(bounds.inflate(8), Paint());
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.34, -.42),
          radius: 1.16,
          colors: [
            Colors.white.withValues(alpha: (.48 + energy * .12) * opacity),
            primary.withValues(alpha: .88 * opacity),
            secondary.withValues(alpha: .72 * opacity),
            const Color(0xFF11091E).withValues(alpha: .78 * opacity),
          ],
          stops: const [0, .18, .64, 1],
        ).createShader(bounds),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: .52 * opacity),
            primary.withValues(alpha: .18 * opacity),
            Colors.white.withValues(alpha: .05 * opacity),
          ],
        ).createShader(bounds),
    );
    canvas.restore();

    final highlight = Rect.fromCenter(
      center: center - Offset(radius * .28, radius * .31),
      width: radius * .58,
      height: radius * .18,
    );
    canvas.drawOval(
      highlight,
      Paint()
        ..color = Colors.white.withValues(alpha: (.20 + energy * .07) * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      center + Offset(radius * .22, radius * .28),
      radius * .28,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            primary.withValues(alpha: .22 * opacity),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(
          center: center + Offset(radius * .22, radius * .28),
          radius: radius * .32,
        )),
    );
  }

  Path _blobPath({
    required Offset center,
    required double radius,
    required double phase,
    required double seed,
    required double energy,
  }) {
    const points = 64;
    final path = Path();
    for (var i = 0; i <= points; i++) {
      final angle = i / points * math.pi * 2;
      final organic = math.sin(angle * 3 + phase * 1.3 + seed) * 1.5 +
          math.sin(angle * 5 - phase * .82 + seed * 2) * .72;
      final pulse = math.sin(phase * 1.6 + seed) * 1.15;
      final r = radius + organic * (1 + energy * .38) + pulse;
      final point = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  void _drawTapRipple(
    Canvas canvas,
    Offset center,
    double radius,
    double animation,
    Color color,
  ) {
    if (animation <= 0 || animation >= 1) return;
    final eased = Curves.easeOutCubic.transform(animation);
    canvas.drawCircle(
      center,
      radius * (1.02 + eased * .9),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ui.lerpDouble(2.4, .35, eased)!
        ..color = color.withValues(alpha: (1 - eased) * .44),
    );
  }

  void _drawSharedCore(
    Canvas canvas,
    Offset center,
    double radius,
    double phase,
    double amount,
  ) {
    final pulse = .96 + math.sin(phase * 1.7) * .04;
    final sharedRadius = radius * (1.02 + amount * .26) * pulse;
    final sharedPath = _blobPath(
      center: center,
      radius: sharedRadius,
      phase: phase * .72,
      seed: 4.7,
      energy: amount,
    );
    final bounds = sharedPath.getBounds();
    canvas.drawPath(
      sharedPath,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = const Color(0xFFCD83FF).withValues(alpha: amount * .24)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );
    canvas.saveLayer(bounds.inflate(6), Paint());
    canvas.drawPath(
      sharedPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            const Color(0xFF7650E8).withValues(alpha: amount * .94),
            const Color(0xFFC46BDF).withValues(alpha: amount * .96),
            const Color(0xFFF06FAF).withValues(alpha: amount * .90),
          ],
        ).createShader(bounds),
    );
    canvas.drawPath(
      sharedPath,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          center: const Alignment(-.08, -.18),
          radius: .88,
          colors: [
            Colors.white.withValues(alpha: amount * .56),
            const Color(0xFFFFD98B).withValues(alpha: amount * .24),
            Colors.transparent,
          ],
          stops: const [0, .27, 1],
        ).createShader(bounds),
    );
    canvas.drawPath(
      sharedPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: amount * .58),
            const Color(0xFFFFCBE2).withValues(alpha: amount * .16),
            Colors.white.withValues(alpha: amount * .04),
          ],
        ).createShader(bounds),
    );
    canvas.restore();
    canvas.drawOval(
      Rect.fromCenter(
        center: center - Offset(sharedRadius * .24, sharedRadius * .30),
        width: sharedRadius * .54,
        height: sharedRadius * .17,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: amount * .24)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    if (completed) {
      for (var i = 0; i < 12; i++) {
        final angle = phase * .22 + i / 12 * math.pi * 2;
        final orbit = radius * (1.45 + math.sin(phase + i) * .08);
        canvas.drawCircle(
          center + Offset(math.cos(angle), math.sin(angle)) * orbit,
          1.25 + (i % 3) * .45,
          Paint()
            ..blendMode = BlendMode.plus
            ..color =
                const Color(0xFFFFD98B).withValues(alpha: .28 + (i % 2) * .12),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SharedPulsePainter old) =>
      old.ambient != ambient ||
      old.beat != beat ||
      old.localTap != localTap ||
      old.partnerTap != partnerTap ||
      old.progress != progress ||
      old.completed != completed ||
      old.localHolding != localHolding ||
      old.partnerHolding != partnerHolding;
}
