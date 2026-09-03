import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/pulse_mockup.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../capabilities/application/capability_providers.dart';
import '../../../capabilities/domain/device_capability.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import '../../application/breath/shared_breath_controller.dart';
import '../../application/breath/shared_breath_models.dart';
import '../../application/breath/shared_breath_protocol.dart';
import '../../primitives/mic_level_stream.dart';
import '../../primitives/primitive_providers.dart';

/// A shared breathing space. The microphone is an enhancement, never a gate:
/// holding the surface provides the same private, audio-free experience.
class BreathModeScreen extends ConsumerWidget {
  const BreathModeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(deviceCapabilitiesProvider).valueOrNull;
    final hasMic = capabilities?.has(DeviceCapability.microphone) ?? false;
    return _BreathModeView(
      mic: hasMic ? ref.watch(micLevelStreamProvider) : null,
      hasMic: hasMic,
    );
  }
}

class _BreathModeView extends ConsumerStatefulWidget {
  const _BreathModeView({required this.mic, required this.hasMic});
  final MicLevelStream? mic;
  final bool hasMic;

  @override
  ConsumerState<_BreathModeView> createState() => _BreathModeViewState();
}

class _BreathModeViewState extends ConsumerState<_BreathModeView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final SharedBreathController _controller = SharedBreathController();
  final SharedBreathOrderGuard _order = SharedBreathOrderGuard();
  late final AnimationController _ticker;
  StreamSubscription<MicLevel>? _micSub;
  StreamSubscription<ModeEvent>? _partnerSub;
  Timer? _remoteDecay;
  DateTime? _lastSentAt;
  SharedBreathSample? _remote;
  double _microphoneLevel = 0;
  double _manualLevel = 0;
  double _lastRemoteHaptic = 0;
  bool _reduceMotion = false;
  bool _lifecyclePaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _subscribeToMicrophone();
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
        .where((event) => event.type == 'breath_level')
        .listen(_onPartner);
  }

  void _subscribeToMicrophone() {
    if (_lifecyclePaused || _micSub != null) return;
    _micSub = widget.mic?.levels.listen(_onMic);
  }

  @override
  void didUpdateWidget(covariant _BreathModeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mic == widget.mic) return;
    unawaited(_micSub?.cancel());
    _micSub = null;
    _subscribeToMicrophone();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (_reduceMotion || _lifecyclePaused) {
      _ticker.stop();
    } else if (!_ticker.isAnimating) {
      _ticker.repeat();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final paused = state != AppLifecycleState.resumed;
    if (_lifecyclePaused == paused) return;
    _lifecyclePaused = paused;
    if (paused) {
      unawaited(_micSub?.cancel());
      _micSub = null;
      _remoteDecay?.cancel();
      _ticker.stop();
      _manualLevel = 0;
      _microphoneLevel = 0;
      return;
    }
    _subscribeToMicrophone();
    if (!_reduceMotion && !_ticker.isAnimating) _ticker.repeat();
  }

  void _onMic(MicLevel sample) {
    if (!mounted || _lifecyclePaused) return;
    final breathLike = sample.level01 * (.35 + sample.noiseLikeness * .65);
    setState(() {
      _microphoneLevel += (breathLike - _microphoneLevel) * .28;
    });
    _sendIfDue(sample.timestamp.millisecondsSinceEpoch);
  }

  void _onPartner(ModeEvent event) {
    final value = SharedBreathProtocol.decode(event);
    if (value == null ||
        !_order.accept(value) ||
        !mounted ||
        _lifecyclePaused) {
      return;
    }
    setState(() => _remote = value);
    if (value.intensity > .45 && _lastRemoteHaptic <= .45) {
      unawaited(HapticFeedback.lightImpact());
    }
    _lastRemoteHaptic = value.intensity;
    _remoteDecay?.cancel();
    _remoteDecay = Timer(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      setState(() {
        _remote = null;
        _lastRemoteHaptic = 0;
      });
    });
  }

  void _sendIfDue(int nowMs, {bool force = false}) {
    final now = DateTime.fromMillisecondsSinceEpoch(nowMs);
    if (!force &&
        _lastSentAt != null &&
        now.difference(_lastSentAt!) < const Duration(milliseconds: 100)) {
      return;
    }
    _lastSentAt = now;
    final sample = _controller.sample(
      nowMs: nowMs,
      intensity: math.max(_manualLevel, _microphoneLevel),
      manual: _manualLevel > 0,
    );
    unawaited(
      ref.read(modeEventBusProvider).send(SharedBreathProtocol.encode(sample)),
    );
  }

  void _manualDown(PointerDownEvent event, Size size) {
    if (size.isEmpty) return;
    setState(() => _manualLevel = _manualIntensity(event.localPosition, size));
    _sendIfDue(DateTime.now().millisecondsSinceEpoch, force: true);
    unawaited(HapticFeedback.selectionClick());
  }

  void _manualMove(PointerMoveEvent event, Size size) {
    if (_manualLevel == 0 || size.isEmpty) return;
    setState(() => _manualLevel = _manualIntensity(event.localPosition, size));
    _sendIfDue(DateTime.now().millisecondsSinceEpoch);
  }

  void _manualUp() {
    if (_manualLevel == 0) return;
    setState(() => _manualLevel = 0);
    _sendIfDue(DateTime.now().millisecondsSinceEpoch, force: true);
  }

  double _manualIntensity(Offset position, Size size) {
    final vertical = 1 - (position.dy / size.height).clamp(0.0, 1.0);
    return (.32 + vertical * .55).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _micSub?.cancel();
    _partnerSub?.cancel();
    _remoteDecay?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final russian = Localizations.localeOf(context).languageCode == 'ru';
    final reduceMotion = _reduceMotion;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            children: [
              const Positioned.fill(child: PulseBackdrop(child: SizedBox())),
              Positioned.fill(
                child: Semantics(
                  label: russian
                      ? 'Удерживайте экран, чтобы поделиться дыханием'
                      : 'Hold the screen to share a breath',
                  button: true,
                  child: Listener(
                    key: const Key('breath-surface'),
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) => _manualDown(event, size),
                    onPointerMove: (event) => _manualMove(event, size),
                    onPointerUp: (_) => _manualUp(),
                    onPointerCancel: (_) => _manualUp(),
                    child: AnimatedBuilder(
                      animation: _ticker,
                      builder: (context, _) {
                        final local = _controller.sample(
                          nowMs: DateTime.now().millisecondsSinceEpoch,
                          intensity: math.max(_manualLevel, _microphoneLevel),
                          manual: _manualLevel > 0,
                          advanceSequence: false,
                        );
                        return CustomPaint(
                          painter: _SharedBreathPainter(
                            local: local,
                            remote: _remote,
                            coherence: _controller.coherence(local, _remote),
                            reduceMotion: reduceMotion,
                            russian: russian,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: PulseHeader(
                    title: t.modeBreath,
                    trailing: PulseRoundButton(
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).maybePop(),
                      subtle: true,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 32,
                child: IgnorePointer(
                  child: PulsePanel(
                    radius: 25,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          widget.hasMic
                              ? Icons.mic_none_rounded
                              : Icons.touch_app_rounded,
                          color: AppColors.pulse,
                          size: 18,
                        ),
                        const SizedBox(width: 9),
                        Flexible(
                          child: Text(
                            widget.hasMic
                                ? (russian
                                    ? 'Дышите или удерживайте поверхность'
                                    : 'Breathe or hold the surface')
                                : (russian
                                    ? 'Удерживайте поверхность — микрофон не нужен'
                                    : 'Hold the surface — no microphone needed'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SharedBreathPainter extends CustomPainter {
  const _SharedBreathPainter({
    required this.local,
    required this.remote,
    required this.coherence,
    required this.reduceMotion,
    required this.russian,
  });
  final SharedBreathSample local;
  final SharedBreathSample? remote;
  final double coherence;
  final bool reduceMotion;
  final bool russian;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final shortest = size.shortestSide;
    final localExpansion = _expansion(local);
    final remoteExpansion = remote == null ? .1 : _expansion(remote!);
    final separation = shortest * (.12 - coherence * .065);
    final localCenter = center.translate(-separation, 0);
    final remoteCenter = center.translate(separation, 0);
    final localRadius = shortest * (.17 + localExpansion * .17);
    final remoteRadius = shortest * (.17 + remoteExpansion * .17);

    final atmosphere = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.lerp(AppColors.pulse, AppColors.heart, coherence)!
              .withValues(alpha: .18 + coherence * .13),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(center: center, radius: shortest * .72),
      );
    canvas.drawCircle(center, shortest * .72, atmosphere);
    _orb(canvas, localCenter, localRadius, AppColors.pulse, local.intensity);
    _orb(
      canvas,
      remoteCenter,
      remoteRadius,
      AppColors.heart,
      remote?.intensity ?? 0,
    );

    if (remote != null) {
      final bridge = Paint()
        ..shader = LinearGradient(
          colors: [
            AppColors.pulse.withValues(alpha: coherence * .05),
            Colors.white.withValues(alpha: coherence * .28),
            AppColors.heart.withValues(alpha: coherence * .05),
          ],
        ).createShader(Rect.fromPoints(localCenter, remoteCenter))
        ..strokeWidth = 2 + coherence * 5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(localCenter, remoteCenter, bridge);
    }

    final phaseLabel = russian
        ? switch (local.phase) {
            SharedBreathPhase.inhale => 'ВДОХ',
            SharedBreathPhase.settle => 'ТИШИНА',
            SharedBreathPhase.exhale => 'ВЫДОХ',
            SharedBreathPhase.rest => 'ПАУЗА',
          }
        : switch (local.phase) {
            SharedBreathPhase.inhale => 'INHALE',
            SharedBreathPhase.settle => 'SETTLE',
            SharedBreathPhase.exhale => 'EXHALE',
            SharedBreathPhase.rest => 'REST',
          };
    final text = TextPainter(
      text: TextSpan(
        text: phaseLabel,
        style: TextStyle(
          color: Colors.white.withValues(alpha: .82),
          fontSize: 14,
          letterSpacing: 2.4,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, center.translate(-text.width / 2, shortest * .39));

    if (remote != null) {
      final sync = TextPainter(
        text: TextSpan(
          text: '${(coherence * 100).round()}%',
          style: TextStyle(
            color: AppColors.textSecondary.withValues(alpha: .75),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      sync.paint(canvas, center.translate(-sync.width / 2, shortest * .45));
    }
  }

  void _orb(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double intensity,
  ) {
    final halo = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: .23 + intensity * .23),
          color.withValues(alpha: .055),
          Colors.transparent,
        ],
        stops: const [0, .58, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.45));
    canvas.drawCircle(center, radius * 1.45, halo);
    final surface = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-.32, -.38),
        colors: [
          Colors.white.withValues(alpha: .19 + intensity * .12),
          color.withValues(alpha: .20 + intensity * .2),
          color.withValues(alpha: .035),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, surface);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: .44 + intensity * .25),
    );
  }

  double _expansion(SharedBreathSample value) {
    if (reduceMotion) return .55;
    return switch (value.phase) {
      SharedBreathPhase.inhale => value.phaseProgress,
      SharedBreathPhase.settle => 1,
      SharedBreathPhase.exhale => 1 - value.phaseProgress,
      SharedBreathPhase.rest => 0,
    };
  }

  @override
  bool shouldRepaint(covariant _SharedBreathPainter oldDelegate) => true;
}
