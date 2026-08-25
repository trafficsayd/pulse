import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import '../../primitives/haptic_pattern_player.dart';
import '../../primitives/primitive_providers.dart';

/// "Goosebumps" — a rolling wave of goosebumps that travels across both
/// screens. One user taps to send a wave; both phones ripple and vibrate
/// in a rising-and-falling pattern.
///
/// Visual: a radial wave that expands from the tap point with a soft
/// purple gradient, fading at the edges. Haptic: [HapticPatterns.wave]
/// plays a 5-beat rising-then-falling surge.
class GoosebumpsModeScreen extends ConsumerStatefulWidget {
  const GoosebumpsModeScreen({super.key});

  @override
  ConsumerState<GoosebumpsModeScreen> createState() =>
      _GoosebumpsModeScreenState();
}

class _GoosebumpsModeScreenState extends ConsumerState<GoosebumpsModeScreen>
    with TickerProviderStateMixin {
  final List<_Wave> _waves = [];
  StreamSubscription<ModeEvent>? _partnerSub;
  late final HapticPatternPlayer _player;

  @override
  void initState() {
    super.initState();
    _player = HapticPatternPlayer(ref.read(hapticEngineProvider));
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
        .where((e) => e.type == 'goosebumps_wave')
        .listen(_onPartnerWave);
  }

  void _onPartnerWave(ModeEvent event) {
    if (!mounted) return;
    final x = (event.data['x'] as num?)?.toDouble() ?? 0.5;
    final y = (event.data['y'] as num?)?.toDouble() ?? 0.5;
    _addWave(Offset(x, y), isLocal: false);
    unawaited(_player.play(HapticPatterns.wave));
  }

  void _addWave(Offset normalizedPosition, {required bool isLocal}) {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    final wave = _Wave(
        position: normalizedPosition, controller: controller, isLocal: isLocal);
    setState(() => _waves.add(wave));
    controller.forward().whenComplete(() {
      if (!mounted) return;
      setState(() => _waves.remove(wave));
      controller.dispose();
    });
  }

  Future<void> _onTap(TapDownDetails details) async {
    final size = context.size;
    if (size == null) return;
    final normalized = Offset(
      details.localPosition.dx / size.width,
      details.localPosition.dy / size.height,
    );
    _addWave(normalized, isLocal: true);
    HapticFeedback.selectionClick();
    unawaited(_player.play(HapticPatterns.wave));
    await ref.read(modeEventBusProvider).send(ModeEvent(
          type: 'goosebumps_wave',
          data: {
            'x': normalized.dx,
            'y': normalized.dy,
          },
        ));
  }

  @override
  void dispose() {
    _partnerSub?.cancel();
    for (final w in _waves) {
      w.controller.dispose();
    }
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
                onTapDown: _onTap,
                child: CustomPaint(
                  painter: _GoosebumpsPainter(waves: _waves),
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  t.modeGoosebumps,
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

class _Wave {
  _Wave(
      {required this.position,
      required this.controller,
      required this.isLocal});
  final Offset position;
  final AnimationController controller;
  final bool isLocal;
}

class _GoosebumpsPainter extends CustomPainter {
  _GoosebumpsPainter({required this.waves})
      : super(
          repaint: Listenable.merge(
            waves.map((wave) => wave.controller).toList(growable: false),
          ),
        );
  final List<_Wave> waves;

  @override
  void paint(Canvas canvas, Size size) {
    for (final wave in waves) {
      final position = Offset(
        wave.position.dx * size.width,
        wave.position.dy * size.height,
      );
      final progress = wave.controller.value;
      final maxRadius = size.shortestSide * 0.7;
      // Three concentric rings expanding outward.
      for (var ring = 0; ring < 3; ring++) {
        final ringProgress = (progress - ring * 0.12).clamp(0.0, 1.0);
        if (ringProgress <= 0 || ringProgress >= 1) continue;
        final radius = ringProgress * maxRadius;
        final alpha = (1 - ringProgress) * 0.5;
        final color = wave.isLocal
            ? AppColors.pulse.withValues(alpha: alpha)
            : AppColors.heart.withValues(alpha: alpha);
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 - ringProgress * 2
          ..color = color
          ..isAntiAlias = true;
        canvas.drawCircle(position, radius, paint);
        // Tiny "bumps" along the ring for texture.
        const bumpCount = 24;
        final bumpPaint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        for (var i = 0; i < bumpCount; i++) {
          final theta = (i / bumpCount) * 2 * math.pi;
          final bumpR = radius + math.sin(ringProgress * 20 + i) * 3;
          final p = position + Offset(math.cos(theta), math.sin(theta)) * bumpR;
          canvas.drawCircle(p, 2.5 * (1 - ringProgress), bumpPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GoosebumpsPainter old) =>
      old.waves.length != waves.length;
}
