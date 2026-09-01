import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/pulse_mockup.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../haptics/infrastructure/platform_haptic_bridge.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import '../../application/tap_tap/knock_models.dart';
import '../../application/tap_tap/knock_protocol.dart';
import '../../application/tap_tap/knock_series_controller.dart';
import '../../application/tap_tap/touch_character_normalizer.dart';
import 'tap_tap/knock_surface_painter.dart';

class TapTapModeScreen extends ConsumerStatefulWidget {
  const TapTapModeScreen({super.key});

  @override
  ConsumerState<TapTapModeScreen> createState() => _TapTapModeScreenState();
}

class _TapTapModeScreenState extends ConsumerState<TapTapModeScreen>
    with SingleTickerProviderStateMixin {
  static const _uuid = Uuid();
  static const _haptics = PlatformHapticBridge();

  late final AnimationController _ticker;
  late final KnockSeriesController _series;
  final KnockDeduplicator _dedupe = KnockDeduplicator();
  final List<KnockVisualHit> _hits = [];
  final Set<Timer> _visualTimers = <Timer>{};
  StreamSubscription<ModeEvent>? _partnerSub;
  Timer? _seriesTimer;

  int? _downAtMs;
  Offset? _pressedPosition;
  double? _downSize;
  double? _downPressure;
  double? _pressureMin;
  double? _pressureMax;
  KnockHit? _lastLocal;
  String? _replyToSeriesId;
  KnockResonanceVisual? _resonance;

  @override
  void initState() {
    super.initState();
    _series = KnockSeriesController(idFactory: _uuid.v4);
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
        .where((event) => KnockProtocol.supportedTypes.contains(event.type))
        .listen(_onPartnerEvent);
  }

  void _onPointerDown(PointerDownEvent event) {
    setState(() {
      _downAtMs = DateTime.now().millisecondsSinceEpoch;
      _pressedPosition = event.localPosition;
      _downSize = event.size;
      _downPressure = event.pressure;
      _pressureMin = event.pressureMin;
      _pressureMax = event.pressureMax;
    });
  }

  void _onPointerCancel(PointerCancelEvent event) {
    setState(() {
      _downAtMs = null;
      _pressedPosition = null;
    });
  }

  Future<void> _onPointerUp(PointerUpEvent event, Size size) async {
    final started = _downAtMs;
    if (started == null || size.isEmpty) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final character = TouchCharacterNormalizer.normalize(
      TouchCharacterSample(
        durationMs: nowMs - started,
        contactSize: _normalizeContactSize(_downSize, size),
        pressure: _downPressure,
        pressureMin: _pressureMin,
        pressureMax: _pressureMax,
      ),
    );
    final isNewSeries = _series.shouldStartNew(nowMs);
    final replyTo = _replyToSeriesId;
    final hit = _series.add(
      nowMs: nowMs,
      x: event.localPosition.dx / size.width,
      y: event.localPosition.dy / size.height,
      character: character,
      replyToSeriesId: replyTo,
    );

    setState(() {
      _downAtMs = null;
      _pressedPosition = null;
      _lastLocal = hit;
      _hits.add(KnockVisualHit(
        hit: hit,
        createdAt: DateTime.now(),
        isLocal: true,
      ));
      if (replyTo != null) _replyToSeriesId = null;
    });
    _pruneLater(hit.id);
    if (replyTo != null) {
      unawaited(_haptics.playReply());
    } else {
      unawaited(_haptics.playKnock(character));
    }

    final bus = ref.read(modeEventBusProvider);
    if (isNewSeries) await bus.send(KnockProtocol.begin(hit.seriesId));
    await bus.send(KnockProtocol.hit(hit, reply: replyTo != null));
    _scheduleSeriesEnd();
  }

  double? _normalizeContactSize(double? raw, Size size) {
    if (raw == null || raw <= 0) return null;
    final reference = size.shortestSide * .12;
    return (raw / reference).clamp(0.0, 1.0).toDouble();
  }

  void _scheduleSeriesEnd() {
    _seriesTimer?.cancel();
    _seriesTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      final seriesId = _series.activeSeriesId;
      final count = _series.hitCount;
      if (seriesId == null) return;
      _series.end();
      unawaited(
        ref.read(modeEventBusProvider).send(KnockProtocol.end(seriesId, count)),
      );
    });
  }

  void _onPartnerEvent(ModeEvent event) {
    if (!mounted) return;
    final hit = KnockProtocol.tryParseHit(event);
    if (hit == null) return;
    if (event.type != 'tap' && !_dedupe.accept(hit.id)) return;
    final receivedAt = DateTime.now();
    final lastLocal = _lastLocal;
    setState(() {
      _hits.add(KnockVisualHit(
        hit: hit,
        createdAt: receivedAt,
        isLocal: false,
      ));
      _replyToSeriesId = hit.seriesId;
      if (event.type == 'knock_reply' && lastLocal != null) {
        _resonance = KnockResonanceVisual(
          from: Offset(lastLocal.x, lastLocal.y),
          to: Offset(hit.x, hit.y),
          createdAt: receivedAt,
        );
      }
    });
    _pruneLater(hit.id);
    if (event.type == 'knock_reply') {
      unawaited(_haptics.playReply());
    } else {
      unawaited(_haptics.playKnock(hit.character));
    }
    if (event.type != 'tap') {
      unawaited(
        ref
            .read(modeEventBusProvider)
            .send(KnockProtocol.receipt(hit.seriesId, hit.id)),
      );
    }
  }

  void _pruneLater(String id) {
    late final Timer timer;
    timer = Timer(const Duration(milliseconds: 1200), () {
      _visualTimers.remove(timer);
      if (!mounted) return;
      setState(() {
        _hits.removeWhere((visual) => visual.hit.id == id);
        final resonance = _resonance;
        if (resonance != null &&
            DateTime.now().difference(resonance.createdAt) >
                const Duration(milliseconds: 1250)) {
          _resonance = null;
        }
      });
    });
    _visualTimers.add(timer);
  }

  @override
  void dispose() {
    _seriesTimer?.cancel();
    for (final timer in _visualTimers) {
      timer.cancel();
    }
    _visualTimers.clear();
    _partnerSub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
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
                  label: t.tapTapSurfaceLabel,
                  button: true,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _onPointerDown,
                    onPointerUp: (event) => _onPointerUp(event, size),
                    onPointerCancel: _onPointerCancel,
                    child: AnimatedBuilder(
                      animation: _ticker,
                      builder: (context, _) => CustomPaint(
                        painter: KnockSurfacePainter(
                          hits: List.unmodifiable(_hits),
                          now: DateTime.now(),
                          ambientProgress: _ticker.value,
                          pressedPosition: _pressedPosition,
                          resonance: _scaledResonance(size),
                          reduceMotion: reduceMotion,
                        ),
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
                      title: t.modeTapTap,
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
                top: MediaQuery.paddingOf(context).top + 68,
                left: 30,
                right: 30,
                child: IgnorePointer(
                  child: Column(
                    children: [
                      Text(
                        t.tapTapSubtitle,
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
                        t.tapTapDescription,
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
                left: 24,
                right: 24,
                bottom: 34,
                child: IgnorePointer(
                  child: PulsePanel(
                    radius: 24,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 13,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _replyToSeriesId == null
                              ? Icons.touch_app_rounded
                              : Icons.reply_rounded,
                          size: 17,
                          color: _replyToSeriesId == null
                              ? AppColors.pulse
                              : AppColors.heart,
                        ),
                        const SizedBox(width: 9),
                        Flexible(
                          child: Text(
                            _replyToSeriesId == null
                                ? t.tapTapHint
                                : t.tapTapReplyHint,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
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

  KnockResonanceVisual? _scaledResonance(Size size) {
    final resonance = _resonance;
    if (resonance == null) return null;
    return KnockResonanceVisual(
      from: Offset(
        resonance.from.dx * size.width,
        resonance.from.dy * size.height,
      ),
      to: Offset(
        resonance.to.dx * size.width,
        resonance.to.dy * size.height,
      ),
      createdAt: resonance.createdAt,
    );
  }
}
