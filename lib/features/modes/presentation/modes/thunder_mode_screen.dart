import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import '../../application/thunder/thunder_audio_engine.dart';
import '../../application/thunder/thunder_choreography.dart';
import '../../application/thunder/thunder_flash_coordinator.dart';
import '../../application/thunder/thunder_models.dart';
import '../../application/thunder/thunder_protocol.dart';
import '../../primitives/flashlight_controller.dart';
import '../../primitives/haptic_pattern_player.dart';
import '../../primitives/primitive_providers.dart';
import 'thunder/storm_surface_painter.dart';

class ThunderModeScreen extends ConsumerWidget {
  const ThunderModeScreen({
    super.key,
    this.flashlight,
    this.hapticEngine,
    this.audioEngine,
    this.now,
    this.idFactory,
  });

  final FlashlightController? flashlight;
  final HapticEngine? hapticEngine;
  final ThunderAudioEngine? audioEngine;
  final DateTime Function()? now;
  final String Function()? idFactory;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _ThunderModeView(
        flashlight: flashlight ?? ref.watch(flashlightControllerProvider),
        hapticEngine: hapticEngine ?? ref.watch(hapticEngineProvider),
        audioEngine: audioEngine ?? const PlatformThunderAudioEngine(),
        now: now,
        idFactory: idFactory,
      );
}

class _ThunderModeView extends ConsumerStatefulWidget {
  const _ThunderModeView({
    required this.flashlight,
    required this.hapticEngine,
    required this.audioEngine,
    required this.now,
    required this.idFactory,
  });

  final FlashlightController flashlight;
  final HapticEngine hapticEngine;
  final ThunderAudioEngine audioEngine;
  final DateTime Function()? now;
  final String Function()? idFactory;

  @override
  ConsumerState<_ThunderModeView> createState() => _ThunderModeViewState();
}

class _ThunderModeViewState extends ConsumerState<_ThunderModeView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion;
  late final ThunderFlashCoordinator _flash;
  late final String Function() _idFactory;
  final ThunderStrikeDeduplicator _dedupe = ThunderStrikeDeduplicator();
  final List<ThunderVisualStrike> _strikes = <ThunderVisualStrike>[];
  final List<ThunderGestureSample> _samples = <ThunderGestureSample>[];
  final List<Offset> _gesture = <Offset>[];
  final Set<Timer> _timers = <Timer>{};
  StreamSubscription<ModeEvent>? _partnerSub;
  int? _activePointer;
  int _lastLocalStrikeMs = -100000;
  bool _reduceMotion = false;
  bool _lifecycleActive = true;
  ThunderStrike? _lastStrike;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    const uuid = Uuid();
    _idFactory = widget.idFactory ?? uuid.v4;
    _flash = ThunderFlashCoordinator(widget.flashlight);
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
        .where((event) => event.type == ThunderProtocol.eventType)
        .listen(_onPartnerStrike);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lifecycleActive = true;
      return;
    }
    _lifecycleActive = false;
    _cancelPendingEffects();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.maybeOf(context);
    _reduceMotion =
        media?.disableAnimations == true || media?.accessibleNavigation == true;
  }

  void _onPointerDown(PointerDownEvent event, Size size) {
    if (!_lifecycleActive || _activePointer != null || size.isEmpty) return;
    _activePointer = event.pointer;
    _samples.clear();
    _gesture.clear();
    _record(event, size);
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent event, Size size) {
    if (_activePointer != event.pointer || size.isEmpty) return;
    if (_gesture.isNotEmpty &&
        (event.localPosition - _gesture.last).distance < 3) {
      return;
    }
    _record(event, size);
    if (_samples.length > 44) {
      _samples.removeAt(1);
      _gesture.removeAt(1);
    }
    setState(() {});
  }

  Future<void> _onPointerUp(PointerUpEvent event, Size size) async {
    if (_activePointer != event.pointer || size.isEmpty) return;
    _record(event, size);
    final nowMs = _now.millisecondsSinceEpoch;
    final id = _idFactory();
    final strike = ThunderChoreography.fromGesture(
      id: id,
      seed: id.hashCode & 0x7fffffff,
      samples: List<ThunderGestureSample>.of(_samples),
    );
    setState(() {
      _activePointer = null;
      _gesture.clear();
      _samples.clear();
    });
    if (strike == null || nowMs - _lastLocalStrikeMs < 700) return;
    _lastLocalStrikeMs = nowMs;
    setState(() => _lastStrike = strike);
    _playStrike(strike, isLocal: true);
    await ref.read(modeEventBusProvider).send(ThunderProtocol.strike(strike));
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_activePointer != event.pointer) return;
    setState(() {
      _activePointer = null;
      _samples.clear();
      _gesture.clear();
    });
  }

  void _record(PointerEvent event, Size size) {
    final position = Offset(
      event.localPosition.dx.clamp(0.0, size.width),
      event.localPosition.dy.clamp(0.0, size.height),
    );
    _gesture.add(position);
    _samples.add(ThunderGestureSample(
      x: position.dx / size.width,
      y: position.dy / size.height,
      timeMs: _now.millisecondsSinceEpoch,
      pressure: event.pressure,
      pressureMin: event.pressureMin,
      pressureMax: event.pressureMax,
    ));
  }

  void _onPartnerStrike(ModeEvent event) {
    final strike = ThunderProtocol.tryParse(
      event,
      nowMs: _now.millisecondsSinceEpoch,
    );
    if (strike == null || !mounted) return;
    if (ThunderProtocol.isVersioned(event) && !_dedupe.accept(strike.id)) {
      return;
    }
    if (!_lifecycleActive) return;
    final clockAge = _now.millisecondsSinceEpoch - strike.createdAtMs;
    final trustedAge = clockAge.abs() <= 10000 ? math.max(0, clockAge) : 0;
    final delay = math.max(0, strike.handoffMs - trustedAge);
    _schedule(delay, () {
      if (!mounted) return;
      setState(() => _lastStrike = strike);
      _playStrike(strike, isLocal: false);
    });
  }

  void _playStrike(ThunderStrike strike, {required bool isLocal}) {
    if (!_lifecycleActive) return;
    final cues = ThunderChoreography.cues(
      strike,
      reduceMotion: _reduceMotion,
    );
    final visual = ThunderVisualStrike(
      strike: strike,
      geometry: ThunderChoreography.geometry(strike, remote: !isLocal),
      startedAt: _now,
      isLocal: isLocal,
    );
    setState(() => _strikes.add(visual));

    _schedule(cues.flashDelayMs, () {
      unawaited(_flash.pulse(
        onMs: cues.flashOnMs,
        gapMs: cues.flashGapMs,
        count: cues.flashCount,
      ));
    });
    _schedule(cues.impactDelayMs, () {
      unawaited(widget.hapticEngine.playBeat(HapticBeat(
        duration: Duration(milliseconds: 68 + (strike.intensity * 92).round()),
        amplitude: cues.hapticAmplitude,
      )));
    });
    _schedule(cues.impactDelayMs + 115, () {
      unawaited(widget.hapticEngine.playBeat(HapticBeat(
        duration: const Duration(milliseconds: 92),
        amplitude: (cues.hapticAmplitude * .62).round(),
      )));
    });
    _schedule(cues.rumbleDelayMs, () {
      unawaited(widget.audioEngine.play(
        strike,
        durationMs: cues.rumbleDurationMs,
      ));
    });
    _schedule(cues.totalDurationMs + 260, () {
      if (mounted) setState(() => _strikes.remove(visual));
    });
  }

  void _schedule(int delayMs, void Function() action) {
    late final Timer timer;
    timer = Timer(Duration(milliseconds: delayMs), () {
      _timers.remove(timer);
      if (_lifecycleActive) action();
    });
    _timers.add(timer);
  }

  void _cancelPendingEffects() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    _activePointer = null;
    _samples.clear();
    _gesture.clear();
    if (mounted) setState(_strikes.clear);
    unawaited(_flash.stop());
    unawaited(widget.hapticEngine.cancel());
    unawaited(widget.audioEngine.stop());
  }

  String _copy(BuildContext context, String ru, String en) =>
      Localizations.localeOf(context).languageCode == 'ru' ? ru : en;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _partnerSub?.cancel();
    for (final timer in _timers) {
      timer.cancel();
    }
    unawaited(_flash.dispose());
    unawaited(widget.hapticEngine.cancel());
    unawaited(widget.audioEngine.stop());
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final last = _lastStrike;
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
                    'Проведите пальцем, чтобы создать гром',
                    'Swipe to create thunder',
                  ),
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) => _onPointerDown(event, size),
                    onPointerMove: (event) => _onPointerMove(event, size),
                    onPointerUp: (event) => _onPointerUp(event, size),
                    onPointerCancel: _onPointerCancel,
                    child: CustomPaint(
                      painter: StormSurfacePainter(
                        strikes: _strikes,
                        gesture: _gesture,
                        now: () => _now,
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
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .055),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .07),
                    ),
                  ),
                  child: Text(
                    t.modeThunder,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
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
              child: _StormPanel(
                instruction: _copy(
                  context,
                  'Проведи — свет, удар и раскат продолжатся у близкого',
                  'Swipe — light, impact and rumble continue on their phone',
                ),
                intensity: last?.intensity,
                velocity: last?.velocity,
                strengthLabel: _copy(context, 'сила', 'strength'),
                speedLabel: _copy(context, 'скорость', 'speed'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StormPanel extends StatelessWidget {
  const _StormPanel({
    required this.instruction,
    required this.intensity,
    required this.velocity,
    required this.strengthLabel,
    required this.speedLabel,
  });

  final String instruction;
  final double? intensity;
  final double? velocity;
  final String strengthLabel;
  final String speedLabel;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 15, 18, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF151623).withValues(alpha: .9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: .085)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6960FF).withValues(alpha: .13),
              blurRadius: 30,
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
            Row(children: [
              Expanded(
                child: _Meter(
                  icon: Icons.graphic_eq_rounded,
                  label: strengthLabel,
                  value: intensity,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _Meter(
                  icon: Icons.speed_rounded,
                  label: speedLabel,
                  value: velocity,
                ),
              ),
            ]),
          ],
        ),
      );
}

class _Meter extends StatelessWidget {
  const _Meter({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: value ?? .18,
                  minHeight: 3,
                  color: value == null
                      ? AppColors.textMuted
                      : const Color(0xFFA9A2FF),
                  backgroundColor: Colors.white.withValues(alpha: .055),
                ),
              ),
            ],
          ),
        ),
      ]);
}
