import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../capabilities/application/capability_providers.dart';
import '../../../capabilities/domain/device_capability.dart';
import '../../primitives/flashlight_controller.dart';
import '../../primitives/haptic_pattern_player.dart';
import '../../primitives/mic_level_stream.dart';
import 'unsupported_mode_screen.dart';

/// "Thunder" — clap to flash + buzz + paint a lightning bolt.
///
/// On every microphone sample whose `level01` exceeds [clapThreshold]
/// the screen fires the thunder event (subject to a [debounce] cooldown
/// so a single sustained clap doesn't trigger sixty times a second):
///
///   1. Pulse the device torch via [FlashlightController.pulse] — three
///      flashes at 80ms on / 60ms off.
///   2. Buzz three [HapticPatterns.tap] beats through the haptic
///      engine (best-effort: silent on devices with no vibrator).
///   3. Paint a single white-and-lavender lightning bolt overlay for
///      [boltDuration] inside a [RepaintBoundary] so the entire stack
///      stays clear of the surrounding screen's repaint set.
///
/// Disposal is centralised in [_ThunderModeViewState.dispose]: the mic
/// subscription is cancelled, the haptic player and flashlight are
/// asked to stop, and the bolt timer is cancelled before `super.dispose`.
class ThunderModeScreen extends ConsumerWidget {
  const ThunderModeScreen({
    super.key,
    this.micLevelStream,
    this.hapticEngine,
    this.flashlightController,
    this.clapThreshold = 0.85,
    this.debounce = const Duration(seconds: 1),
    this.boltDuration = const Duration(milliseconds: 250),
  });

  /// Optional injection. When null, the screen constructs a
  /// [FakeMicLevelStream] which never auto-emits — the production
  /// integration is the responsibility of a future PR.
  final MicLevelStream? micLevelStream;

  /// Optional haptic engine. Defaults to [NullHapticEngine] so a device
  /// with no vibrator stays silent (no crash, no fallback).
  final HapticEngine? hapticEngine;

  /// Optional flashlight controller. Defaults to a fresh
  /// [FlashlightController] backed by the no-op backend, which means
  /// the pulse short-circuits on devices that don't have a torch
  /// (matching the gate above).
  final FlashlightController? flashlightController;

  /// Normalized amplitude that counts as a "clap". A single tick above
  /// this threshold (after the debounce window) fires the event.
  final double clapThreshold;

  /// Minimum interval between two consecutive thunder events. Filters
  /// out chains of micro-claps inside a sustained loud noise.
  final Duration debounce;

  /// How long the lightning-bolt overlay stays painted.
  final Duration boltDuration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final capsAsync = ref.watch(deviceCapabilitiesProvider);
    const required = {
      DeviceCapability.microphone,
      DeviceCapability.flashlight,
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
        title: t.modeThunder,
        missing: caps.missing(required),
      );
    }
    return _ThunderModeView(
      micLevelStream: micLevelStream,
      hapticEngine: hapticEngine,
      flashlightController: flashlightController,
      clapThreshold: clapThreshold,
      debounce: debounce,
      boltDuration: boltDuration,
    );
  }
}

class _ThunderModeView extends StatefulWidget {
  const _ThunderModeView({
    required this.micLevelStream,
    required this.hapticEngine,
    required this.flashlightController,
    required this.clapThreshold,
    required this.debounce,
    required this.boltDuration,
  });

  final MicLevelStream? micLevelStream;
  final HapticEngine? hapticEngine;
  final FlashlightController? flashlightController;
  final double clapThreshold;
  final Duration debounce;
  final Duration boltDuration;

  @override
  State<_ThunderModeView> createState() => _ThunderModeViewState();
}

class _ThunderModeViewState extends State<_ThunderModeView> {
  late final MicLevelStream _mic;
  late final HapticEngine _engine;
  late final HapticPatternPlayer _player;
  late final FlashlightController _torch;
  StreamSubscription<MicLevel>? _sub;
  Timer? _boltTimer;

  bool _ownsMic = false;
  bool _ownsEngine = false;
  bool _ownsTorch = false;

  DateTime? _lastFired;
  bool _showBolt = false;

  /// Three-tap pattern. Built once in [initState] so we don't churn
  /// the constant pool every clap.
  late final HapticPattern _tapTriple;

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
    if (widget.flashlightController == null) {
      _torch = FlashlightController();
      _ownsTorch = true;
    } else {
      _torch = widget.flashlightController!;
    }
    _player = HapticPatternPlayer(_engine);
    _tapTriple = HapticPattern(
      List.filled(3, HapticPatterns.tap.beats.first),
    );
    _sub = _mic.levels.listen(_onLevel);
  }

  void _onLevel(MicLevel sample) {
    if (!mounted) return;
    if (sample.level01 <= widget.clapThreshold) return;
    final now = sample.timestamp;
    final last = _lastFired;
    if (last != null && now.difference(last) < widget.debounce) return;
    _lastFired = now;
    _fireThunder();
  }

  void _fireThunder() {
    setState(() => _showBolt = true);
    _boltTimer?.cancel();
    _boltTimer = Timer(widget.boltDuration, () {
      if (!mounted) return;
      setState(() => _showBolt = false);
    });
    // Fire-and-forget on all three side-effects. The flashlight pulse
    // and the haptic player are both cancel-safe — if the user exits
    // the mode mid-burst they tear down cleanly in [dispose].
    unawaited(_torch.pulse(
      const Duration(milliseconds: 80),
      const Duration(milliseconds: 60),
      3,
    ));
    unawaited(_player.play(_tapTriple));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _boltTimer?.cancel();
    unawaited(_player.stop());
    unawaited(_torch.off());
    if (_ownsMic) {
      unawaited(_mic.dispose());
    }
    if (_ownsEngine) {
      unawaited(_engine.cancel());
    }
    if (_ownsTorch) {
      // No explicit dispose on FlashlightController; off() above is
      // sufficient to drop the in-flight pulse train.
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
                child: CustomPaint(
                  painter: _ThunderBoltPainter(visible: _showBolt),
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  t.modeThunderHint,
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

/// Paints a single jagged lightning bolt (white core, lavender halo)
/// down the centre of the canvas when [visible] is true. Returns an
/// empty paint when invisible so the RepaintBoundary above can elide
/// the work.
class _ThunderBoltPainter extends CustomPainter {
  const _ThunderBoltPainter({required this.visible});

  final bool visible;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;
    final cx = size.width / 2;
    final h = size.height;
    // Five-segment zig-zag. Coordinates are normalised to size so the
    // bolt scales with the device.
    final path = Path()
      ..moveTo(cx + size.width * 0.04, h * 0.05)
      ..lineTo(cx - size.width * 0.06, h * 0.38)
      ..lineTo(cx + size.width * 0.02, h * 0.42)
      ..lineTo(cx - size.width * 0.08, h * 0.75)
      ..lineTo(cx + size.width * 0.05, h * 0.65)
      ..lineTo(cx - size.width * 0.02, h * 0.95);

    // Lavender halo first so the white core paints on top.
    final halo = Paint()
      ..color = const Color(0xFFB39CFF).withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawPath(path, halo);

    final core = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.drawPath(path, core);
  }

  @override
  bool shouldRepaint(covariant _ThunderBoltPainter old) =>
      old.visible != visible;
}
