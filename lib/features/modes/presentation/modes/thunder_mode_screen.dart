import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../capabilities/application/capability_providers.dart';
import '../../../capabilities/domain/device_capability.dart';
import '../../primitives/flashlight_controller.dart';
import '../../primitives/haptic_pattern_player.dart';
import '../../primitives/primitive_providers.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import 'unsupported_mode_screen.dart';

/// "Thunder" — tap to strike lightning. A jagged bolt flashes across both
/// screens, the torch pulses, and a deep rumble vibration plays.
///
/// Requires [DeviceCapability.flashlight] and [DeviceCapability.microphone]
/// (the latter for a thunder rumble audio cue in a future iteration; for
/// now the haptic rumble carries the effect).
class ThunderModeScreen extends ConsumerWidget {
  const ThunderModeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final capsAsync = ref.watch(deviceCapabilitiesProvider);
    const required = {DeviceCapability.flashlight};
    if (capsAsync.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.pulse)),
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
      flashlight: ref.watch(flashlightControllerProvider),
      hapticEngine: ref.watch(hapticEngineProvider),
    );
  }
}

class _ThunderModeView extends ConsumerStatefulWidget {
  const _ThunderModeView({required this.flashlight, required this.hapticEngine});

  final FlashlightController flashlight;
  final HapticEngine hapticEngine;

  @override
  ConsumerState<_ThunderModeView> createState() => _ThunderModeViewState();
}

class _ThunderModeViewState extends ConsumerState<_ThunderModeView>
    with SingleTickerProviderStateMixin {
  StreamSubscription<ModeEvent>? _partnerSub;
  late final AnimationController _bolt;
  List<Offset> _currentBolt = [];
  late final HapticPatternPlayer _player;

  @override
  void initState() {
    super.initState();
    _player = HapticPatternPlayer(widget.hapticEngine);
    _bolt = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _partnerSub = ref.read(modeEventBusProvider).incoming
        .where((e) => e.type == 'thunder_strike')
        .listen(_onPartnerStrike);
  }

  void _onPartnerStrike(ModeEvent event) {
    if (!mounted) return;
    final startX = (event.data['x'] as num?)?.toDouble() ?? 0.5;
    final size = context.size;
    if (size == null) return;
    _strike(Offset(startX * size.width, 0));
  }

  Future<void> _strike(Offset start) async {
    final size = context.size ?? const Size(400, 800);
    setState(() {
      _currentBolt = _generateBolt(start, size);
    });
    _bolt..reset()..forward();
    HapticFeedback.heavyImpact();
    // Flash the torch briefly.
    unawaited(widget.flashlight.pulse(
      const Duration(milliseconds: 120),
      const Duration(milliseconds: 60),
      2,
    ));
    unawaited(_player.play(HapticPatterns.rumble));
    await ref.read(modeEventBusProvider).send(ModeEvent(
      type: 'thunder_strike',
      data: {'x': start.dx / size.width},
    ));
  }

  /// Generate a jagged lightning bolt from [start] downward.
  List<Offset> _generateBolt(Offset start, Size size) {
    final points = <Offset>[start];
    final random = math.Random();
    var x = start.dx;
    var y = start.dy;
    final endY = size.height;
    while (y < endY) {
      y += 20 + random.nextInt(40);
      x += (random.nextDouble() - 0.5) * 80;
      x = x.clamp(0.0, size.width);
      points.add(Offset(x, y));
    }
    return points;
  }

  @override
  void dispose() {
    _partnerSub?.cancel();
    _bolt.dispose();
    unawaited(_player.stop());
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
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _strike(d.localPosition),
                child: AnimatedBuilder(
                  animation: _bolt,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _ThunderPainter(
                        bolt: _currentBolt,
                        progress: _bolt.value,
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
                  t.modeThunder,
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

class _ThunderPainter extends CustomPainter {
  _ThunderPainter({required this.bolt, required this.progress});

  final List<Offset> bolt;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (bolt.isEmpty || progress >= 1) return;
    final fade = (1 - progress).clamp(0.0, 1.0);

    // Screen flash overlay.
    final flashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15 * fade);
    canvas.drawRect(Offset.zero & size, flashPaint);

    // Bolt path.
    if (bolt.length < 2) return;
    final path = Path()..moveTo(bolt[0].dx, bolt[0].dy);
    for (var i = 1; i < bolt.length; i++) {
      path.lineTo(bolt[i].dx, bolt[i].dy);
    }

    // Outer glow.
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.pulse.withValues(alpha: 0.4 * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Main bolt.
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _ThunderPainter old) =>
      old.progress != progress || old.bolt.length != bolt.length;
}
