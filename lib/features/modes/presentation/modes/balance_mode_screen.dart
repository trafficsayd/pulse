import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../capabilities/application/capability_providers.dart';
import '../../../capabilities/domain/device_capability.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import '../../application/balance/balance_dynamics.dart';
import '../../primitives/accelerometer_3d_stream.dart';
import '../../primitives/haptic_pattern_player.dart';
import '../../primitives/primitive_providers.dart';

/// Two phones apply forces to one shared physical object. Sensor input is the
/// default, while dragging anywhere on the field is an always-available
/// fallback for emulators, desktops and accessibility use.
class BalanceModeScreen extends ConsumerWidget {
  const BalanceModeScreen({
    super.key,
    this.accelerometer,
    this.sensorAvailable,
    this.hapticEngine,
    this.frameDuration = const Duration(seconds: 8),
    this.networkSendInterval = const Duration(milliseconds: 55),
  });

  final Accelerometer3DStream? accelerometer;
  final bool? sensorAvailable;
  final HapticEngine? hapticEngine;
  final Duration frameDuration;
  final Duration networkSendInterval;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (accelerometer != null || sensorAvailable != null) {
      return _BalanceModeView(
        accelerometer: sensorAvailable == false ? null : accelerometer,
        hapticEngine: hapticEngine,
        frameDuration: frameDuration,
        networkSendInterval: networkSendInterval,
      );
    }
    final capsAsync = ref.watch(deviceCapabilitiesProvider);
    if (capsAsync.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.pulse)),
      );
    }
    final caps = capsAsync.asData?.value ?? const DeviceCapabilities.none();
    final hasSensor = caps.has(DeviceCapability.accelerometer);
    return _BalanceModeView(
      accelerometer: hasSensor ? ref.watch(accelerometerStreamProvider) : null,
      hapticEngine: hapticEngine,
      frameDuration: frameDuration,
      networkSendInterval: networkSendInterval,
    );
  }
}

class _BalanceModeView extends ConsumerStatefulWidget {
  const _BalanceModeView({
    required this.accelerometer,
    required this.hapticEngine,
    required this.frameDuration,
    required this.networkSendInterval,
  });

  final Accelerometer3DStream? accelerometer;
  final HapticEngine? hapticEngine;
  final Duration frameDuration;
  final Duration networkSendInterval;

  @override
  ConsumerState<_BalanceModeView> createState() => _BalanceModeViewState();
}

class _BalanceModeViewState extends ConsumerState<_BalanceModeView>
    with SingleTickerProviderStateMixin {
  final BalanceSensorNormalizer _normalizer = BalanceSensorNormalizer();
  final CooperativeBalancePhysics _physics = CooperativeBalancePhysics();
  final BalanceRemoteReconciler _remote = BalanceRemoteReconciler();
  final BalancePacketDeduplicator _deduplicator = BalancePacketDeduplicator();
  final List<BalanceVector> _trail = [];

  StreamSubscription<Accel3>? _sensorSub;
  StreamSubscription<ModeEvent>? _partnerSub;
  Timer? _reducedTickTimer;
  late final AnimationController _clock;
  late final HapticPatternPlayer _haptics;
  CooperativeBalanceFrame _frame = const CooperativeBalanceFrame(
    position: BalanceVector.zero,
    velocity: BalanceVector.zero,
    combinedIntent: BalanceVector.zero,
    stability: 1,
    partnerWeight: 0,
  );
  BalanceRemoteState _remoteState = const BalanceRemoteState(
    intent: BalanceVector.zero,
    position: BalanceVector.zero,
    velocity: BalanceVector.zero,
    weight: 0,
  );
  BalanceVector _sensorIntent = BalanceVector.zero;
  BalanceVector? _gestureIntent;
  DateTime? _lastFrameAt;
  DateTime? _lastSentAt;
  DateTime? _lastTrailAt;
  double _stableSeconds = 0;
  bool _celebrated = false;
  bool _reduceMotion = false;
  late final int _epoch;
  int _sequence = 0;

  BalanceVector get _localIntent => _gestureIntent ?? _sensorIntent;

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
    _sensorSub = widget.accelerometer?.events.listen(_onSensor);
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
        .where((event) => event.type == 'balance_ball')
        .listen(_onPartnerState);
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

  void _onSensor(Accel3 sample) {
    if (!mounted || _gestureIntent != null) return;
    _sensorIntent = _normalizer.add(sample.x, sample.y);
  }

  void _tick() {
    if (!mounted) return;
    final now = DateTime.now();
    final previous = _lastFrameAt;
    _lastFrameAt = now;
    final delta = previous == null
        ? 1 / 60
        : now.difference(previous).inMicroseconds / 1000000;
    _remoteState = _remote.resolveAt(now.microsecondsSinceEpoch);
    _physics.reconcile(
      remotePosition: _remoteState.position,
      remoteVelocity: _remoteState.velocity,
      confidence: _remoteState.weight,
    );
    _frame = _physics.step(
      localIntent: _localIntent,
      partnerIntent: _remoteState.intent,
      partnerWeight: _remoteState.weight,
      deltaSeconds: delta,
    );
    _updateStability(delta);
    if (_lastTrailAt == null ||
        now.difference(_lastTrailAt!) > const Duration(milliseconds: 90)) {
      _lastTrailAt = now;
      _trail.add(_frame.position);
      final limit = _reduceMotion ? 5 : 18;
      if (_trail.length > limit) _trail.removeAt(0);
    }
    _sendState(now);
    setState(() {});
  }

  void _updateStability(double delta) {
    final cooperative = _remoteState.weight > .2;
    if (cooperative && _frame.stability > .83) {
      _stableSeconds += delta;
      if (_stableSeconds >= 1.15 && !_celebrated) {
        _celebrated = true;
        unawaited(_haptics.play(HapticPatterns.syncTogether));
      }
    } else {
      _stableSeconds = math.max(0, _stableSeconds - delta * 1.6);
      if (_frame.stability < .62) _celebrated = false;
    }
  }

  void _sendState(DateTime now) {
    if (_lastSentAt != null &&
        now.difference(_lastSentAt!) < widget.networkSendInterval) {
      return;
    }
    _lastSentAt = now;
    unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
          type: 'balance_ball',
          data: BalanceProtocol.state(
            epoch: _epoch,
            sequence: ++_sequence,
            sentAtUs: now.microsecondsSinceEpoch,
            intent: _localIntent,
            position: _frame.position,
            velocity: _frame.velocity,
            source: _gestureIntent == null ? 'sensor' : 'gesture',
          ),
        )));
  }

  void _onPartnerState(ModeEvent event) {
    if (!mounted) return;
    final packet = BalanceProtocol.parse(event.data);
    if (packet == null || !_deduplicator.accept(packet)) return;
    _remote.push(BalanceRemoteSample(
      intent: packet.intent,
      position: packet.position,
      velocity: packet.velocity,
      sentAtUs: packet.sentAtUs ?? DateTime.now().microsecondsSinceEpoch,
      receivedAtUs: DateTime.now().microsecondsSinceEpoch,
    ));
    // Incoming state only enters the reconciler. It never invokes _sendState,
    // preventing a remote replay/echo loop.
  }

  BalanceVector _gestureVector(Offset localPosition, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.max(1.0, size.shortestSide * .38);
    return BalanceVector(
      (localPosition.dx - center.dx) / radius,
      (localPosition.dy - center.dy) / radius,
    ).clampMagnitude();
  }

  void _onPanStart(DragStartDetails details, Size size) {
    _gestureIntent = _gestureVector(details.localPosition, size);
    unawaited(_haptics.play(HapticPatterns.syncTouch));
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    _gestureIntent = _gestureVector(details.localPosition, size);
    setState(() {});
  }

  void _onPanEnd() {
    _gestureIntent = null;
    _sensorIntent = BalanceVector.zero;
    setState(() {});
  }

  @override
  void dispose() {
    _sensorSub?.cancel();
    _partnerSub?.cancel();
    _reducedTickTimer?.cancel();
    _clock
      ..removeListener(_tick)
      ..dispose();
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
            final size = constraints.biggest;
            return Stack(
              children: [
                Positioned.fill(
                  child: Semantics(
                    container: true,
                    label: t.modeBalance,
                    child: GestureDetector(
                      excludeFromSemantics: true,
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (details) => _onPanStart(details, size),
                      onPanUpdate: (details) => _onPanUpdate(details, size),
                      onPanEnd: (_) => _onPanEnd(),
                      onPanCancel: _onPanEnd,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _BalanceFieldPainter(
                            frame: _frame,
                            localIntent: _localIntent,
                            partnerIntent: _remoteState.intent,
                            partnerWeight: _remoteState.weight,
                            phase: _clock.value,
                            trail: List<BalanceVector>.of(_trail),
                            celebrated: _celebrated,
                            reduceMotion: _reduceMotion,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 14,
                  left: 60,
                  right: 60,
                  child: Column(
                    children: [
                      Text(
                        t.modeBalance,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .25,
                        ),
                      ),
                      const SizedBox(height: 9),
                      _StabilityPill(
                        stability: _frame.stability,
                        connected: _remoteState.weight > .15,
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
                  bottom: 28,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _InputGlyph(
                      sensorAvailable: widget.accelerometer != null,
                      gestureActive: _gestureIntent != null,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StabilityPill extends StatelessWidget {
  const _StabilityPill({required this.stability, required this.connected});

  final double stability;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final color = connected
        ? Color.lerp(
            const Color(0xFFFF86B5),
            const Color(0xFF91E8C4),
            stability,
          )!
        : const Color(0xFF8D879A);
    return Container(
      width: 48,
      height: 7,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      alignment: Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 4 + stability * 38,
        height: 3,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(99),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: .35), blurRadius: 5)
          ],
        ),
      ),
    );
  }
}

class _InputGlyph extends StatelessWidget {
  const _InputGlyph({
    required this.sensorAvailable,
    required this.gestureActive,
  });

  final bool sensorAvailable;
  final bool gestureActive;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 58,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: gestureActive ? .09 : .045),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white.withValues(alpha: .07)),
        ),
        child: Icon(
          sensorAvailable && !gestureActive
              ? Icons.screen_rotation_alt_rounded
              : Icons.swipe_rounded,
          size: 16,
          color: gestureActive ? const Color(0xFFC7A5FF) : AppColors.textMuted,
        ),
      );
}

class _BalanceFieldPainter extends CustomPainter {
  const _BalanceFieldPainter({
    required this.frame,
    required this.localIntent,
    required this.partnerIntent,
    required this.partnerWeight,
    required this.phase,
    required this.trail,
    required this.celebrated,
    required this.reduceMotion,
  });

  final CooperativeBalanceFrame frame;
  final BalanceVector localIntent;
  final BalanceVector partnerIntent;
  final double partnerWeight;
  final double phase;
  final List<BalanceVector> trail;
  final bool celebrated;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero) + const Offset(0, 8);
    final radius = math.min(size.width * .39, size.height * .31);
    _drawBackground(canvas, size, center, radius);
    _drawBowl(canvas, center, radius);
    _drawIntent(
        canvas, center, radius, localIntent, const Color(0xFF9B76FF), 1);
    _drawIntent(
      canvas,
      center,
      radius,
      partnerIntent,
      const Color(0xFFFF83B5),
      partnerWeight,
    );
    _drawTrail(canvas, center, radius);
    final orb = center + Offset(frame.position.x, frame.position.y) * radius;
    _drawOrb(canvas, orb, radius);
  }

  void _drawBackground(Canvas canvas, Size size, Offset center, double radius) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -.08),
          radius: 1.04,
          colors: [Color(0xFF1A1226), Color(0xFF0C0914), AppColors.background],
          stops: [0, .58, 1],
        ).createShader(Offset.zero & size),
    );
    canvas.drawCircle(
      center,
      radius * 1.45,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFAC70FF).withValues(alpha: .035),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius * 1.45)),
    );
  }

  void _drawBowl(Canvas canvas, Offset center, double radius) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(
            frame.combinedIntent.x * .22,
            frame.combinedIntent.y * .22,
          ),
          colors: [
            const Color(0xFF322243).withValues(alpha: .52),
            const Color(0xFF171020).withValues(alpha: .68),
            const Color(0xFF09070E).withValues(alpha: .88),
          ],
          stops: const [0, .68, 1],
        ).createShader(rect),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..shader = const SweepGradient(
          colors: [
            Color(0x1AFFFFFF),
            Color(0x668D68FF),
            Color(0x66FF7FB2),
            Color(0x1AFFFFFF),
          ],
        ).createShader(rect),
    );
    for (final fraction in [.22, .52, .78]) {
      canvas.drawCircle(
        center,
        radius * fraction,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = fraction == .22 ? 1 : .55
          ..color = Color.lerp(
            const Color(0xFFB07BFF),
            const Color(0xFF91E8C4),
            frame.stability,
          )!
              .withValues(alpha: fraction == .22 ? .25 : .08),
      );
    }
  }

  void _drawIntent(
    Canvas canvas,
    Offset center,
    double radius,
    BalanceVector intent,
    Color color,
    double opacity,
  ) {
    if (opacity <= .01) return;
    final start = center + Offset(intent.x, intent.y) * radius * .84;
    final end = center + Offset(intent.x, intent.y) * radius * .48;
    canvas.drawLine(
      start,
      end,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.4
        ..color =
            color.withValues(alpha: opacity * (.16 + intent.magnitude * .25)),
    );
    canvas.drawCircle(
      start,
      3.5,
      Paint()..color = color.withValues(alpha: opacity * .48),
    );
  }

  void _drawTrail(Canvas canvas, Offset center, double radius) {
    if (trail.length < 2) return;
    for (var i = 0; i < trail.length; i++) {
      final value = (i + 1) / trail.length;
      final point = center + Offset(trail[i].x, trail[i].y) * radius;
      canvas.drawCircle(
        point,
        .7 + value * 2.1,
        Paint()
          ..color = const Color(0xFFD6B5FF)
              .withValues(alpha: value * (reduceMotion ? .07 : .18)),
      );
    }
  }

  void _drawOrb(Canvas canvas, Offset point, double radius) {
    final speed = frame.velocity.magnitude;
    final motion = reduceMotion ? 0.0 : math.sin(phase * math.pi * 2) * .7;
    final orbRadius = 17 + speed * 2 + motion;
    final glow = Color.lerp(
      const Color(0xFFFF7FAC),
      const Color(0xFFB88BFF),
      frame.stability,
    )!;
    canvas.drawCircle(
      point,
      orbRadius * (2.2 + (celebrated ? .5 : 0)),
      Paint()
        ..blendMode = BlendMode.plus
        ..color = glow.withValues(alpha: celebrated ? .18 : .10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13),
    );
    canvas.drawCircle(
      point,
      orbRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.38, -.42),
          colors: [
            Colors.white.withValues(alpha: .96),
            glow,
            const Color(0xFF4D286A),
          ],
          stops: const [0, .3, 1],
        ).createShader(Rect.fromCircle(center: point, radius: orbRadius)),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: point - Offset(orbRadius * .27, orbRadius * .32),
        width: orbRadius * .62,
        height: orbRadius * .2,
      ),
      Paint()..color = Colors.white.withValues(alpha: .44),
    );
    if (celebrated) {
      canvas.drawCircle(
        point,
        radius *
            (.22 + (reduceMotion ? 0 : .015 * math.sin(phase * math.pi * 2))),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF91E8C4).withValues(alpha: .32),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BalanceFieldPainter old) =>
      old.frame != frame ||
      old.localIntent != localIntent ||
      old.partnerIntent != partnerIntent ||
      old.partnerWeight != partnerWeight ||
      old.phase != phase ||
      old.trail != trail ||
      old.celebrated != celebrated ||
      old.reduceMotion != reduceMotion;
}
