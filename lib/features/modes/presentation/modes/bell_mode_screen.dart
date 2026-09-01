import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/pulse_mockup.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../capabilities/application/capability_providers.dart';
import '../../../capabilities/domain/device_capability.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import '../../application/bell/bell_models.dart';
import '../../application/bell/bell_physics_engine.dart';
import '../../application/bell/bell_protocol.dart';
import '../../primitives/accelerometer_3d_stream.dart';
import '../../primitives/haptic_pattern_player.dart';
import '../../primitives/primitive_providers.dart';
import 'bell/bell_physical_painter.dart';

/// A material bell rather than a shake detector: body and clapper have
/// independent inertia, every strike carries its physical character to the
/// partner, and a drag gesture is a first-class fallback without sensors.
class BellModeScreen extends ConsumerStatefulWidget {
  const BellModeScreen({
    super.key,
    this.accelerometerStream,
    this.hapticEngine,
    this.physicsEngine,
    this.playSystemSound = true,
  });

  final Accelerometer3DStream? accelerometerStream;
  final HapticEngine? hapticEngine;
  final BellPhysicsEngine? physicsEngine;
  final bool playSystemSound;

  @override
  ConsumerState<BellModeScreen> createState() => _BellModeScreenState();
}

class _BellModeScreenState extends ConsumerState<BellModeScreen>
    with SingleTickerProviderStateMixin {
  late final BellPhysicsEngine _physics;
  late final HapticEngine _hapticEngine;
  late final HapticPatternPlayer _hapticPlayer;
  late final AnimationController _ticker;
  final BellStrikeDeduplicator _deduplicator = BellStrikeDeduplicator();

  StreamSubscription<Accel3>? _sensorSubscription;
  StreamSubscription<ModeEvent>? _partnerSubscription;
  Duration? _lastElapsed;
  DateTime? _lastSensorAt;
  double _lastTangential = 0;
  double _sensorDrive = 0;
  double _strikePulse = 0;
  bool _lastStrikeWasRemote = false;
  bool _sensorBound = false;
  int _gestureDirection = 1;
  int _suppressPhysicsStrikeUntilMs = 0;

  @override
  void initState() {
    super.initState();
    _physics = widget.physicsEngine ?? BellPhysicsEngine();
    _hapticEngine = widget.hapticEngine ?? ref.read(hapticEngineProvider);
    _hapticPlayer = HapticPatternPlayer(_hapticEngine);
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )
      ..addListener(_onFrame)
      ..repeat();
    _partnerSubscription = ref
        .read(modeEventBusProvider)
        .incoming
        .where((event) => event.type == BellProtocol.eventType)
        .listen(_onPartnerRing);
  }

  void _bindSensorIfNeeded(bool sensorAvailable) {
    if (_sensorBound || !sensorAvailable) return;
    _sensorBound = true;
    final stream =
        widget.accelerometerStream ?? ref.read(accelerometerStreamProvider);
    if (stream == null) {
      _sensorBound = false;
      return;
    }
    _sensorSubscription = stream.events.listen(
      _onSensorSample,
      onError: (_) {
        if (mounted) setState(() => _sensorBound = false);
      },
    );
  }

  void _onSensorSample(Accel3 sample) {
    if (!mounted) return;
    final tangential =
        ((sample.x + sample.y * .32) / 9.81).clamp(-2.6, 2.6).toDouble();
    final dt = _lastSensorAt == null
        ? 1 / 60
        : sample.timestamp
                .difference(_lastSensorAt!)
                .inMicroseconds
                .clamp(4000, 80000) /
            1000000;
    final jerk = (tangential - _lastTangential) / math.max(dt, .01);
    _lastTangential = tangential;
    _lastSensorAt = sample.timestamp;
    _sensorDrive = tangential;
    if (jerk.abs() > 7.5) {
      _physics.applyImpulse((jerk * .026).clamp(-3.8, 3.8).toDouble());
    }
  }

  void _onFrame() {
    if (!mounted) return;
    final elapsed = _ticker.lastElapsedDuration;
    if (elapsed == null) return;
    final previous = _lastElapsed;
    _lastElapsed = elapsed;
    if (previous == null) return;
    var delta = (elapsed - previous).inMicroseconds / 1000000;
    if (delta <= 0) delta = 1 / 60;
    _sensorDrive *= math.exp(-delta * 5.8);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final result = _physics.step(
      BellMotionInput(tangentialAcceleration: _sensorDrive),
      delta,
      nowMs: nowMs,
    );
    if (result.strike case final strike?
        when nowMs >= _suppressPhysicsStrikeUntilMs) {
      _handleStrike(strike, send: true);
    }
    _strikePulse = math.max(0, _strikePulse - delta * .82);
    setState(() {});
  }

  void _onPartnerRing(ModeEvent event) {
    final strike = BellProtocol.decode(event);
    if (strike == null || !_deduplicator.accept(strike.id)) return;
    _suppressPhysicsStrikeUntilMs =
        DateTime.now().millisecondsSinceEpoch + 1100;
    _physics.applyRemoteStrike(strike);
    _handleStrike(strike, send: false);
  }

  void _handleStrike(BellStrike strike, {required bool send}) {
    if (!mounted) return;
    setState(() {
      _strikePulse = math.max(_strikePulse, strike.strength);
      _lastStrikeWasRemote = strike.remote;
    });
    unawaited(_playFeedback(strike));
    if (send) {
      unawaited(
        ref.read(modeEventBusProvider).send(BellProtocol.encode(strike)),
      );
    }
  }

  Future<void> _playFeedback(BellStrike strike) async {
    if (widget.playSystemSound) {
      unawaited(SystemSound.play(
        strike.material == BellMaterial.crystal
            ? SystemSoundType.click
            : SystemSoundType.alert,
      ));
    }
    final p = BellMaterialProfile.forMaterial(strike.material);
    final contactAmplitude =
        (44 + strike.strength * 178 * p.hapticHardness).round().clamp(1, 255);
    final resonanceAmplitude =
        (18 + strike.strength * 74).round().clamp(1, 255);
    await _hapticPlayer.play(HapticPattern([
      HapticBeat(
        duration: Duration(milliseconds: 18 + (strike.strength * 28).round()),
        amplitude: contactAmplitude,
        gapAfter: Duration(milliseconds: 34 + ((1 - p.pitch) * 34).round()),
      ),
      HapticBeat(
        duration: Duration(milliseconds: 28 + (strike.strength * 48).round()),
        amplitude: resonanceAmplitude,
      ),
    ]));
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final impulse = (details.delta.dx * .022).clamp(-.75, .75).toDouble();
    if (impulse.abs() < .01) return;
    _gestureDirection = impulse.sign.toInt();
    _physics.applyImpulse(impulse);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    final direction = velocity.abs() < 40 ? _gestureDirection : velocity.sign;
    final impulse = direction * (1.8 + (velocity.abs() / 640).clamp(0, 3.4));
    _physics.applyImpulse(impulse.toDouble());
  }

  void _nudgeBell() {
    _gestureDirection *= -1;
    _physics.applyImpulse(_gestureDirection * 3.6);
  }

  void _selectMaterial(BellMaterial material) {
    if (_physics.material == material) return;
    setState(() => _physics.setMaterial(material));
    unawaited(HapticFeedback.selectionClick());
  }

  @override
  void dispose() {
    _sensorSubscription?.cancel();
    _partnerSubscription?.cancel();
    _ticker
      ..removeListener(_onFrame)
      ..dispose();
    unawaited(_hapticPlayer.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final copy = _BellCopy.of(context);
    final caps = ref.watch(deviceCapabilitiesProvider).asData?.value;
    final sensorAvailable = widget.accelerometerStream != null ||
        (caps?.has(DeviceCapability.accelerometer) ?? false);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _bindSensorIfNeeded(sensorAvailable),
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: PulseBackdrop(child: SizedBox())),
          Positioned.fill(
            child: Semantics(
              label: copy.bellSurface,
              button: true,
              onTap: _nudgeBell,
              child: GestureDetector(
                key: const ValueKey('bell-gesture-surface'),
                behavior: HitTestBehavior.opaque,
                onTap: _nudgeBell,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                child: AnimatedBuilder(
                  animation: _ticker,
                  builder: (context, _) => CustomPaint(
                    key: const ValueKey('physical-bell-renderer'),
                    painter: BellPhysicalPainter(
                      state: _physics.state,
                      material: _physics.material,
                      ambientProgress: _ticker.value,
                      strikePulse: _strikePulse,
                      remotePulse: _lastStrikeWasRemote,
                      reduceMotion: reduceMotion,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: PulseHeader(
                  title: t.modeBell,
                  trailing: PulseRoundButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(context).maybePop(),
                    subtle: true,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 70,
            left: 24,
            right: 24,
            child: IgnorePointer(
              child: Column(
                children: [
                  Text(
                    copy.subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.35,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    sensorAvailable ? t.bellHint : copy.fallbackHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 28,
            child: SafeArea(
              top: false,
              child: PulsePanel(
                radius: 26,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.graphic_eq_rounded,
                          size: 16,
                          color: Color(0xFFFFD071),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _lastStrikeWasRemote
                                ? copy.partnerRang
                                : copy.materialTitle,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${(_physics.state.resonance * 100).round()}%',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: BellMaterial.values.map((material) {
                        final selected = material == _physics.material;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Semantics(
                              selected: selected,
                              button: true,
                              child: Material(
                                color: selected
                                    ? const Color(0xFFFFD071)
                                        .withValues(alpha: .14)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(17),
                                child: InkWell(
                                  key: ValueKey(
                                    'bell-material-${material.name}',
                                  ),
                                  onTap: () => _selectMaterial(material),
                                  borderRadius: BorderRadius.circular(17),
                                  child: Container(
                                    height: 38,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(17),
                                      border: Border.all(
                                        color: selected
                                            ? const Color(0xFFFFD071)
                                                .withValues(alpha: .55)
                                            : AppColors.outlineSoft,
                                      ),
                                    ),
                                    child: Text(
                                      copy.material(material),
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: selected
                                            ? const Color(0xFFFFE3A1)
                                            : AppColors.textSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(growable: false),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BellCopy {
  const _BellCopy({required this.ru});

  factory _BellCopy.of(BuildContext context) =>
      _BellCopy(ru: Localizations.localeOf(context).languageCode == 'ru');

  final bool ru;

  String get subtitle =>
      ru ? 'Позвони ему через расстояние' : 'Ring it across the distance';
  String get fallbackHint => ru
      ? 'Проведи по колокольчику или коснись его'
      : 'Swipe across the bell or tap it';
  String get bellSurface => ru
      ? 'Физический колокольчик. Проведите, чтобы раскачать'
      : 'Physical bell. Swipe to swing';
  String get materialTitle => ru ? 'Характер звучания' : 'Sound character';
  String get partnerRang => ru ? 'Он позвонил тебе' : 'Your person rang you';

  String material(BellMaterial material) => switch (material) {
        BellMaterial.brass => ru ? 'Латунь' : 'Brass',
        BellMaterial.crystal => ru ? 'Хрусталь' : 'Crystal',
        BellMaterial.porcelain => ru ? 'Фарфор' : 'Porcelain',
      };
}
