import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show BlurStyle, ImageFilter, MaskFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/routing/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/pulse_mockup.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import '../../../session/application/session_provider.dart';
import '../../../transport/transport.dart';
import '../../application/ray_sketch_engine.dart';

class RaySketchModeScreen extends ConsumerStatefulWidget {
  const RaySketchModeScreen({super.key});

  @override
  ConsumerState<RaySketchModeScreen> createState() =>
      _RaySketchModeScreenState();
}

class _RaySketchModeScreenState extends ConsumerState<RaySketchModeScreen>
    with WidgetsBindingObserver {
  static const _uuid = Uuid();
  static const _violet = Color(0xFF9747FF);
  static const List<Color> _palette = [
    Color(0xFFFFFFFF),
    _violet,
    Color(0xFFB975FF),
    Color(0xFFE07CFF),
    Color(0xFFFF7CC8),
    Color(0xFFFF4D8B),
    Color(0xFFFF8A65),
    Color(0xFFFFD86A),
    Color(0xFF7CE0A1),
    Color(0xFF6BD3FF),
    Color(0xFF60A5FA),
    Color(0xFF94A3B8),
    Color(0xFF111827),
  ];
  static const List<Color> _canvasPalette = [
    Color(0xFF100B19),
    Color(0xFF24113D),
    Color(0xFF16102A),
    Color(0xFF101B35),
    Color(0xFF321827),
    Color(0xFFF3ECFF),
  ];
  static const Set<String> _events = {
    'ray_stroke_begin',
    'ray_stroke_points',
    'ray_stroke_end',
    'ray_state_request',
    'ray_state',
    'ray_undo',
    'ray_clear',
    'ray_canvas',
    'ray_card',
    // Compatibility with builds released before protocol v2.
    'ray_point',
    'ray_end',
  };

  late final RaySketchEngine _engine;
  late final ValueNotifier<double> _livingPulse;
  late final Stopwatch _livingClock;
  Timer? _livingTimer;
  StreamSubscription<ModeEvent>? _partnerSub;
  ProviderSubscription<AsyncValue<TransportKind>>? _transportSub;
  Timer? _batchTimer;
  Timer? _statusTimer;
  final List<RayPoint> _pendingPoints = [];
  Future<void> _outbound = Future.value();

  Color _selectedColor = _violet;
  double _selectedWidth = 9;
  RayBrushEffect _selectedEffect = RayBrushEffect.neon;
  bool _liveMode = true;
  int _revision = 0;
  int? _pointerId;
  String? _activeStrokeId;
  String? _legacyStrokeId;
  Stopwatch? _strokeClock;
  DateTime _lastHapticAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSyncRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _statusOverride;

  @override
  void initState() {
    super.initState();
    _engine = RaySketchEngine(
      ownerId: _uuid.v4(),
      canvasColorValue: _canvasPalette.first.toARGB32(),
    );
    _livingPulse = ValueNotifier(0);
    _livingClock = Stopwatch()..start();
    WidgetsBinding.instance.addObserver(this);
    _startLivingPulse();

    final bus = ref.read(modeEventBusProvider);
    _partnerSub =
        bus.incoming.where((event) => _events.contains(event.type)).listen(
              _onPartnerEvent,
              onError: (_) => _showTransientStatus(
                _copy('Связь восстанавливается…', 'Restoring connection…'),
              ),
            );
    _transportSub = ref.listenManual<AsyncValue<TransportKind>>(
      transportStateProvider,
      (previous, next) {
        final kind = next.valueOrNull;
        if (kind == null || kind == TransportKind.searching) return;
        if (previous?.valueOrNull != kind) _requestState();
      },
      fireImmediately: true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestState());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _livingTimer?.cancel();
    _batchTimer?.cancel();
    _statusTimer?.cancel();
    _partnerSub?.cancel();
    _transportSub?.close();
    _livingPulse.dispose();
    super.dispose();
  }

  void _startLivingPulse() {
    _livingTimer?.cancel();
    // Twenty ambient frames per second are enough for the slow breathing and
    // sparkle effects. Pointer updates still repaint immediately, so drawing
    // stays responsive without redrawing every blurred stroke at display FPS.
    _livingTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      _livingPulse.value = (_livingClock.elapsedMilliseconds % 3200) / 3200.0;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _livingClock.start();
      _startLivingPulse();
    } else {
      _livingTimer?.cancel();
      _livingClock.stop();
    }
  }

  void _requestState() {
    if (!mounted) return;
    final now = DateTime.now();
    if (now.difference(_lastSyncRequestAt) <
        const Duration(milliseconds: 700)) {
      return;
    }
    _lastSyncRequestAt = now;
    _enqueue(_engine.stateRequestEvent());
  }

  void _onPartnerEvent(ModeEvent event) {
    if (!mounted) return;
    if (event.type == 'ray_point' || event.type == 'ray_end') {
      _applyLegacyEvent(event);
      return;
    }
    final result = _engine.apply(event);
    if (result.reply != null) _enqueue(result.reply!);
    if (!result.changed) return;
    setState(() => _revision++);
    if (event.type == 'ray_state') {
      _showTransientStatus(_copy('Холст восстановлен', 'Canvas restored'));
    } else if (event.type == 'ray_stroke_begin') {
      HapticFeedback.selectionClick();
    } else if (event.type == 'ray_stroke_end' || event.type == 'ray_card') {
      HapticFeedback.lightImpact();
    }
  }

  void _applyLegacyEvent(ModeEvent event) {
    if (event.type == 'ray_end') {
      final id = _legacyStrokeId;
      final stroke = id == null ? null : _engine.strokeById(id);
      if (stroke != null) {
        stroke.complete = true;
        setState(() => _revision++);
      }
      _legacyStrokeId = null;
      return;
    }
    final x = (event.data['x'] as num?)?.toDouble();
    final y = (event.data['y'] as num?)?.toDouble();
    if (x == null || y == null) return;
    final point = RayPoint(x: x.clamp(0, 1), y: y.clamp(0, 1));
    var id = _legacyStrokeId;
    if (id == null) {
      id = 'legacy-${DateTime.now().microsecondsSinceEpoch}';
      _legacyStrokeId = id;
      final stroke = {
        'id': id,
        'owner': 'legacy-partner',
        'version': {
          'c': DateTime.now().millisecondsSinceEpoch,
          'a': 'legacy-partner',
        },
        'color': (event.data['color'] as num?)?.toInt() ?? 0xFF60A5FA,
        'width': (event.data['width'] as num?)?.toDouble() ?? 10,
        'effect': (event.data['effect'] as num?)?.toInt() ?? 1,
        'points': [point.toWire()],
      };
      _engine.apply(ModeEvent(
        type: 'ray_stroke_begin',
        data: {'stroke': stroke},
      ));
    } else {
      _engine.apply(ModeEvent(
        type: 'ray_stroke_points',
        data: {
          'id': id,
          'owner': 'legacy-partner',
          'points': [point.toWire()],
        },
      ));
    }
    setState(() => _revision++);
  }

  void _onPointerDown(PointerDownEvent event, Size size) {
    if (_pointerId != null || size.isEmpty) return;
    _pointerId = event.pointer;
    _strokeClock = Stopwatch()..start();
    final point = _pointFor(event.localPosition, event.pressure, size);
    final stroke = _engine.beginLocalStroke(
      id: '${_engine.ownerId}-${_engine.logicalClock + 1}-${event.pointer}',
      colorValue: _selectedColor.toARGB32(),
      width: _selectedWidth,
      effect: _selectedEffect,
      point: point,
    );
    _activeStrokeId = stroke.id;
    setState(() => _revision++);
    HapticFeedback.selectionClick();
    if (_liveMode) _enqueue(_engine.beginEvent(stroke));
  }

  void _onPointerMove(PointerMoveEvent event, Size size) {
    if (_pointerId != event.pointer || size.isEmpty) return;
    final id = _activeStrokeId;
    if (id == null) return;
    final stroke = _engine.strokeById(id);
    if (stroke == null) return;
    final point = _pointFor(event.localPosition, event.pressure, size);
    final previous = stroke.points.last;
    final distance = math.sqrt(
      math.pow(point.x - previous.x, 2) + math.pow(point.y - previous.y, 2),
    );
    if (distance < 0.0017) return;
    if (!_engine.appendLocalPoints(id, [point])) return;
    if (_liveMode) {
      _pendingPoints.add(point);
      if (_pendingPoints.length >= 8) {
        _flushPointBatch();
      } else {
        _batchTimer ??= Timer(
          const Duration(milliseconds: 32),
          _flushPointBatch,
        );
      }
    }
    final now = DateTime.now();
    if (distance > 0.018 &&
        now.difference(_lastHapticAt) > const Duration(milliseconds: 110)) {
      _lastHapticAt = now;
      HapticFeedback.selectionClick();
    }
    setState(() => _revision++);
  }

  void _onPointerUp(PointerEvent event) {
    if (_pointerId != event.pointer) return;
    _flushPointBatch();
    final id = _activeStrokeId;
    final stroke = id == null ? null : _engine.finishLocalStroke(id);
    if (_liveMode && stroke != null) _enqueue(_engine.endEvent(stroke));
    _pointerId = null;
    _activeStrokeId = null;
    _strokeClock?.stop();
    _strokeClock = null;
    setState(() => _revision++);
    HapticFeedback.lightImpact();
  }

  RayPoint _pointFor(Offset local, double rawPressure, Size size) {
    final pressure = rawPressure <= 0 ? 1.0 : rawPressure.clamp(0.12, 1.8);
    return RayPoint(
      x: (local.dx / size.width).clamp(0, 1),
      y: (local.dy / size.height).clamp(0, 1),
      pressure: pressure,
      elapsedMs: _strokeClock?.elapsedMilliseconds ?? 0,
    );
  }

  void _flushPointBatch() {
    _batchTimer?.cancel();
    _batchTimer = null;
    final id = _activeStrokeId;
    if (!_liveMode || id == null || _pendingPoints.isEmpty) {
      _pendingPoints.clear();
      return;
    }
    final points = List<RayPoint>.of(_pendingPoints);
    _pendingPoints.clear();
    _enqueue(_engine.pointsEvent(id, points));
  }

  void _enqueue(ModeEvent event) {
    _outbound = _outbound
        .then((_) => ref.read(modeEventBusProvider).send(event))
        .catchError((Object _) {});
  }

  void _undo() {
    final removed = _engine.undoLastLocal();
    if (removed == null) return;
    setState(() => _revision++);
    HapticFeedback.mediumImpact();
    if (_liveMode) _enqueue(_engine.undoEvent(removed.id));
  }

  void _clear() {
    final event = _engine.clearLocal();
    setState(() => _revision++);
    HapticFeedback.heavyImpact();
    if (_liveMode) _enqueue(event);
  }

  void _setCanvas(Color color) {
    final event = _engine.setCanvasColor(color.toARGB32());
    setState(() => _revision++);
    HapticFeedback.selectionClick();
    if (_liveMode) _enqueue(event);
  }

  Future<void> _sendMoment() async {
    _flushPointBatch();
    final event =
        _engine.stateEvent(type: _liveMode ? 'ray_state' : 'ray_card');
    await ref.read(modeEventBusProvider).send(event);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    _showTransientStatus(
      _liveMode
          ? _copy('Момент синхронизирован', 'Moment synchronized')
          : AppLocalizations.of(context)!.sketchSendReady,
    );
  }

  void _showTransientStatus(String value) {
    if (!mounted) return;
    _statusTimer?.cancel();
    setState(() => _statusOverride = value);
    _statusTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _statusOverride = null);
    });
  }

  Future<void> _chooseCustomColor({required bool canvas}) async {
    final chosen = await showModalBottomSheet<Color>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ColorStudioSheet(
        initial: canvas ? Color(_engine.canvasColorValue) : _selectedColor,
        title: canvas
            ? _copy('Цвет пространства', 'Canvas color')
            : _copy('Свой цвет рисунка', 'Custom drawing color'),
      ),
    );
    if (chosen == null || !mounted) return;
    if (canvas) {
      _setCanvas(chosen);
    } else {
      setState(() => _selectedColor = chosen);
      HapticFeedback.selectionClick();
    }
  }

  String _copy(String ru, String en) =>
      Localizations.localeOf(context).languageCode == 'ru' ? ru : en;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final connected = ref.read(modeEventBusProvider).isConnected;
    final canvasColor = Color(_engine.canvasColorValue);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    key: const Key('ray-canvas-boundary'),
                    child: Semantics(
                      label: _copy(
                        'Живой совместный холст. Рисуйте пальцем.',
                        'Live shared canvas. Draw with your finger.',
                      ),
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (event) => _onPointerDown(event, size),
                        onPointerMove: (event) => _onPointerMove(event, size),
                        onPointerUp: _onPointerUp,
                        onPointerCancel: _onPointerUp,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            RepaintBoundary(
                              child: CustomPaint(
                                painter: _LivingRayPainter(
                                  layer: _RayPaintLayer.background,
                                  strokes: _engine.strokes,
                                  localOwnerId: _engine.ownerId,
                                  canvasColor: canvasColor,
                                  revision: _revision,
                                  pulse: _livingPulse,
                                ),
                              ),
                            ),
                            RepaintBoundary(
                              child: CustomPaint(
                                painter: _LivingRayPainter(
                                  layer: _RayPaintLayer.strokes,
                                  strokes: _engine.strokes,
                                  localOwnerId: _engine.ownerId,
                                  canvasColor: canvasColor,
                                  revision: _revision,
                                  pulse: _livingPulse,
                                ),
                              ),
                            ),
                            IgnorePointer(
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  painter: _LivingRayPainter(
                                    layer: _RayPaintLayer.accents,
                                    strokes: _engine.strokes,
                                    localOwnerId: _engine.ownerId,
                                    canvasColor: canvasColor,
                                    revision: _revision,
                                    pulse: _livingPulse,
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
                Positioned(
                  top: 10,
                  left: 20,
                  right: 20,
                  child: PulseHeader(
                    title: t.modeRay,
                    leading: PulseRoundButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => context.go(Routes.hub),
                      subtle: true,
                    ),
                  ),
                ),
                Positioned(
                  top: 66,
                  left: 24,
                  right: 24,
                  child: Center(
                    child: _PresencePill(
                      connected: connected,
                      message: _statusOverride ??
                          (connected
                              ? _copy('Вместе · штрихи приходят вживую',
                                  'Together · strokes arrive live')
                              : _copy('Холст работает офлайн',
                                  'Canvas works offline')),
                    ),
                  ),
                ),
                Positioned(
                  top: 108,
                  left: 44,
                  right: 44,
                  child: IgnorePointer(
                    child: Text(
                      _copy(
                        'Нарисуйте то, что трудно сказать словами',
                        'Draw what is hard to put into words',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color:
                            _contrastFor(canvasColor).withValues(alpha: 0.68),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.15,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _RayControlDock(
                    palette: _palette,
                    canvasPalette: _canvasPalette,
                    selectedColor: _selectedColor,
                    selectedWidth: _selectedWidth,
                    selectedEffect: _selectedEffect,
                    selectedCanvas: canvasColor,
                    liveMode: _liveMode,
                    canUndo: _engine.strokes.any(
                      (stroke) =>
                          stroke.ownerId == _engine.ownerId && stroke.complete,
                    ),
                    onLiveModeChanged: (value) {
                      setState(() => _liveMode = value);
                      HapticFeedback.selectionClick();
                      if (value) _enqueue(_engine.stateEvent());
                    },
                    onColor: (color) {
                      setState(() => _selectedColor = color);
                      HapticFeedback.selectionClick();
                    },
                    onCustomColor: () => _chooseCustomColor(canvas: false),
                    onCanvas: _setCanvas,
                    onCustomCanvas: () => _chooseCustomColor(canvas: true),
                    onWidth: (width) => setState(() => _selectedWidth = width),
                    onEffect: (effect) {
                      setState(() => _selectedEffect = effect);
                      HapticFeedback.selectionClick();
                    },
                    onUndo: _undo,
                    onClear: _clear,
                    onSend: _sendMoment,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PresencePill extends StatelessWidget {
  const _PresencePill({required this.connected, required this.message});

  final bool connected;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      connected ? const Color(0xFF9AFFC0) : AppColors.textMuted,
                  boxShadow: connected
                      ? const [
                          BoxShadow(color: Color(0x889AFFC0), blurRadius: 8),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RayControlDock extends StatelessWidget {
  const _RayControlDock({
    required this.palette,
    required this.canvasPalette,
    required this.selectedColor,
    required this.selectedWidth,
    required this.selectedEffect,
    required this.selectedCanvas,
    required this.liveMode,
    required this.canUndo,
    required this.onLiveModeChanged,
    required this.onColor,
    required this.onCustomColor,
    required this.onCanvas,
    required this.onCustomCanvas,
    required this.onWidth,
    required this.onEffect,
    required this.onUndo,
    required this.onClear,
    required this.onSend,
  });

  final List<Color> palette;
  final List<Color> canvasPalette;
  final Color selectedColor;
  final double selectedWidth;
  final RayBrushEffect selectedEffect;
  final Color selectedCanvas;
  final bool liveMode;
  final bool canUndo;
  final ValueChanged<bool> onLiveModeChanged;
  final ValueChanged<Color> onColor;
  final VoidCallback onCustomColor;
  final ValueChanged<Color> onCanvas;
  final VoidCallback onCustomCanvas;
  final ValueChanged<double> onWidth;
  final ValueChanged<RayBrushEffect> onEffect;
  final VoidCallback onUndo;
  final VoidCallback onClear;
  final VoidCallback onSend;

  static const _customCanvasSentinel = Color(0x00000001);

  String _copy(BuildContext context, String ru, String en) =>
      Localizations.localeOf(context).languageCode == 'ru' ? ru : en;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
          decoration: BoxDecoration(
            color: const Color(0xFF17101F).withValues(alpha: 0.84),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x6610061B),
                blurRadius: 36,
                offset: Offset(0, 16),
              ),
              BoxShadow(color: Color(0x339747FF), blurRadius: 28),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _ModeToggle(
                    live: liveMode,
                    liveLabel: t.sketchLive,
                    cardLabel: t.sketchCard,
                    onChanged: onLiveModeChanged,
                  ),
                  const Spacer(),
                  _DockAction(
                    key: const Key('ray-undo'),
                    icon: Icons.undo_rounded,
                    tooltip: _copy(context, 'Отменить штрих', 'Undo stroke'),
                    enabled: canUndo,
                    onTap: onUndo,
                  ),
                  const SizedBox(width: 7),
                  _DockAction(
                    key: const Key('ray-clear'),
                    icon: Icons.delete_outline_rounded,
                    tooltip: t.sketchClear,
                    onTap: onClear,
                  ),
                  const SizedBox(width: 7),
                  _DockAction(
                    key: const Key('ray-send'),
                    icon:
                        liveMode ? Icons.favorite_rounded : Icons.send_rounded,
                    tooltip: t.sketchSend,
                    highlighted: true,
                    onTap: onSend,
                  ),
                ],
              ),
              const SizedBox(height: 11),
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: palette.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    if (index == palette.length) {
                      return _SpectrumButton(
                        tooltip: _copy(context, 'Любой цвет', 'Any color'),
                        onTap: onCustomColor,
                      );
                    }
                    final color = palette[index];
                    return _ColorDot(
                      key: Key('ray-color-$index'),
                      color: color,
                      selected: color == selectedColor,
                      onTap: () => onColor(color),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final effect in RayBrushEffect.values) ...[
                    _EffectButton(
                      effect: effect,
                      selected: selectedEffect == effect,
                      tooltip: _effectLabel(t, effect),
                      onTap: () => onEffect(effect),
                    ),
                    const SizedBox(width: 5),
                  ],
                  const SizedBox(width: 2),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        activeTrackColor: selectedColor,
                        inactiveTrackColor:
                            Colors.white.withValues(alpha: 0.16),
                        thumbColor: selectedColor,
                        overlayColor: selectedColor.withValues(alpha: 0.13),
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                      ),
                      child: Slider(
                        key: const Key('ray-width'),
                        min: 2,
                        max: 24,
                        value: selectedWidth,
                        semanticFormatterCallback: (value) =>
                            '${value.round()} px',
                        onChanged: onWidth,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  PopupMenuButton<Color>(
                    key: const Key('ray-canvas-color'),
                    tooltip: t.sketchCanvas,
                    color: AppColors.surfaceElevated,
                    onSelected: (color) {
                      if (color == _customCanvasSentinel) {
                        // Let the popup finish its route transition before a
                        // bottom sheet is pushed. Some Android builds otherwise
                        // discard the second route during the same frame.
                        Future<void>.delayed(
                          const Duration(milliseconds: 180),
                          onCustomCanvas,
                        );
                      } else {
                        onCanvas(color);
                      }
                    },
                    itemBuilder: (context) => [
                      for (final color in canvasPalette)
                        PopupMenuItem(
                          value: color,
                          child: Row(
                            children: [
                              _CanvasSwatch(color: color),
                              const SizedBox(width: 10),
                              Text(
                                color == selectedCanvas
                                    ? _copy(context, 'Выбран', 'Selected')
                                    : t.sketchCanvas,
                              ),
                            ],
                          ),
                        ),
                      PopupMenuItem(
                        value: _customCanvasSentinel,
                        child: Row(
                          children: [
                            const _SpectrumButton(compact: true),
                            const SizedBox(width: 10),
                            Text(_copy(context, 'Свой цвет', 'Custom color')),
                          ],
                        ),
                      ),
                    ],
                    child: _CanvasSwatch(color: selectedCanvas, selected: true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _effectLabel(AppLocalizations t, RayBrushEffect effect) =>
      switch (effect) {
        RayBrushEffect.clean => t.sketchEffectClean,
        RayBrushEffect.neon => t.sketchEffectNeon,
        RayBrushEffect.glow => t.sketchEffectGlow,
        RayBrushEffect.watercolor => t.sketchEffectWatercolor,
        RayBrushEffect.sparkles => t.sketchEffectSparkles,
      };
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.live,
    required this.liveLabel,
    required this.cardLabel,
    required this.onChanged,
  });

  final bool live;
  final String liveLabel;
  final String cardLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeSegment(
            key: const Key('ray-live-mode'),
            label: liveLabel,
            selected: live,
            onTap: () => onChanged(true),
          ),
          _ModeSegment(
            key: const Key('ray-card-mode'),
            label: cardLabel,
            selected: !live,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFB65CFF)],
                  )
                : null,
            borderRadius: BorderRadius.circular(14),
            boxShadow: selected
                ? const [BoxShadow(color: Color(0x559747FF), blurRadius: 12)]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.45,
            ),
          ),
        ),
      ),
    );
  }
}

class _DockAction extends StatelessWidget {
  const _DockAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.highlighted = false,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool highlighted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: enabled ? 1 : 0.36,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: highlighted
                    ? const LinearGradient(
                        colors: [Color(0xFF7C3AED), Color(0xFFFF4D9D)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color:
                    highlighted ? null : Colors.white.withValues(alpha: 0.075),
                border: highlighted
                    ? null
                    : Border.all(color: Colors.white.withValues(alpha: 0.10)),
                boxShadow: highlighted
                    ? const [
                        BoxShadow(color: Color(0x779747FF), blurRadius: 18),
                      ]
                    : null,
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 32,
          height: 32,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? Colors.white.withValues(alpha: 0.13) : null,
            border: Border.all(
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.12),
              width: selected ? 2 : 1,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: selected
                  ? [
                      BoxShadow(
                          color: color.withValues(alpha: 0.72), blurRadius: 9)
                    ]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpectrumButton extends StatelessWidget {
  const _SpectrumButton({this.tooltip, this.onTap, this.compact = false});

  final String? tooltip;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final child = GestureDetector(
      onTap: onTap,
      child: Container(
        width: compact ? 24 : 32,
        height: compact ? 24 : 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const SweepGradient(colors: [
            Colors.red,
            Colors.yellow,
            Colors.green,
            Colors.cyan,
            Colors.blue,
            Colors.purple,
            Colors.red,
          ]),
          border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        ),
        child: compact
            ? null
            : const Icon(Icons.add_rounded, color: Colors.white, size: 16),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

class _CanvasSwatch extends StatelessWidget {
  const _CanvasSwatch({required this.color, this.selected = false});

  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: selected ? 34 : 24,
      height: selected ? 34 : 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.3),
          width: selected ? 2 : 1,
        ),
        boxShadow: selected
            ? [BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 10)]
            : null,
      ),
      child: selected
          ? const Icon(Icons.layers_rounded, color: Colors.white, size: 15)
          : null,
    );
  }
}

class _EffectButton extends StatelessWidget {
  const _EffectButton({
    required this.effect,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  final RayBrushEffect effect;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? const Color(0xFF9747FF).withValues(alpha: 0.24)
                  : Colors.white.withValues(alpha: 0.055),
              border: Border.all(
                color: selected
                    ? const Color(0xFFB975FF)
                    : Colors.white.withValues(alpha: 0.10),
              ),
            ),
            child: Icon(
              switch (effect) {
                RayBrushEffect.clean => Icons.gesture_rounded,
                RayBrushEffect.neon => Icons.bolt_rounded,
                RayBrushEffect.glow => Icons.blur_on_rounded,
                RayBrushEffect.watercolor => Icons.water_drop_rounded,
                RayBrushEffect.sparkles => Icons.auto_awesome_rounded,
              },
              size: 16,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorStudioSheet extends StatefulWidget {
  const _ColorStudioSheet({required this.initial, required this.title});

  final Color initial;
  final String title;

  @override
  State<_ColorStudioSheet> createState() => _ColorStudioSheetState();
}

class _ColorStudioSheetState extends State<_ColorStudioSheet> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  String _copy(String ru, String en) =>
      Localizations.localeOf(context).languageCode == 'ru' ? ru : en;

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
        decoration: BoxDecoration(
          color: const Color(0xF21B1425),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
          boxShadow: const [
            BoxShadow(color: Color(0x8810061B), blurRadius: 36),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 15),
            Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              height: 76,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                      color: color.withValues(alpha: 0.55), blurRadius: 28),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                style: TextStyle(
                  color: _contrastFor(color),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _StudioSlider(
              label: _copy('Оттенок', 'Hue'),
              value: _hsv.hue,
              max: 360,
              gradient: const LinearGradient(colors: [
                Colors.red,
                Colors.yellow,
                Colors.green,
                Colors.cyan,
                Colors.blue,
                Colors.purple,
                Colors.red,
              ]),
              onChanged: (value) => setState(() => _hsv = _hsv.withHue(value)),
            ),
            _StudioSlider(
              label: _copy('Насыщенность', 'Saturation'),
              value: _hsv.saturation,
              gradient: LinearGradient(colors: [
                HSVColor.fromAHSV(1, _hsv.hue, 0, _hsv.value).toColor(),
                HSVColor.fromAHSV(1, _hsv.hue, 1, _hsv.value).toColor(),
              ]),
              onChanged: (value) =>
                  setState(() => _hsv = _hsv.withSaturation(value)),
            ),
            _StudioSlider(
              label: _copy('Свет', 'Light'),
              value: _hsv.value,
              gradient: LinearGradient(colors: [
                Colors.black,
                HSVColor.fromAHSV(1, _hsv.hue, _hsv.saturation, 1).toColor(),
              ]),
              onChanged: (value) =>
                  setState(() => _hsv = _hsv.withValue(value)),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF9747FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(color),
                child: Text(_copy('Выбрать', 'Choose')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudioSlider extends StatelessWidget {
  const _StudioSlider({
    required this.label,
    required this.value,
    required this.gradient,
    required this.onChanged,
    this.max = 1,
  });

  final String label;
  final double value;
  final double max;
  final LinearGradient gradient;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          SizedBox(
            width: 102,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 7,
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 0,
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white.withValues(alpha: 0.12),
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    min: 0,
                    max: max,
                    value: value,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _RayPaintLayer { background, strokes, accents }

class _LivingRayPainter extends CustomPainter {
  _LivingRayPainter({
    required this.layer,
    required this.strokes,
    required this.localOwnerId,
    required this.canvasColor,
    required this.revision,
    required ValueNotifier<double> pulse,
  })  : _pulse = pulse,
        super(repaint: layer == _RayPaintLayer.strokes ? null : pulse);

  final _RayPaintLayer layer;
  final List<RayStroke> strokes;
  final String localOwnerId;
  final Color canvasColor;
  final int revision;
  final ValueNotifier<double> _pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = _pulse.value * math.pi * 2;
    switch (layer) {
      case _RayPaintLayer.background:
        _drawLivingBackground(canvas, size, phase);
      case _RayPaintLayer.strokes:
        for (final stroke in strokes) {
          _drawStroke(canvas, size, stroke, phase, includeAccents: false);
        }
      case _RayPaintLayer.accents:
        for (final stroke in strokes) {
          if (stroke.points.isEmpty) continue;
          final points = [
            for (final point in stroke.points)
              Offset(point.x * size.width, point.y * size.height),
          ];
          final width = stroke.width * size.shortestSide / 390;
          final color = Color(stroke.colorValue);
          if (stroke.effect == RayBrushEffect.sparkles) {
            _drawSparkles(
              canvas,
              points,
              color,
              width,
              phase,
              stroke.id.hashCode,
            );
          }
          if (!stroke.complete && stroke.ownerId != localOwnerId) {
            _drawPartnerPresence(canvas, points.last, color, width, phase);
          }
        }
    }
  }

  void _drawLivingBackground(Canvas canvas, Size size, double phase) {
    final dark = canvasColor.computeLuminance() < 0.45;
    final top = Color.alphaBlend(
      (dark ? Colors.white : Colors.black).withValues(alpha: 0.025),
      canvasColor,
    );
    final bottom = Color.alphaBlend(
      const Color(0xFF6D28D9).withValues(alpha: dark ? 0.20 : 0.08),
      canvasColor,
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, canvasColor, bottom],
          stops: const [0, 0.56, 1],
        ).createShader(Offset.zero & size),
    );

    final center = Offset(size.width * 0.5, size.height * 0.43);
    final breath = 1 + math.sin(phase) * 0.025;
    final auraRadius = size.shortestSide * 0.48 * breath;
    canvas.drawCircle(
      center,
      auraRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFB975FF).withValues(alpha: dark ? 0.075 : 0.035),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: auraRadius)),
    );

    final rings = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (var index = 0; index < 4; index++) {
      rings.color = (dark ? Colors.white : Colors.black).withValues(
        alpha: 0.035 - index * 0.005,
      );
      canvas.drawCircle(
        center,
        (54 + index * 48) * breath * size.shortestSide / 390,
        rings,
      );
    }

    final dust = Paint();
    for (var index = 0; index < 44; index++) {
      final x = ((index * 83) % 997) / 997 * size.width;
      final y = ((index * 157 + 31) % 991) / 991 * size.height;
      final twinkle = (math.sin(phase + index * 0.77) + 1) / 2;
      dust.color = (dark ? Colors.white : Colors.black).withValues(
        alpha: 0.025 + twinkle * 0.035,
      );
      canvas.drawCircle(Offset(x, y), 0.45 + twinkle * 0.55, dust);
    }
  }

  void _drawStroke(
    Canvas canvas,
    Size size,
    RayStroke stroke,
    double phase, {
    required bool includeAccents,
  }) {
    if (stroke.points.isEmpty) return;
    final points = [
      for (final point in stroke.points)
        Offset(point.x * size.width, point.y * size.height),
    ];
    final scale = size.shortestSide / 390;
    final baseWidth = stroke.width * scale;
    final color = Color(stroke.colorValue);
    final path = _smoothPath(points);
    final breathing =
        0.88 + (math.sin(phase + stroke.id.hashCode * 0.001) + 1) * 0.06;

    switch (stroke.effect) {
      case RayBrushEffect.clean:
        break;
      case RayBrushEffect.neon:
        canvas.drawPath(
          path,
          _strokePaint(
            color.withValues(alpha: 0.18 * breathing),
            baseWidth * 4.6,
            blur: baseWidth * 1.35,
          ),
        );
        canvas.drawPath(
          path,
          _strokePaint(color.withValues(alpha: 0.34), baseWidth * 2.15),
        );
      case RayBrushEffect.glow:
        canvas.drawPath(
          path,
          _strokePaint(
            color.withValues(alpha: 0.20 * breathing),
            baseWidth * 3.25,
            blur: baseWidth,
          ),
        );
      case RayBrushEffect.watercolor:
        canvas.drawPath(
          path.shift(const Offset(0.8, -0.6)),
          _strokePaint(color.withValues(alpha: 0.13), baseWidth * 2.7),
        );
        canvas.drawPath(
          path.shift(const Offset(-0.7, 0.9)),
          _strokePaint(color.withValues(alpha: 0.17), baseWidth * 1.8),
        );
      case RayBrushEffect.sparkles:
        break;
    }

    if (points.length == 1) {
      canvas.drawCircle(points.first, baseWidth / 2, Paint()..color = color);
    } else {
      _drawPressureSegments(canvas, points, stroke, color, baseWidth);
    }

    if (includeAccents && stroke.effect == RayBrushEffect.sparkles) {
      _drawSparkles(
          canvas, points, color, baseWidth, phase, stroke.id.hashCode);
    }
    if (includeAccents && !stroke.complete && stroke.ownerId != localOwnerId) {
      _drawPartnerPresence(canvas, points.last, color, baseWidth, phase);
    }
  }

  void _drawPressureSegments(
    Canvas canvas,
    List<Offset> points,
    RayStroke stroke,
    Color color,
    double baseWidth,
  ) {
    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1];
      final current = points[index];
      final a = stroke.points[index - 1];
      final b = stroke.points[index];
      final elapsed = math.max(1, b.elapsedMs - a.elapsedMs);
      final speed = (current - previous).distance / elapsed;
      final speedFactor = (1.08 - speed * 0.22).clamp(0.72, 1.08);
      final pressure = ((a.pressure + b.pressure) / 2).clamp(0.2, 1.5);
      final pressureFactor = (0.58 + pressure * 0.52).clamp(0.62, 1.28);
      final width = baseWidth * pressureFactor * speedFactor;
      final segment = Path()
        ..moveTo(previous.dx, previous.dy)
        ..lineTo(current.dx, current.dy);
      final alpha = stroke.effect == RayBrushEffect.watercolor ? 0.58 : 0.94;
      canvas.drawPath(
          segment, _strokePaint(color.withValues(alpha: alpha), width));
    }
    final last = points.last;
    canvas.drawCircle(
      last,
      baseWidth * stroke.points.last.pressure.clamp(0.4, 1.4) / 2,
      Paint()..color = color.withValues(alpha: 0.94),
    );
  }

  Path _smoothPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    if (points.length == 1) return path;
    for (var index = 1; index < points.length - 1; index++) {
      final point = points[index];
      final next = points[index + 1];
      path.quadraticBezierTo(
        point.dx,
        point.dy,
        (point.dx + next.dx) / 2,
        (point.dy + next.dy) / 2,
      );
    }
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  Paint _strokePaint(Color color, double width, {double? blur}) {
    return Paint()
      ..isAntiAlias = true
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width
      ..maskFilter = blur == null
          ? null
          : MaskFilter.blur(BlurStyle.normal, blur.clamp(1, 22));
  }

  void _drawSparkles(
    Canvas canvas,
    List<Offset> points,
    Color color,
    double width,
    double phase,
    int seed,
  ) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (var index = 0; index < points.length; index += 6) {
      final point = points[index];
      final twinkle = (math.sin(phase * 1.6 + index + seed * 0.001) + 1) / 2;
      final radius = width * (0.12 + twinkle * 0.18) + 0.8;
      final direction = index.isEven ? 1.0 : -1.0;
      final center = point + Offset(width * direction, -width * 0.72);
      paint.color = color.withValues(alpha: 0.46 + twinkle * 0.46);
      canvas.drawCircle(center, radius, paint);
      canvas.drawLine(
        center - Offset(radius * 2.2, 0),
        center + Offset(radius * 2.2, 0),
        Paint()
          ..color = paint.color
          ..strokeWidth = 0.7,
      );
      canvas.drawLine(
        center - Offset(0, radius * 2.2),
        center + Offset(0, radius * 2.2),
        Paint()
          ..color = paint.color
          ..strokeWidth = 0.7,
      );
    }
  }

  void _drawPartnerPresence(
    Canvas canvas,
    Offset point,
    Color color,
    double width,
    double phase,
  ) {
    final pulse = (math.sin(phase * 1.35) + 1) / 2;
    canvas.drawCircle(
      point,
      width * 1.3 + pulse * 5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withValues(alpha: 0.32 + pulse * 0.28),
    );
    canvas.drawCircle(
      point,
      width * 0.22 + 1.3,
      Paint()..color = Colors.white.withValues(alpha: 0.86),
    );
  }

  @override
  bool shouldRepaint(_LivingRayPainter oldDelegate) =>
      oldDelegate.layer != layer ||
      oldDelegate.revision != revision ||
      oldDelegate.canvasColor != canvasColor ||
      oldDelegate.strokes != strokes;
}

Color _contrastFor(Color color) =>
    color.computeLuminance() > 0.48 ? const Color(0xFF15101D) : Colors.white;
