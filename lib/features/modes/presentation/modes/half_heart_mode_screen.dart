import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import '../../application/half_heart/heart_presence_controller.dart';
import '../../application/half_heart/heart_presence_models.dart';
import '../../application/half_heart/heart_presence_protocol.dart';
import '../../primitives/haptic_pattern_player.dart';
import '../../primitives/primitive_providers.dart';
import 'half_heart/heart_presence_painter.dart';

/// Two halves become one living heart only while both people are present and
/// continuously holding. Network keepalives protect the meaning from delayed
/// and duplicated packets without changing the legacy outer event names.
class HalfHeartModeScreen extends ConsumerStatefulWidget {
  const HalfHeartModeScreen({
    super.key,
    this.hapticEngine,
    this.now,
    this.idFactory,
  });

  final HapticEngine? hapticEngine;
  final DateTime Function()? now;
  final String Function()? idFactory;

  @override
  ConsumerState<HalfHeartModeScreen> createState() =>
      _HalfHeartModeScreenState();
}

class _HalfHeartModeScreenState extends ConsumerState<HalfHeartModeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _keepAliveInterval = Duration(milliseconds: 450);
  static const _remotePollInterval = Duration(milliseconds: 180);
  static const _heartbeatInterval = Duration(milliseconds: 980);
  static const _semanticHoldDuration = Duration(milliseconds: 1200);

  final GlobalKey _surfaceKey = GlobalKey();
  late final HeartPresenceController _presence;
  late final AnimationController _motion;
  late final HapticPatternPlayer _haptics;
  StreamSubscription<ModeEvent>? _partnerSub;
  Timer? _keepAlive;
  Timer? _remotePoll;
  Timer? _heartbeat;
  Timer? _semanticRelease;
  int? _activePointer;
  double _localStrength = .5;
  double _localX = .5;
  double _localY = .5;
  bool _wasMutual = false;

  int get _nowMs =>
      (widget.now?.call() ?? DateTime.now()).millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    const uuid = Uuid();
    _presence = HeartPresenceController(
      idFactory: widget.idFactory ?? () => uuid.v4(),
    );
    _haptics = HapticPatternPlayer(
      widget.hapticEngine ?? ref.read(hapticEngineProvider),
    );
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1220),
    )..repeat();
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
        .where(
          (event) => HeartPresenceProtocol.supportedTypes.contains(event.type),
        )
        .listen(_onPartnerSignal);
    _remotePoll = Timer.periodic(_remotePollInterval, (_) {
      if (!mounted) return;
      final before = _presence.partnerHeld;
      _presence.snapshot(_nowMs);
      if (before != _presence.partnerHeld) {
        _syncMutualHaptics();
        setState(() {});
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion && _motion.isAnimating) {
      _motion.stop();
      _motion.value = .35;
    } else if (!reduceMotion && !_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _endLocalHold();
  }

  void _onPartnerSignal(ModeEvent event) {
    if (!mounted) return;
    final nowMs = _nowMs;
    final signal = HeartPresenceProtocol.tryParse(event, receivedAtMs: nowMs);
    if (signal == null || !_presence.receive(signal, receivedAtMs: nowMs)) {
      return;
    }
    _syncMutualHaptics();
    setState(() {});
  }

  Future<void> _send(HeartHoldSignal signal) =>
      ref.read(modeEventBusProvider).send(HeartPresenceProtocol.encode(signal));

  void _beginLocalHold() {
    if (_presence.localHeld) return;
    final signal = _presence.beginLocal(
      nowMs: _nowMs,
      strength: _localStrength,
      x: _localX,
      y: _localY,
    );
    unawaited(_send(signal));
    unawaited(_haptics.play(HapticPatterns.tap));
    _keepAlive?.cancel();
    _keepAlive = Timer.periodic(_keepAliveInterval, (_) {
      if (!_presence.localHeld) return;
      unawaited(
        _send(
          _presence.keepLocalAlive(
            nowMs: _nowMs,
            strength: _localStrength,
            x: _localX,
            y: _localY,
          ),
        ),
      );
    });
    _syncMutualHaptics();
    setState(() {});
  }

  void _endLocalHold() {
    _keepAlive?.cancel();
    _keepAlive = null;
    final signal = _presence.endLocal(nowMs: _nowMs);
    if (signal != null) unawaited(_send(signal));
    _syncMutualHaptics();
    if (mounted) setState(() {});
  }

  void _syncMutualHaptics() {
    final mutual = _presence.snapshot(_nowMs).isMutual;
    if (mutual == _wasMutual) return;
    _wasMutual = mutual;
    _heartbeat?.cancel();
    _heartbeat = null;
    if (!mutual) {
      unawaited(_haptics.stop());
      return;
    }
    unawaited(_haptics.play(HapticPatterns.heartbeat));
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) {
      if (_presence.snapshot(_nowMs).isMutual) {
        unawaited(_haptics.play(HapticPatterns.heartbeat));
      } else {
        _syncMutualHaptics();
      }
    });
  }

  void _updateContact(PointerEvent event) {
    final box = _surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(event.position);
    _localX = (local.dx / box.size.width).clamp(0.0, 1.0).toDouble();
    _localY = (local.dy / box.size.height).clamp(0.0, 1.0).toDouble();
    final range = event.pressureMax - event.pressureMin;
    _localStrength = range >= .15
        ? ((event.pressure - event.pressureMin) / range)
            .clamp(.16, 1.0)
            .toDouble()
        : .5;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _updateContact(event);
    _beginLocalHold();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_activePointer != event.pointer) return;
    _updateContact(event);
  }

  void _onPointerEnd(PointerEvent event) {
    if (_activePointer != event.pointer) return;
    _activePointer = null;
    _endLocalHold();
  }

  void _semanticHold() {
    _semanticRelease?.cancel();
    _beginLocalHold();
    _semanticRelease = Timer(_semanticHoldDuration, _endLocalHold);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _partnerSub?.cancel();
    _keepAlive?.cancel();
    _remotePoll?.cancel();
    _heartbeat?.cancel();
    _semanticRelease?.cancel();
    final signal = _presence.endLocal(nowMs: _nowMs);
    if (signal != null) unawaited(_send(signal));
    unawaited(_haptics.stop());
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(child: _HeartBackdrop()),
            Positioned.fill(
              child: Semantics(
                label: t.halfHeartHint,
                button: true,
                onTap: _semanticHold,
                child: Listener(
                  key: const ValueKey('half-heart-touch-surface'),
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerEnd,
                  onPointerCancel: _onPointerEnd,
                  child: RepaintBoundary(
                    key: _surfaceKey,
                    child: AnimatedBuilder(
                      animation: _motion,
                      builder: (context, _) {
                        final snapshot = _presence.snapshot(_nowMs);
                        return CustomPaint(
                          key: ValueKey(
                            'half-heart-${snapshot.phase.name}',
                          ),
                          painter: HeartPresencePainter(
                            snapshot: snapshot,
                            phase: _motion.value,
                            reduceMotion: reduceMotion,
                          ),
                          size: Size.infinite,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 18,
              left: 24,
              right: 64,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.modeHalfHeart,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -.4,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t.halfHeartHint,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
                color: AppColors.textSecondary,
                tooltip: t.hubExit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeartBackdrop extends StatelessWidget {
  const _HeartBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -.08),
          radius: 1.05,
          colors: [
            AppColors.heart.withValues(alpha: .075),
            AppColors.pulse.withValues(alpha: .045),
            AppColors.background,
          ],
          stops: const [0, .46, 1],
        ),
      ),
    );
  }
}
