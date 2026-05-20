import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../capabilities/application/capability_providers.dart';
import '../../../capabilities/domain/device_capability.dart';
import '../../primitives/haptic_pattern_player.dart';
import 'unsupported_mode_screen.dart';

/// "Goosebumps" — drag-driven haptic stroke.
///
/// While the user drags, every pan-update fires a single 12ms
/// [HapticBeat] through [HapticPatternPlayer]. The amplitude is
/// derived from the gesture velocity:
///
///   amplitude01 = clamp(velocity / 800, 0.2, 1.0)
///   amplitude   = (amplitude01 * 255).round()
///
/// On devices whose vibrator does not support amplitude control (i.e.
/// [DeviceCapability.vibrationAmplitude] is missing in the capabilities
/// snapshot) the screen falls back to a fixed-amplitude pulse —
/// [HapticPatterns.whisper.beats.first] — so the gesture still
/// produces feedback, just without the dynamics.
///
/// A faint radial gradient is painted underneath the finger inside a
/// [RepaintBoundary] so the swipe leaves a visible "trail" — important
/// because the haptic feedback alone gives no positional reference.
///
/// Disposal: cancels any in-flight haptic via [HapticPatternPlayer.stop]
/// and releases the engine before [super.dispose].
class GoosebumpsModeScreen extends ConsumerWidget {
  const GoosebumpsModeScreen({
    super.key,
    this.hapticEngine,
    this.minAmplitude01 = 0.2,
    this.velocityDivisor = 800.0,
  });

  /// Optional override for the haptic engine. Tests pass in a
  /// [RecordingHapticEngine] to assert exact beats fired.
  final HapticEngine? hapticEngine;

  /// Floor for the derived amplitude — even the gentlest tap must
  /// produce a perceptible buzz, otherwise users think the mode is
  /// broken.
  final double minAmplitude01;

  /// Divisor applied to the raw drag velocity (px/s) before clamping
  /// into `[minAmplitude01, 1.0]`. Default 800 maps a brisk finger
  /// swipe (~700 px/s) just under full strength.
  final double velocityDivisor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final capsAsync = ref.watch(deviceCapabilitiesProvider);
    const required = {DeviceCapability.vibration};
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
        title: t.modeGoosebumps,
        missing: caps.missing(required),
      );
    }
    return _GoosebumpsModeView(
      hapticEngine: hapticEngine,
      hasAmplitude: caps.has(DeviceCapability.vibrationAmplitude),
      minAmplitude01: minAmplitude01,
      velocityDivisor: velocityDivisor,
    );
  }
}

class _GoosebumpsModeView extends StatefulWidget {
  const _GoosebumpsModeView({
    required this.hapticEngine,
    required this.hasAmplitude,
    required this.minAmplitude01,
    required this.velocityDivisor,
  });

  final HapticEngine? hapticEngine;
  final bool hasAmplitude;
  final double minAmplitude01;
  final double velocityDivisor;

  @override
  State<_GoosebumpsModeView> createState() => _GoosebumpsModeViewState();
}

class _GoosebumpsModeViewState extends State<_GoosebumpsModeView> {
  late final HapticEngine _engine;
  late final HapticPatternPlayer _player;
  bool _ownsEngine = false;

  Offset? _fingerPosition;
  DateTime? _lastUpdate;

  @override
  void initState() {
    super.initState();
    if (widget.hapticEngine == null) {
      _engine = const NullHapticEngine();
      _ownsEngine = true;
    } else {
      _engine = widget.hapticEngine!;
    }
    _player = HapticPatternPlayer(_engine);
  }

  @override
  void dispose() {
    unawaited(_player.stop());
    if (_ownsEngine) {
      unawaited(_engine.cancel());
    }
    super.dispose();
  }

  void _onPanStart(DragStartDetails d) {
    setState(() {
      _fingerPosition = d.localPosition;
      _lastUpdate = DateTime.now();
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    // Estimate velocity from the delta between updates. Using
    // d.delta / dt rather than relying on the gesture recognizer's
    // built-in velocity (which is only populated on PanEnd).
    final now = DateTime.now();
    final last = _lastUpdate ?? now;
    final dtMicros = now.difference(last).inMicroseconds;
    final dtSeconds = dtMicros <= 0 ? 1 / 60.0 : dtMicros / 1e6;
    final velocityPxPerSec = d.delta.distance / dtSeconds;
    setState(() {
      _fingerPosition = d.localPosition;
      _lastUpdate = now;
    });
    _emitHaptic(velocityPxPerSec);
  }

  void _onPanEnd(DragEndDetails _) {
    setState(() {
      _fingerPosition = null;
      _lastUpdate = null;
    });
  }

  void _emitHaptic(double velocityPxPerSec) {
    final HapticBeat beat;
    if (widget.hasAmplitude) {
      final amp01 = (velocityPxPerSec / widget.velocityDivisor)
          .clamp(widget.minAmplitude01, 1.0);
      beat = HapticBeat(
        duration: const Duration(milliseconds: 12),
        amplitude: (amp01 * 255).round().clamp(0, 255),
      );
    } else {
      // Fixed-amplitude fallback. Spec uses the leading beat of the
      // whisper pattern so the rhythm matches "soft arrival".
      beat = HapticPatterns.whisper.beats.first;
    }
    unawaited(_player.play(HapticPattern([beat])));
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
              child: RepaintBoundary(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  onPanCancel: () => _onPanEnd(DragEndDetails()),
                  child: CustomPaint(
                    painter: _GoosebumpsTrailPainter(
                      position: _fingerPosition,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  t.modeGoosebumpsHint,
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

/// Soft lavender glow centred on the most recent drag point. Renders
/// nothing when [position] is null so a static "no-finger" frame is
/// effectively free.
class _GoosebumpsTrailPainter extends CustomPainter {
  const _GoosebumpsTrailPainter({required this.position});

  final Offset? position;

  @override
  void paint(Canvas canvas, Size size) {
    final p = position;
    if (p == null) return;
    final radius = size.shortestSide * 0.22;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.pulse.withValues(alpha: 0.5),
          AppColors.pulse.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: p, radius: radius));
    canvas.drawCircle(p, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _GoosebumpsTrailPainter old) =>
      old.position != position;
}
