import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../capabilities/application/capability_providers.dart';
import '../../../capabilities/domain/device_capability.dart';
import '../../primitives/accelerometer_3d_stream.dart';
import '../../primitives/haptic_pattern_player.dart';
import '../../primitives/primitive_providers.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import 'unsupported_mode_screen.dart';

/// "Bell" — shake-to-ring mode driven by [Accelerometer3DStream].
///
/// Detects a shake when [Accel3.netMagnitude] stays above 12 m/s² for
/// at least 100ms. On a shake we:
///   1. Play [HapticPatterns.triple] through the haptic engine.
///   2. Animate a bell-icon rotation tween (a quick swing + decay).
///   3. Ring a system alert tone via [SystemSound.play].
///
/// Disposal: cancels the sensor subscription, stops the animation
/// controller, and aborts any in-flight haptic before [super.dispose].
class BellModeScreen extends ConsumerWidget {
  const BellModeScreen({
    super.key,
    this.accelerometerStream,
    this.hapticEngine,
    this.shakeThreshold = 12.0,
    this.shakeWindow = const Duration(milliseconds: 100),
  });

  /// Optional override. Tests pass in a [FakeAccelerometer3DStream] and
  /// push synthetic samples through [FakeAccelerometer3DStream.push].
  /// In production this is null and the screen reads the real sensor
  /// via [accelerometerStreamProvider].
  final Accelerometer3DStream? accelerometerStream;

  /// Optional override for the haptic engine. Defaults to the real
  /// device vibrator via [hapticEngineProvider].
  final HapticEngine? hapticEngine;

  /// Net magnitude (m/s², gravity removed) that counts as "shaking".
  final double shakeThreshold;

  /// Minimum dwell time over [shakeThreshold] before a shake is
  /// recognised — filters out single accidental jolts.
  final Duration shakeWindow;

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
        title: t.modeBell,
        missing: caps.missing(required),
      );
    }
    return _BellModeView(
      accelerometerStream:
          accelerometerStream ?? ref.watch(accelerometerStreamProvider),
      hapticEngine: hapticEngine ?? ref.watch(hapticEngineProvider),
      shakeThreshold: shakeThreshold,
      shakeWindow: shakeWindow,
    );
  }
}

class _BellModeView extends ConsumerStatefulWidget {
  const _BellModeView({
    required this.accelerometerStream,
    required this.hapticEngine,
    required this.shakeThreshold,
    required this.shakeWindow,
  });

  final Accelerometer3DStream? accelerometerStream;
  final HapticEngine? hapticEngine;
  final double shakeThreshold;
  final Duration shakeWindow;

  @override
  ConsumerState<_BellModeView> createState() => _BellModeViewState();
}

class _BellModeViewState extends ConsumerState<_BellModeView>
    with SingleTickerProviderStateMixin {
  late final Accelerometer3DStream _accel;
  late final HapticEngine _engine;
  late final HapticPatternPlayer _player;
  late final AnimationController _swing;
  StreamSubscription<Accel3>? _sub;
  StreamSubscription<ModeEvent>? _partnerSub;
  Timer? _cooldownTimer;

  bool _ownsAccel = false;
  bool _ownsEngine = false;

  /// Smoothed shake intensity in `[0, 1]`. Drives the bottom "intensity
  /// bar" and stays alive even after the burst of shakes settles.
  double _intensity = 0.0;

  /// Timestamp of the first sample inside the current over-threshold
  /// window. Reset whenever the magnitude dips back below threshold.
  DateTime? _windowStart;

  /// Set during a shake event for [_cooldown] so a single sustained
  /// shake fires the bell once rather than 60 times a second.
  bool _cooldownActive = false;
  static const Duration _cooldown = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    if (widget.accelerometerStream == null) {
      _accel = FakeAccelerometer3DStream();
      _ownsAccel = true;
    } else {
      _accel = widget.accelerometerStream!;
    }
    if (widget.hapticEngine == null) {
      _engine = const NullHapticEngine();
      _ownsEngine = true;
    } else {
      _engine = widget.hapticEngine!;
    }
    _player = HapticPatternPlayer(_engine);
    _swing = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      value: 0.0,
    );
    _sub = _accel.events.listen(_onAccel);
    _partnerSub = ref.read(modeEventBusProvider).incoming
        .where((e) => e.type == 'bell_ring')
        .listen((e) {
      if (mounted) _firePartnerRing();
    });
  }

  void _firePartnerRing() {
    _swing
      ..value = 0.0
      ..forward();
    unawaited(SystemSound.play(SystemSoundType.alert));
    unawaited(_player.play(HapticPatterns.triple));
  }

  void _onAccel(Accel3 sample) {
    if (!mounted) return;
    final mag = sample.netMagnitude;
    // Lightweight low-pass over the intensity bar so it visually
    // settles back even when samples are noisy.
    final normalized = (mag / (widget.shakeThreshold * 1.6)).clamp(0.0, 1.0);
    setState(() {
      _intensity = math.max(_intensity * 0.85, normalized);
    });

    if (mag <= widget.shakeThreshold) {
      _windowStart = null;
      return;
    }
    final now = sample.timestamp;
    _windowStart ??= now;
    final dwell = now.difference(_windowStart!);
    if (dwell >= widget.shakeWindow && !_cooldownActive) {
      _fireShake();
    }
  }

  void _fireShake() {
    _cooldownActive = true;
    _swing
      ..value = 0.0
      ..forward();
    unawaited(SystemSound.play(SystemSoundType.alert));
    unawaited(_player.play(HapticPatterns.triple));
    // Send bell ring event to partner.
    ref.read(modeEventBusProvider).send(
          ModeEvent(type: 'bell_ring', data: {'intensity': _intensity}),
        );
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(_cooldown, () {
      if (!mounted) return;
      _cooldownActive = false;
      _windowStart = null;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _partnerSub?.cancel();
    _cooldownTimer?.cancel();
    _swing.dispose();
    unawaited(_player.stop());
    if (_ownsAccel) {
      unawaited(_accel.dispose());
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
            Center(
              child: AnimatedBuilder(
                animation: _swing,
                builder: (context, _) {
                  // Decaying triangle wave — full swing on impact,
                  // fading wobble while the controller eases back.
                  final v = _swing.value;
                  final angle = 0.55 *
                      math.sin(v * math.pi * 4) *
                      (1 - v).clamp(0.0, 1.0);
                  return Transform.rotate(
                    angle: angle,
                    child: const Icon(
                      Icons.notifications_active_rounded,
                      size: 168,
                      color: AppColors.pulse,
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
                  t.bellHint,
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
              left: 24,
              right: 24,
              bottom: 32,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.bellIntensity,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: _intensity.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: AppColors.outlineSoft,
                      valueColor: const AlwaysStoppedAnimation(AppColors.pulse),
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
          ],
        ),
      ),
    );
  }
}
