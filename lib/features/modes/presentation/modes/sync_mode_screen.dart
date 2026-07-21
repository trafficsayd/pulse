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

/// "Sync" — a pulsing orb that both users try to synchronize. The orb
/// beats at a steady rhythm; each user taps their side to sync their
/// beat with the orb. When both taps land within a 200ms window, the
/// orb glows gold and a heart-beat haptic fires on both phones.
///
/// Visual: a central orb with two satellite dots (local + partner).
/// The satellites orbit the orb and flash when their owner taps.
class SyncModeScreen extends ConsumerStatefulWidget {
  const SyncModeScreen({super.key});

  @override
  ConsumerState<SyncModeScreen> createState() => _SyncModeScreenState();
}

class _SyncModeScreenState extends ConsumerState<SyncModeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _orbit;
  late final AnimationController _pulse;
  Timer? _beatTimer;
  DateTime? _localTapTime;
  DateTime? _partnerTapTime;
  bool _synced = false;
  StreamSubscription<ModeEvent>? _partnerSub;
  late final HapticPatternPlayer _player;

  @override
  void initState() {
    super.initState();
    _player = HapticPatternPlayer(ref.read(hapticEngineProvider));
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    // Steady beat every 2 seconds.
    _beatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      _pulse..reset()..forward();
      _checkSync();
    });
    _partnerSub = ref.read(modeEventBusProvider).incoming
        .where((e) => e.type == 'sync_tap')
        .listen(_onPartnerTap);
  }

  void _onPartnerTap(ModeEvent event) {
    if (!mounted) return;
    _partnerTapTime = DateTime.now();
    setState(() {});
    _checkSync();
  }

  Future<void> _onTap() async {
    HapticFeedback.lightImpact();
    _localTapTime = DateTime.now();
    setState(() {});
    _checkSync();
    await ref.read(modeEventBusProvider).send(const ModeEvent(type: 'sync_tap'));
  }

  void _checkSync() {
    final local = _localTapTime;
    final partner = _partnerTapTime;
    if (local == null || partner == null) return;
    final diff = (local.difference(partner)).inMilliseconds.abs();
    if (diff < 400 && !_synced) {
      setState(() => _synced = true);
      unawaited(_player.play(HapticPatterns.heartbeat));
      // Reset synced state after a beat.
      Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _synced = false);
      });
    }
  }

  @override
  void dispose() {
    _beatTimer?.cancel();
    _partnerSub?.cancel();
    _orbit.dispose();
    _pulse.dispose();
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
                onTap: _onTap,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_orbit, _pulse]),
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _SyncPainter(
                        orbit: _orbit.value,
                        pulse: _pulse.value,
                        synced: _synced,
                        localTapped: _localTapTime != null &&
                            DateTime.now().difference(_localTapTime!) <
                                const Duration(milliseconds: 800),
                        partnerTapped: _partnerTapTime != null &&
                            DateTime.now().difference(_partnerTapTime!) <
                                const Duration(milliseconds: 800),
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
                  t.modeSync,
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

class _SyncPainter extends CustomPainter {
  _SyncPainter({
    required this.orbit,
    required this.pulse,
    required this.synced,
    required this.localTapped,
    required this.partnerTapped,
  });

  final double orbit;
  final double pulse;
  final bool synced;
  final bool localTapped;
  final bool partnerTapped;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final baseRadius = size.shortestSide * 0.12;
    final pulseRadius = baseRadius + pulse * baseRadius * 0.6;
    final color = synced ? const Color(0xFFFFD86A) : AppColors.pulse;

    // Glow halo.
    final halo = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.2 + pulse * 0.3),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: pulseRadius * 3));
    canvas.drawCircle(center, pulseRadius * 3, halo);

    // Central orb.
    final orbPaint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, pulseRadius, orbPaint);

    // Orbit ring.
    final ringPaint = Paint()
      ..color = AppColors.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, baseRadius * 2.5, ringPaint);

    // Local satellite (left orbit).
    final localAngle = orbit * 2 * math.pi + math.pi;
    final localPos = center + Offset(math.cos(localAngle), math.sin(localAngle)) * baseRadius * 2.5;
    final localColor = localTapped ? AppColors.pulse : AppColors.pulse.withValues(alpha: 0.4);
    canvas.drawCircle(
      localPos,
      localTapped ? 14 : 10,
      Paint()..color = localColor,
    );

    // Partner satellite (right orbit, offset by pi).
    final partnerAngle = orbit * 2 * math.pi;
    final partnerPos = center + Offset(math.cos(partnerAngle), math.sin(partnerAngle)) * baseRadius * 2.5;
    final partnerColor = partnerTapped ? AppColors.heart : AppColors.heart.withValues(alpha: 0.4);
    canvas.drawCircle(
      partnerPos,
      partnerTapped ? 14 : 10,
      Paint()..color = partnerColor,
    );

    // Connection line when synced.
    if (synced) {
      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.5)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(localPos, partnerPos, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SyncPainter old) =>
      old.orbit != orbit ||
      old.pulse != pulse ||
      old.synced != synced ||
      old.localTapped != localTapped ||
      old.partnerTapped != partnerTapped;
}
