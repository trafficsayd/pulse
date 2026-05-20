import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../capabilities/application/capability_providers.dart';
import '../../../capabilities/domain/device_capability.dart';
import '../../primitives/accelerometer_3d_stream.dart';
import '../../primitives/haptic_pattern_player.dart';
import 'unsupported_mode_screen.dart';

/// Stream of "partner" [Accel3] events ramping `x` from -1 to 1 over
/// [period], looping. `y` and `z` stay at 0. Used by [BalanceModeScreen]
/// to render a simulated second ball when no real partner stream is
/// available.
///
/// The stream is push-based — a [Timer.periodic] drives a synthetic
/// ramp at [tick] cadence so widget tests can use `tester.pump` to
/// advance time deterministically.
class SimulatedPartnerAccelStream implements Accelerometer3DStream {
  SimulatedPartnerAccelStream({
    this.period = const Duration(seconds: 4),
    this.tick = const Duration(milliseconds: 50),
    Stopwatch? stopwatch,
  }) : _stopwatch = stopwatch ?? Stopwatch() {
    _stopwatch.start();
  }

  final Duration period;
  final Duration tick;
  final Stopwatch _stopwatch;
  final StreamController<Accel3> _controller =
      StreamController<Accel3>.broadcast();
  Timer? _timer;

  @override
  Stream<Accel3> get events {
    _timer ??= Timer.periodic(tick, (_) {
      if (_controller.isClosed) return;
      final t = _stopwatch.elapsedMilliseconds % period.inMilliseconds;
      final phase = t / period.inMilliseconds;
      // Ramp -1 → 1 → -1 (triangle wave), so the partner ball drifts
      // smoothly rather than snapping back at the wrap point.
      final tri = phase < 0.5 ? -1 + 4 * phase : 3 - 4 * phase;
      _controller.add(Accel3(tri, 0, 0, timestamp: DateTime.now()));
    });
    return _controller.stream;
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    _stopwatch.stop();
    await _controller.close();
  }
}

/// "Balance" — tilt-the-phone ball-rolling mode.
///
/// Integrates [Accel3.x] / [Accel3.y] into a 2-D position in
/// `[-1, 1]^2` using Euler steps keyed off the sample timestamp:
///
///   position += accel.{x,y} * dt
///   position  = clamp(position, -1, 1)
///
/// The ball widget is translated by `position * size/2` so position 0
/// lands the ball at the screen centre and ±1 pins it against the
/// edge. When either axis crosses 0.9 in magnitude the screen fires a
/// single [HapticPatterns.tap] (debounced for [_edgeCooldown]) so the
/// user feels when they've hit the rim.
///
/// A second, fainter ball is driven by the partner stream (defaults
/// to [SimulatedPartnerAccelStream]) so a solo user can see how the
/// two channels read together.
///
/// Disposal: cancels both subscriptions, stops the haptic player, and
/// disposes the simulated partner if we own it.
class BalanceModeScreen extends ConsumerWidget {
  const BalanceModeScreen({
    super.key,
    this.accelerometerStream,
    this.partnerStream,
    this.hapticEngine,
    this.edgeThreshold = 0.9,
  });

  /// Optional override. Tests pass in a [FakeAccelerometer3DStream] so
  /// the runner never reaches `sensors_plus`.
  final Accelerometer3DStream? accelerometerStream;

  /// Optional partner override. When null, the screen owns a
  /// [SimulatedPartnerAccelStream].
  final Accelerometer3DStream? partnerStream;

  /// Optional haptic engine. Defaults to [NullHapticEngine].
  final HapticEngine? hapticEngine;

  /// Absolute position on either axis that triggers the edge haptic.
  final double edgeThreshold;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final capsAsync = ref.watch(deviceCapabilitiesProvider);
    const required = {DeviceCapability.accelerometer};
    if (capsAsync.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.pulse),
        ),
      );
    }
    final caps = capsAsync.asData?.value ?? const DeviceCapabilities.none();
    if (!caps.hasAll(required)) {
      return UnsupportedModeScreen(
        title: t.modeBalance,
        missing: caps.missing(required),
      );
    }
    return _BalanceModeView(
      accelerometerStream: accelerometerStream,
      partnerStream: partnerStream,
      hapticEngine: hapticEngine,
      edgeThreshold: edgeThreshold,
    );
  }
}

class _BalanceModeView extends StatefulWidget {
  const _BalanceModeView({
    required this.accelerometerStream,
    required this.partnerStream,
    required this.hapticEngine,
    required this.edgeThreshold,
  });

  final Accelerometer3DStream? accelerometerStream;
  final Accelerometer3DStream? partnerStream;
  final HapticEngine? hapticEngine;
  final double edgeThreshold;

  @override
  State<_BalanceModeView> createState() => _BalanceModeViewState();
}

class _BalanceModeViewState extends State<_BalanceModeView> {
  late final Accelerometer3DStream _accel;
  late final Accelerometer3DStream _partner;
  late final HapticEngine _engine;
  late final HapticPatternPlayer _player;
  StreamSubscription<Accel3>? _accelSub;
  StreamSubscription<Accel3>? _partnerSub;
  Timer? _edgeCooldownTimer;

  bool _ownsAccel = false;
  bool _ownsPartner = false;
  bool _ownsEngine = false;

  Offset _localPosition = Offset.zero;
  Offset _partnerPosition = Offset.zero;
  DateTime? _lastLocalTimestamp;
  DateTime? _lastPartnerTimestamp;
  bool _edgeCooldown = false;

  static const Duration _edgeCooldownDuration = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    if (widget.accelerometerStream == null) {
      _accel = FakeAccelerometer3DStream();
      _ownsAccel = true;
    } else {
      _accel = widget.accelerometerStream!;
    }
    if (widget.partnerStream == null) {
      _partner = SimulatedPartnerAccelStream();
      _ownsPartner = true;
    } else {
      _partner = widget.partnerStream!;
    }
    if (widget.hapticEngine == null) {
      _engine = const NullHapticEngine();
      _ownsEngine = true;
    } else {
      _engine = widget.hapticEngine!;
    }
    _player = HapticPatternPlayer(_engine);
    _accelSub = _accel.events.listen(_onLocalAccel);
    _partnerSub = _partner.events.listen(_onPartnerAccel);
  }

  void _onLocalAccel(Accel3 sample) {
    if (!mounted) return;
    final last = _lastLocalTimestamp;
    _lastLocalTimestamp = sample.timestamp;
    final dt = last == null
        ? 0.0
        : sample.timestamp.difference(last).inMicroseconds / 1e6;
    final nextX = (_localPosition.dx + sample.x * dt).clamp(-1.0, 1.0);
    final nextY = (_localPosition.dy + sample.y * dt).clamp(-1.0, 1.0);
    setState(() {
      _localPosition = Offset(nextX, nextY);
    });
    if (!_edgeCooldown &&
        (nextX.abs() > widget.edgeThreshold ||
            nextY.abs() > widget.edgeThreshold)) {
      _fireEdgeHaptic();
    }
  }

  void _onPartnerAccel(Accel3 sample) {
    if (!mounted) return;
    final last = _lastPartnerTimestamp;
    _lastPartnerTimestamp = sample.timestamp;
    final dt = last == null
        ? 0.0
        : sample.timestamp.difference(last).inMicroseconds / 1e6;
    final nextX = (_partnerPosition.dx + sample.x * dt).clamp(-1.0, 1.0);
    final nextY = (_partnerPosition.dy + sample.y * dt).clamp(-1.0, 1.0);
    setState(() {
      _partnerPosition = Offset(nextX, nextY);
    });
  }

  void _fireEdgeHaptic() {
    _edgeCooldown = true;
    unawaited(_player.play(HapticPatterns.tap));
    _edgeCooldownTimer?.cancel();
    _edgeCooldownTimer = Timer(_edgeCooldownDuration, () {
      if (!mounted) return;
      _edgeCooldown = false;
    });
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _partnerSub?.cancel();
    _edgeCooldownTimer?.cancel();
    unawaited(_player.stop());
    if (_ownsAccel) {
      unawaited(_accel.dispose());
    }
    if (_ownsPartner) {
      unawaited(_partner.dispose());
    }
    if (_ownsEngine) {
      unawaited(_engine.cancel());
    }
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = math.min(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final centre = Offset(
                    constraints.maxWidth / 2,
                    constraints.maxHeight / 2,
                  );
                  final localBall = centre +
                      Offset(
                        _localPosition.dx * (size / 2),
                        _localPosition.dy * (size / 2),
                      );
                  final partnerBall = centre +
                      Offset(
                        _partnerPosition.dx * (size / 2),
                        _partnerPosition.dy * (size / 2),
                      );
                  return RepaintBoundary(
                    child: CustomPaint(
                      painter: _BalancePainter(
                        localBall: localBall,
                        partnerBall: partnerBall,
                        arenaRadius: size / 2,
                        arenaCentre: centre,
                      ),
                      child: const SizedBox.expand(),
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
                  t.modeBalanceHint,
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

class _BalancePainter extends CustomPainter {
  const _BalancePainter({
    required this.localBall,
    required this.partnerBall,
    required this.arenaRadius,
    required this.arenaCentre,
  });

  final Offset localBall;
  final Offset partnerBall;
  final double arenaRadius;
  final Offset arenaCentre;

  static const Color _localBallColor = AppColors.pulse;
  static const Color _partnerBallColor = Color(0xFF6BD3FF);

  @override
  void paint(Canvas canvas, Size size) {
    // Arena rim — soft outlined circle so the user reads the boundary.
    final rim = Paint()
      ..color = AppColors.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..isAntiAlias = true;
    canvas.drawCircle(arenaCentre, arenaRadius, rim);

    final ballRadius = arenaRadius * 0.08;

    // Partner ball first so the local ball draws on top.
    final partnerPaint = Paint()
      ..color = _partnerBallColor.withValues(alpha: 0.5)
      ..isAntiAlias = true;
    canvas.drawCircle(partnerBall, ballRadius, partnerPaint);

    final localPaint = Paint()
      ..color = _localBallColor
      ..isAntiAlias = true;
    canvas.drawCircle(localBall, ballRadius, localPaint);
  }

  @override
  bool shouldRepaint(covariant _BalancePainter old) =>
      old.localBall != localBall ||
      old.partnerBall != partnerBall ||
      old.arenaRadius != arenaRadius ||
      old.arenaCentre != arenaCentre;
}
