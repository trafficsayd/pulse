import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import '../../application/sandbox/sand_haptics.dart';
import '../../application/sandbox/sand_models.dart';
import '../../application/sandbox/sand_protocol.dart';
import '../../application/sandbox/sand_simulation.dart';
import '../../primitives/haptic_pattern_player.dart';
import '../../primitives/primitive_providers.dart';
import 'sandbox/sand_world_painter.dart';

class SandboxModeScreen extends ConsumerStatefulWidget {
  const SandboxModeScreen({
    super.key,
    this.hapticEngine,
    this.now,
    this.idFactory,
  });

  final HapticEngine? hapticEngine;
  final DateTime Function()? now;
  final String Function()? idFactory;

  @override
  ConsumerState<SandboxModeScreen> createState() => _SandboxModeScreenState();
}

class _SandboxModeScreenState extends ConsumerState<SandboxModeScreen> {
  late final SandSimulation _simulation;
  late final HapticEngine _haptics;
  late final String Function() _idFactory;
  final SandCommandDeduplicator _dedupe = SandCommandDeduplicator();
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  final List<Offset> _localGesture = <Offset>[];
  final List<SandPoint> _pendingPoints = <SandPoint>[];
  final List<SandRemoteTrace> _remoteTraces = <SandRemoteTrace>[];
  StreamSubscription<ModeEvent>? _partnerSub;
  Timer? _physicsTimer;
  int? _activePointer;
  Size _canvasSize = Size.zero;
  SandTool _tool = SandTool.paint;
  SandMaterial _material = SandMaterial.amethyst;
  bool _reduceMotion = false;
  int _lastFlushMs = -100000;
  int _lastSampleMs = -100000;
  int _lastHapticMs = -100000;
  double _lastVelocity = .35;
  double? _lastPressure;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    const uuid = Uuid();
    _idFactory = widget.idFactory ?? uuid.v4;
    _haptics = widget.hapticEngine ?? ref.read(hapticEngineProvider);
    _simulation = SandSimulation();
    _physicsTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      var changed = false;
      final stepsPerFrame = _reduceMotion ? 2 : 3;
      for (var step = 0; step < stepsPerFrame; step++) {
        changed = _simulation.tick(
              maxMoves: _reduceMotion ? 420 : 640,
            ) ||
            changed;
      }
      if (changed) _notifyPaint();
    });
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
        .where((event) => event.type == SandProtocol.eventType)
        .listen(_onPartnerCommand);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.maybeOf(context);
    _reduceMotion =
        media?.disableAnimations == true || media?.accessibleNavigation == true;
  }

  void _onPointerDown(PointerDownEvent event, Size size) {
    if (_activePointer != null || size.isEmpty) return;
    _activePointer = event.pointer;
    _canvasSize = size;
    _localGesture.clear();
    _pendingPoints.clear();
    _lastSampleMs = _now.millisecondsSinceEpoch;
    _record(event);
    _notifyPaint();
  }

  void _onPointerMove(PointerMoveEvent event, Size size) {
    if (_activePointer != event.pointer || size.isEmpty) return;
    _canvasSize = size;
    final nowMs = _now.millisecondsSinceEpoch;
    final elapsed = math.max(1, nowMs - _lastSampleMs);
    final normalizedDistance = event.delta.distance / size.shortestSide;
    _lastVelocity =
        (normalizedDistance * 1000 / elapsed / 1.5).clamp(0.0, 1.0).toDouble();
    _lastSampleMs = nowMs;
    _record(event);
    final interval = _tool == SandTool.pour ? 140 : 80;
    if (_pendingPoints.length >= SandCommand.maxPoints ||
        nowMs - _lastFlushMs >= interval) {
      unawaited(_flush());
    }
    _notifyPaint();
  }

  Future<void> _onPointerUp(PointerUpEvent event, Size size) async {
    if (_activePointer != event.pointer || size.isEmpty) return;
    _canvasSize = size;
    _record(event);
    await _flush();
    _activePointer = null;
    _localGesture.clear();
    _pendingPoints.clear();
    _notifyPaint();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_activePointer != event.pointer) return;
    _activePointer = null;
    _localGesture.clear();
    _pendingPoints.clear();
    _notifyPaint();
  }

  void _record(PointerEvent event) {
    if (_canvasSize.isEmpty) return;
    final point = Offset(
      event.localPosition.dx.clamp(0.0, _canvasSize.width),
      event.localPosition.dy.clamp(0.0, _canvasSize.height),
    );
    if (_localGesture.isEmpty || (point - _localGesture.last).distance >= 2) {
      _localGesture.add(point);
    }
    final normalized = SandPoint(
      point.dx / _canvasSize.width,
      point.dy / _canvasSize.height,
    );
    if (_pendingPoints.isEmpty ||
        (normalized.x - _pendingPoints.last.x).abs() +
                (normalized.y - _pendingPoints.last.y).abs() >
            .004) {
      _pendingPoints.add(normalized);
    }
    final min = event.pressureMin;
    final max = event.pressureMax;
    _lastPressure = max - min >= .05
        ? ((event.pressure - min) / (max - min)).clamp(0.0, 1.0)
        : null;
  }

  Future<void> _flush() async {
    if (_pendingPoints.isEmpty) return;
    final nowMs = _now.millisecondsSinceEpoch;
    final id = _idFactory();
    final intensity = (_lastPressure ?? (.3 + _lastVelocity * .62))
        .clamp(.12, 1.0)
        .toDouble();
    final command = SandCommand(
      id: id,
      createdAtMs: nowMs,
      tool: _tool,
      material: _material,
      points: List<SandPoint>.unmodifiable(
        _pendingPoints.take(SandCommand.maxPoints),
      ),
      intensity: intensity,
      seed: id.hashCode & 0x7fffffff,
    );
    _pendingPoints.clear();
    _lastFlushMs = nowMs;
    if (!_simulation.enqueue(command)) return;
    _playHaptic(command, remote: false);
    _notifyPaint();
    await ref.read(modeEventBusProvider).send(SandProtocol.command(command));
  }

  void _onPartnerCommand(ModeEvent event) {
    final command = SandProtocol.tryParse(
      event,
      nowMs: _now.millisecondsSinceEpoch,
    );
    if (command == null || !mounted) return;
    if (SandProtocol.isVersioned(event) && !_dedupe.accept(command.id)) return;
    if (!_simulation.enqueue(command)) return;
    _remoteTraces.add(SandRemoteTrace(command: command, createdAt: _now));
    if (_remoteTraces.length > 8) _remoteTraces.removeAt(0);
    _playHaptic(command, remote: true);
    _notifyPaint();
  }

  void _playHaptic(SandCommand command, {required bool remote}) {
    final nowMs = _now.millisecondsSinceEpoch;
    if (nowMs - _lastHapticMs < 90) return;
    _lastHapticMs = nowMs;
    unawaited(_haptics.playBeat(SandHaptics.beatFor(command, remote: remote)));
  }

  void _notifyPaint() {
    if (!mounted) return;
    _repaint.value++;
  }

  void _selectTool(SandTool tool) {
    setState(() => _tool = tool);
    unawaited(_haptics.playBeat(const HapticBeat(
      duration: Duration(milliseconds: 22),
      amplitude: 52,
    )));
  }

  String _copy(BuildContext context, String ru, String en) =>
      Localizations.localeOf(context).languageCode == 'ru' ? ru : en;

  @override
  void dispose() {
    _physicsTimer?.cancel();
    _partnerSub?.cancel();
    unawaited(_haptics.cancel());
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(children: [
          Positioned.fill(
            child: LayoutBuilder(builder: (context, constraints) {
              final size = constraints.biggest;
              _canvasSize = size;
              return Semantics(
                label: _copy(
                  context,
                  'Общий тактильный мир из песка',
                  'Shared tactile world made of sand',
                ),
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) => _onPointerDown(event, size),
                  onPointerMove: (event) => _onPointerMove(event, size),
                  onPointerUp: (event) => _onPointerUp(event, size),
                  onPointerCancel: _onPointerCancel,
                  child: CustomPaint(
                    painter: SandWorldPainter(
                      world: _simulation.world,
                      localGesture: _localGesture,
                      remoteTraces: _remoteTraces,
                      now: () => _now,
                      reduceMotion: _reduceMotion,
                      repaint: _repaint,
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
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .07)),
                ),
                child: Text(t.modeSandbox,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    )),
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
            left: 14,
            right: 14,
            bottom: 14,
            child: _SandboxToolbar(
              tool: _tool,
              material: _material,
              onTool: _selectTool,
              onMaterial: (material) => setState(() => _material = material),
              paintLabel: _copy(context, 'Рисовать', 'Paint'),
              pourLabel: _copy(context, 'Пересыпать', 'Pour'),
              eraseLabel: _copy(context, 'Стереть', 'Erase'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SandboxToolbar extends StatelessWidget {
  const _SandboxToolbar({
    required this.tool,
    required this.material,
    required this.onTool,
    required this.onMaterial,
    required this.paintLabel,
    required this.pourLabel,
    required this.eraseLabel,
  });

  final SandTool tool;
  final SandMaterial material;
  final ValueChanged<SandTool> onTool;
  final ValueChanged<SandMaterial> onMaterial;
  final String paintLabel;
  final String pourLabel;
  final String eraseLabel;

  static const _materialColors = [
    Color(0xFFAA77FF),
    Color(0xFFFF78AD),
    Color(0xFFD9DDFF),
  ];

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
        decoration: BoxDecoration(
          color: const Color(0xFF171721).withValues(alpha: .92),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: .09)),
          boxShadow: [
            BoxShadow(
              color: AppColors.pulse.withValues(alpha: .13),
              blurRadius: 30,
              spreadRadius: -9,
            ),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
              child: _ToolButton(
                icon: Icons.gesture_rounded,
                label: paintLabel,
                selected: tool == SandTool.paint,
                onTap: () => onTool(SandTool.paint),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: _ToolButton(
                icon: Icons.waterfall_chart_rounded,
                label: pourLabel,
                selected: tool == SandTool.pour,
                onTap: () => onTool(SandTool.pour),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: _ToolButton(
                icon: Icons.auto_fix_off_rounded,
                label: eraseLabel,
                selected: tool == SandTool.erase,
                onTap: () => onTool(SandTool.erase),
              ),
            ),
          ]),
          const SizedBox(height: 11),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final value in SandMaterial.values)
                Semantics(
                  button: true,
                  selected: material == value,
                  label: value.name,
                  child: GestureDetector(
                    onTap: () => onMaterial(value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: material == value ? 30 : 24,
                      height: material == value ? 30 : 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _materialColors[value.index],
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: material == value ? .8 : .15,
                          ),
                          width: material == value ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _materialColors[value.index]
                                .withValues(alpha: .28),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ]),
      );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 5),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.pulse.withValues(alpha: .18)
                  : Colors.white.withValues(alpha: .035),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: selected
                    ? AppColors.pulse.withValues(alpha: .48)
                    : Colors.white.withValues(alpha: .045),
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon,
                  size: 18,
                  color: selected
                      ? const Color(0xFFD8C3FF)
                      : AppColors.textSecondary),
              const SizedBox(height: 4),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  )),
            ]),
          ),
        ),
      );
}
