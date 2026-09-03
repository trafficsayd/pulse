import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../haptics/application/pulse_haptic_engine.dart';
import '../../../haptics/infrastructure/platform_haptic_bridge.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import '../../application/goosebumps/goosebumps_haptic_player.dart';
import '../../application/goosebumps/goosebumps_motion_engine.dart';
import '../../application/goosebumps/goosebumps_protocol.dart';
import '../../application/goosebumps/goosebumps_wave.dart';
import 'goosebumps/goosebumps_surface_painter.dart';

class GoosebumpsModeScreen extends ConsumerStatefulWidget {
  const GoosebumpsModeScreen({
    super.key,
    this.hapticEngine,
    this.now,
    this.idFactory,
  });

  final PulseHapticEngine? hapticEngine;
  final DateTime Function()? now;
  final String Function()? idFactory;

  @override
  ConsumerState<GoosebumpsModeScreen> createState() =>
      _GoosebumpsModeScreenState();
}

class _GoosebumpsModeScreenState extends ConsumerState<GoosebumpsModeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  late final GoosebumpsHapticPlayer _haptics;
  late final String Function() _idFactory;
  final GoosebumpsWaveDeduplicator _dedupe = GoosebumpsWaveDeduplicator();
  final List<GoosebumpsVisualWave> _waves = <GoosebumpsVisualWave>[];
  final List<GoosebumpsGestureSample> _samples = <GoosebumpsGestureSample>[];
  final List<Offset> _gesture = <Offset>[];
  final Set<Timer> _timers = <Timer>{};
  StreamSubscription<ModeEvent>? _partnerSub;
  int? _activePointer;
  GoosebumpsWave? _lastWave;
  bool _reduceMotion = false;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    const uuid = Uuid();
    _idFactory = widget.idFactory ?? uuid.v4;
    _haptics = GoosebumpsHapticPlayer(
      widget.hapticEngine ?? const PlatformHapticBridge(),
    );
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
        .where((event) => event.type == GoosebumpsProtocol.eventType)
        .listen(_onPartnerWave);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.maybeOf(context);
    final reduce =
        media?.disableAnimations == true || media?.accessibleNavigation == true;
    _reduceMotion = reduce;
    if (reduce) {
      _motion.stop();
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  void _onPointerDown(PointerDownEvent event, Size size) {
    if (_activePointer != null || size.isEmpty) return;
    _activePointer = event.pointer;
    _samples.clear();
    _gesture.clear();
    _record(event, size);
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent event, Size size) {
    if (_activePointer != event.pointer || size.isEmpty) return;
    final last = _gesture.isEmpty ? null : _gesture.last;
    if (last != null && (event.localPosition - last).distance < 2.5) return;
    _record(event, size);
    if (_samples.length > 48) {
      _samples.removeAt(1);
      _gesture.removeAt(1);
    }
    setState(() {});
  }

  Future<void> _onPointerUp(PointerUpEvent event, Size size) async {
    if (_activePointer != event.pointer || size.isEmpty) return;
    _record(event, size);
    final wave = GoosebumpsMotionEngine.fromGesture(
      id: _idFactory(),
      samples: List<GoosebumpsGestureSample>.of(_samples),
    );
    setState(() {
      _activePointer = null;
      _gesture.clear();
      _samples.clear();
      _lastWave = wave;
    });
    if (wave == null) return;
    _addWave(wave, isLocal: true, start: _now);
    unawaited(_haptics.play(wave));
    await ref.read(modeEventBusProvider).send(GoosebumpsProtocol.wave(wave));
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_activePointer != event.pointer) return;
    setState(() {
      _activePointer = null;
      _gesture.clear();
      _samples.clear();
    });
  }

  void _record(PointerEvent event, Size size) {
    final position = Offset(
      event.localPosition.dx.clamp(0.0, size.width),
      event.localPosition.dy.clamp(0.0, size.height),
    );
    _gesture.add(position);
    _samples.add(GoosebumpsGestureSample(
      x: position.dx / size.width,
      y: position.dy / size.height,
      timeMs: _now.millisecondsSinceEpoch,
      pressure: event.pressure,
      pressureMin: event.pressureMin,
      pressureMax: event.pressureMax,
    ));
  }

  void _onPartnerWave(ModeEvent event) {
    final wave = GoosebumpsProtocol.tryParse(
      event,
      nowMs: _now.millisecondsSinceEpoch,
    );
    if (wave == null || !mounted) return;
    if (GoosebumpsProtocol.isVersioned(event) && !_dedupe.accept(wave.id)) {
      return;
    }
    final clockAge = _now.millisecondsSinceEpoch - wave.createdAtMs;
    final trustedAge = clockAge.abs() <= 10000 ? math.max(0, clockAge) : 0;
    final delayMs = math.max(0, wave.handoffMs - trustedAge);
    late final Timer timer;
    timer = Timer(Duration(milliseconds: delayMs), () {
      _timers.remove(timer);
      if (!mounted) return;
      _addWave(wave, isLocal: false, start: _now);
      unawaited(_haptics.play(wave));
    });
    _timers.add(timer);
  }

  void _addWave(GoosebumpsWave wave,
      {required bool isLocal, required DateTime start}) {
    final visual = GoosebumpsVisualWave(
      wave: wave,
      startedAt: start,
      isLocal: isLocal,
    );
    setState(() => _waves.add(visual));
    late final Timer timer;
    timer = Timer(Duration(milliseconds: wave.travelMs + 120), () {
      _timers.remove(timer);
      if (!mounted) return;
      setState(() => _waves.remove(visual));
    });
    _timers.add(timer);
  }

  String _copy(BuildContext context, String ru, String en) =>
      Localizations.localeOf(context).languageCode == 'ru' ? ru : en;

  @override
  void dispose() {
    _partnerSub?.cancel();
    for (final timer in _timers) {
      timer.cancel();
    }
    _haptics.stop();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final wave = _lastWave;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: LayoutBuilder(builder: (context, constraints) {
                final size = constraints.biggest;
                return Semantics(
                  label: _copy(
                    context,
                    'Проведите пальцем, чтобы отправить тактильную волну',
                    'Swipe to send a tactile wave',
                  ),
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) => _onPointerDown(event, size),
                    onPointerMove: (event) => _onPointerMove(event, size),
                    onPointerUp: (event) => _onPointerUp(event, size),
                    onPointerCancel: _onPointerCancel,
                    child: CustomPaint(
                      painter: GoosebumpsSurfacePainter(
                        waves: _waves,
                        now: () => _now,
                        gesture: _gesture,
                        reduceMotion: _reduceMotion,
                        repaint: _motion,
                      ),
                    ),
                  ),
                );
              }),
            ),
            Positioned(
              top: 12,
              left: 20,
              right: 20,
              child: _Header(title: t.modeGoosebumps),
            ),
            Positioned(
              top: 4,
              right: 8,
              child: IconButton(
                tooltip: t.hubExit,
                color: AppColors.textSecondary,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 18,
              child: _GlassPanel(
                instruction: _copy(
                  context,
                  'Проведи по поверхности — волна продолжится у близкого',
                  'Swipe the surface — the wave continues on their phone',
                ),
                speed: wave?.speed,
                intensity: wave?.intensity,
                speedLabel: _copy(context, 'скорость', 'speed'),
                intensityLabel: _copy(context, 'сила', 'strength'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .055),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: .07)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: -.15,
              ),
            ),
          ),
        ),
      );
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.instruction,
    required this.speed,
    required this.intensity,
    required this.speedLabel,
    required this.intensityLabel,
  });

  final String instruction;
  final double? speed;
  final double? intensity;
  final String speedLabel;
  final String intensityLabel;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 15, 18, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF171725).withValues(alpha: .88),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: .09)),
          boxShadow: [
            BoxShadow(
              color: AppColors.pulse.withValues(alpha: .12),
              blurRadius: 32,
              spreadRadius: -8,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              instruction,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    icon: Icons.speed_rounded,
                    label: speedLabel,
                    value: speed ?? .18,
                    active: speed != null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Metric(
                    icon: Icons.graphic_eq_rounded,
                    label: intensityLabel,
                    value: intensity ?? .18,
                    active: intensity != null,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
  });

  final IconData icon;
  final String label;
  final double value;
  final bool active;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 3,
                    color:
                        active ? const Color(0xFFB995FF) : AppColors.textMuted,
                    backgroundColor: Colors.white.withValues(alpha: .055),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}
