import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import '../../application/fireworks/firework_engine.dart';
import '../../application/fireworks/firework_protocol.dart';
import '../../primitives/haptic_pattern_player.dart';
import '../../primitives/primitive_providers.dart';
import 'fireworks/shared_fireworks_painter.dart';

/// A pair builds one show: individual launches stay personal, while a large
/// culmination exists only when two different people contribute together.
class FireworksModeScreen extends ConsumerStatefulWidget {
  const FireworksModeScreen({
    super.key,
    this.hapticEngine,
    this.now,
    this.idFactory,
    this.seedFactory,
    this.random,
  });

  final HapticEngine? hapticEngine;
  final DateTime Function()? now;
  final String Function()? idFactory;
  final int Function()? seedFactory;
  final math.Random? random;

  @override
  ConsumerState<FireworksModeScreen> createState() =>
      _FireworksModeScreenState();
}

class _FireworksModeScreenState extends ConsumerState<FireworksModeScreen>
    with SingleTickerProviderStateMixin {
  late final math.Random _random;
  late final String _localAuthorId;
  late final FireworkEngine _engine;
  late final HapticPatternPlayer _haptics;
  late final AnimationController _ticker;
  final Map<String, int> _activationById = {};
  final Set<String> _playedCulminations = {};
  StreamSubscription<ModeEvent>? _partnerSub;
  Size _surfaceSize = Size.zero;
  int _fallbackId = 0;
  int _legacyTick = 0;

  int get _nowMs =>
      (widget.now?.call() ?? DateTime.now()).millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _random = widget.random ?? math.Random();
    _localAuthorId =
        'fireworks-${_random.nextInt(0x7fffffff).toRadixString(16)}';
    _engine = FireworkEngine(localAuthorId: _localAuthorId);
    _haptics = HapticPatternPlayer(
      widget.hapticEngine ?? ref.read(hapticEngineProvider),
    );
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6400),
    )..repeat();
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
        .where((event) => event.type == FireworkProtocol.eventType)
        .listen(_onPartnerEvent);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _ticker.stop();
      _ticker.value = .36;
    } else if (!_ticker.isAnimating) {
      _ticker.repeat();
    }
  }

  void _onPartnerEvent(ModeEvent event) {
    if (!mounted) return;
    final receivedAt = _nowMs + _legacyTick++;
    final packet = FireworkProtocol.tryDecode(
      event,
      receivedAtMs: receivedAt,
    );
    if (packet == null) return;
    final before =
        _engine.snapshot.contributions.map((item) => item.id).toSet();
    if (_engine.merge(packet.records) == 0) return;
    final newest = packet.newest;
    if (!before.contains(newest.id)) {
      _activationById[newest.id] = receivedAt;
    }
    _pruneVisualHistory();
    _syncCulminations(triggerId: newest.id);
    setState(() {});
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_surfaceSize.isEmpty) return;
    if (event.localPosition.dy < 96 &&
        event.localPosition.dx > _surfaceSize.width - 70) {
      return;
    }
    _launchLocal(
      (event.localPosition.dx / _surfaceSize.width).clamp(0.0, 1.0).toDouble(),
      (event.localPosition.dy / _surfaceSize.height).clamp(0.0, 1.0).toDouble(),
    );
  }

  void _launchLocal(double x, double y) {
    final now = _nowMs;
    final snapshot = _engine.snapshot;
    String? replyTo;
    for (final item in snapshot.contributions.reversed) {
      final activatedAt = _activationById[item.id];
      if (item.authorId != _localAuthorId &&
          activatedAt != null &&
          now - activatedAt <= 5600) {
        replyTo = item.id;
        break;
      }
    }
    final seed = widget.seedFactory?.call() ?? _random.nextInt(0x7fffffff);
    final id =
        widget.idFactory?.call() ?? '$_localAuthorId-$now-${_fallbackId++}';
    final item = _engine.addLocal(
      id: id,
      x: x,
      y: y,
      authoredAtMs: now,
      seed: seed,
      palette: seed % SharedFireworksPainter.palettes.length,
      replyToId: replyTo,
    );
    _activationById[item.id] = now;
    _pruneVisualHistory();
    _syncCulminations(triggerId: item.id);
    setState(() {});
    unawaited(HapticFeedback.lightImpact());
    unawaited(
      ref.read(modeEventBusProvider).send(
            FireworkProtocol.encode(
              item,
              history: _engine.snapshot.contributions,
            ),
          ),
    );
  }

  void _syncCulminations({required String triggerId}) {
    for (final joint in _engine.snapshot.culminations) {
      final triggered =
          joint.firstId == triggerId || joint.secondId == triggerId;
      final bothActive = _activationById.containsKey(joint.firstId) &&
          _activationById.containsKey(joint.secondId);
      if (triggered && bothActive && _playedCulminations.add(joint.id)) {
        unawaited(_haptics.play(HapticPatterns.triple));
      }
    }
  }

  void _pruneVisualHistory() {
    final snapshot = _engine.snapshot;
    final retainedContributions =
        snapshot.contributions.map((item) => item.id).toSet();
    final retainedCulminations =
        snapshot.culminations.map((item) => item.id).toSet();
    _activationById.removeWhere(
      (id, _) => !retainedContributions.contains(id),
    );
    _playedCulminations.removeWhere(
      (id) => !retainedCulminations.contains(id),
    );
  }

  @override
  void dispose() {
    _partnerSub?.cancel();
    _ticker.dispose();
    unawaited(_haptics.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final snapshot = _engine.snapshot;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            _surfaceSize = constraints.biggest;
            return Listener(
              key: const ValueKey('fireworks-touch-surface'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPointerDown,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Semantics(
                      label: t.modeFireworks,
                      value: '${snapshot.contributions.length}',
                      button: true,
                      onTap: () => _launchLocal(.5, .34),
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _ticker,
                          builder: (context, _) => CustomPaint(
                            key: ValueKey(
                              'shared-fireworks-${snapshot.fingerprint}',
                            ),
                            painter: SharedFireworksPainter(
                              snapshot: snapshot,
                              localAuthorId: _localAuthorId,
                              activationById: Map.unmodifiable(_activationById),
                              frameNowMs: _nowMs,
                              ambientPhase: _ticker.value,
                              reduceMotion: reduceMotion,
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 13,
                    left: 16,
                    right: 16,
                    child: _FireworksIsland(
                      title: t.modeFireworks,
                      hasLocal: snapshot.contributions
                          .any((item) => item.authorId == _localAuthorId),
                      hasPartner: snapshot.contributions
                          .any((item) => item.authorId != _localAuthorId),
                      isJoint: snapshot.culminations.isNotEmpty,
                      tooltip: t.hubExit,
                      onClose: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FireworksIsland extends StatelessWidget {
  const _FireworksIsland({
    required this.title,
    required this.hasLocal,
    required this.hasPartner,
    required this.isJoint,
    required this.tooltip,
    required this.onClose,
  });

  final String title;
  final bool hasLocal;
  final bool hasPartner;
  final bool isJoint;
  final String tooltip;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xE80B0C14),
              borderRadius: BorderRadius.circular(23),
              border: Border.all(color: Colors.white.withValues(alpha: .045)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(17, 7, 7, 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -.2,
                        ),
                  ),
                  const SizedBox(width: 14),
                  _PresencePair(
                    hasLocal: hasLocal,
                    hasPartner: hasPartner,
                    isJoint: isJoint,
                  ),
                  const SizedBox(width: 11),
                  Tooltip(
                    message: tooltip,
                    child: Semantics(
                      label: tooltip,
                      button: true,
                      child: InkResponse(
                        key: const ValueKey('fireworks-close'),
                        radius: 22,
                        onTap: onClose,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: .065),
                          ),
                          child: CustomPaint(painter: _ClosePainter()),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PresencePair extends StatelessWidget {
  const _PresencePair({
    required this.hasLocal,
    required this.hasPartner,
    required this.isJoint,
  });

  final bool hasLocal;
  final bool hasPartner;
  final bool isJoint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 35,
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 3,
            child: _PresenceDot(
              color: const Color(0xFFC4B5FD),
              active: hasLocal,
            ),
          ),
          Positioned(
            right: 3,
            child: _PresenceDot(
              color: const Color(0xFFFF8AD8),
              active: hasPartner,
            ),
          ),
          if (isJoint)
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: .55),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PresenceDot extends StatelessWidget {
  const _PresenceDot({required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: active ? .92 : .12),
        border: Border.all(color: color.withValues(alpha: active ? .8 : .22)),
      ),
    );
  }
}

class _ClosePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textSecondary
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    final inset = size.width * .35;
    canvas.drawLine(
      Offset(inset, inset),
      Offset(size.width - inset, size.height - inset),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - inset, inset),
      Offset(inset, size.height - inset),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
