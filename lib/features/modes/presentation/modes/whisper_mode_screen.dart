import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../capabilities/application/capability_providers.dart';
import '../../../capabilities/domain/device_capability.dart';
import '../../primitives/haptic_pattern_player.dart';
import '../../primitives/mic_level_stream.dart';
import '../../primitives/primitive_providers.dart';
import 'unsupported_mode_screen.dart';

import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';

/// "Whisper" — radial waveform driven by [MicLevelStream.levels].
///
/// Subscribes to a [MicLevelStream] (Track C) and renders an animated
/// radial waveform sized by the live amplitude. When the normalized
/// level crosses 0.15 for two consecutive samples the screen fires
/// [HapticPatterns.whisper] through [HapticPatternPlayer] — the
/// "warm exhale" pulse Pulse's vocabulary uses for soft arrivals.
///
/// All disposal is centralised in [_WhisperModeViewState.dispose]: the
/// mic stream is released, the haptic engine cancelled, and the
/// animation controller stopped before [super.dispose].
class WhisperModeScreen extends ConsumerWidget {
  const WhisperModeScreen({
    super.key,
    this.micLevelStream,
    this.hapticEngine,
    this.threshold = 0.15,
    this.requiredConsecutive = 2,
  });

  /// Optional override. When null, the screen reads the real microphone
  /// via [micLevelStreamProvider] (backed by `package:record`).
  final MicLevelStream? micLevelStream;

  /// Optional override for the haptic engine. Tests pass in a
  /// [RecordingHapticEngine] to assert beats fired.
  final HapticEngine? hapticEngine;

  /// Amplitude that counts as "audible whisper". Values strictly above
  /// this threshold for [requiredConsecutive] consecutive samples
  /// trigger the haptic.
  final double threshold;

  /// How many consecutive samples must exceed [threshold]. Default 2 —
  /// a single noisy spike (a passing footstep) should not pulse the
  /// partner.
  final int requiredConsecutive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final capsAsync = ref.watch(deviceCapabilitiesProvider);
    const required = {
      DeviceCapability.microphone,
      DeviceCapability.vibration,
    };
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
        title: t.modeWhisper,
        missing: caps.missing(required),
      );
    }
    return _WhisperModeView(
      micLevelStream:
          micLevelStream ?? ref.watch(micLevelStreamProvider),
      hapticEngine: hapticEngine ?? ref.watch(hapticEngineProvider),
      threshold: threshold,
      requiredConsecutive: requiredConsecutive,
    );
  }
}

class _WhisperModeView extends ConsumerStatefulWidget {
  const _WhisperModeView({
    required this.micLevelStream,
    required this.hapticEngine,
    required this.threshold,
    required this.requiredConsecutive,
  });

  final MicLevelStream? micLevelStream;
  final HapticEngine? hapticEngine;
  final double threshold;
  final int requiredConsecutive;

  @override
  ConsumerState<_WhisperModeView> createState() => _WhisperModeViewState();
}

class _WhisperModeViewState extends ConsumerState<_WhisperModeView>
    with SingleTickerProviderStateMixin {
  late final MicLevelStream _mic;
  late final HapticEngine _engine;
  late final HapticPatternPlayer _player;
  StreamSubscription<MicLevel>? _sub;
  late final AnimationController _ambient;

  double _level = 0.0;
  StreamSubscription<ModeEvent>? _partnerSub;
  int _ticksOverThreshold = 0;
  bool _ownsMic = false;
  bool _ownsEngine = false;

  @override
  void initState() {
    super.initState();
    if (widget.micLevelStream == null) {
      _mic = FakeMicLevelStream();
      _ownsMic = true;
    } else {
      _mic = widget.micLevelStream!;
    }
    if (widget.hapticEngine == null) {
      _engine = const NullHapticEngine();
      _ownsEngine = true;
    } else {
      _engine = widget.hapticEngine!;
    }
    _player = HapticPatternPlayer(_engine);
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _sub = _mic.levels.listen(_onLevel);
    _partnerSub = ref.read(modeEventBusProvider).incoming
        .where((e) => e.type == 'whisper_level')
        .listen((e) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _onLevel(MicLevel sample) {
    if (!mounted) return;
    setState(() => _level = sample.level01);
    // Send mic level to partner.
    ref.read(modeEventBusProvider).send(
          ModeEvent(type: 'whisper_level', data: {'level': sample.level01}),
        );
    if (sample.level01 > widget.threshold) {
      _ticksOverThreshold++;
      if (_ticksOverThreshold == widget.requiredConsecutive) {
        // Fire-and-forget; haptic player handles cancellation if the
        // widget is unmounted mid-pattern.
        unawaited(_player.play(HapticPatterns.whisper));
      }
    } else {
      _ticksOverThreshold = 0;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _partnerSub?.cancel();
    _ambient.dispose();
    unawaited(_player.stop());
    if (_ownsMic) {
      unawaited(_mic.dispose());
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
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _ambient,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _RadialWaveformPainter(
                        level01: _level,
                        ambient: _ambient.value,
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
                  t.whisperHint,
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

class _RadialWaveformPainter extends CustomPainter {
  _RadialWaveformPainter({required this.level01, required this.ambient});

  final double level01;
  final double ambient;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final shortest = size.shortestSide;
    final baseRadius = shortest * 0.18;
    final amp = level01.clamp(0.0, 1.0);
    final outerRadius = baseRadius + amp * shortest * 0.32;

    // Soft halo — drifts with the ambient tick so the screen has life
    // even at perfect silence.
    final halo = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.pulse.withValues(alpha: 0.22 + amp * 0.4),
          AppColors.pulse.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(center: center, radius: outerRadius * 1.6),
      );
    canvas.drawCircle(center, outerRadius * 1.6, halo);

    // 24 radial spokes, length modulated by amplitude with a small
    // ambient breathing offset so silence isn't a frozen disk.
    const spokes = 24;
    final spokePaint = Paint()
      ..color = AppColors.pulse.withValues(alpha: 0.7)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    for (var i = 0; i < spokes; i++) {
      final theta = (i / spokes) * 2 * math.pi;
      final wobble = 0.04 * math.sin(ambient * 2 * math.pi + i * (math.pi / 3));
      final r1 = baseRadius * (0.92 + wobble);
      final r2 = outerRadius * (0.86 + wobble);
      final p1 = center + Offset(math.cos(theta), math.sin(theta)) * r1;
      final p2 = center + Offset(math.cos(theta), math.sin(theta)) * r2;
      canvas.drawLine(p1, p2, spokePaint);
    }

    // Inner ring keeps the form readable even at level==0.
    final inner = Paint()
      ..color = AppColors.pulse.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..isAntiAlias = true;
    canvas.drawCircle(center, baseRadius, inner);
  }

  @override
  bool shouldRepaint(covariant _RadialWaveformPainter old) =>
      old.level01 != level01 || old.ambient != ambient;
}
