import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/secure_key_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../capabilities/application/capability_providers.dart';
import '../../../capabilities/domain/device_capability.dart';
import '../../application/candle_dynamics.dart';
import '../../application/candle_material_profile.dart';
import '../../application/candle_memory_repository.dart';
import '../../application/candle_physics_engine.dart';
import '../../application/candle_quality_controller.dart';
import '../../application/candle_realtime_protocol.dart';
import '../../application/candle_world_state.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import '../../../session/application/session_provider.dart';
import '../../primitives/candle_sound_controller.dart';
import '../../primitives/accelerometer_3d_stream.dart';
import '../../primitives/haptic_pattern_player.dart';
import '../../primitives/mic_level_stream.dart';
import '../../primitives/primitive_providers.dart';

/// "Candle" — touch to light a virtual candle, blow into the mic to
/// extinguish it. The partner's candle lights/extinguishes in sync.
///
/// Uses [MicLevelStream] for blow detection and [HapticPatternPlayer]
/// for gentle haptic feedback on light/extinguish events.
class CandleModeScreen extends ConsumerWidget {
  const CandleModeScreen({
    super.key,
    this.micLevelStream,
    this.hapticEngine,
    this.accelerometerStream,
    this.blowThreshold = 0.6,
    this.requiredBlowSamples = 3,
    this.calibrationDuration = const Duration(milliseconds: 1800),
  });

  final MicLevelStream? micLevelStream;
  final HapticEngine? hapticEngine;
  final Accelerometer3DStream? accelerometerStream;
  final double blowThreshold;
  final int requiredBlowSamples;
  final Duration calibrationDuration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capsAsync = ref.watch(deviceCapabilitiesProvider);
    if (capsAsync.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.pulse),
        ),
      );
    }
    final caps = capsAsync.asData?.value ?? const DeviceCapabilities.none();
    return _CandleModeView(
      micLevelStream: micLevelStream ??
          (caps.has(DeviceCapability.microphone)
              ? ref.watch(micLevelStreamProvider)
              : null),
      hapticEngine: hapticEngine ?? ref.watch(hapticEngineProvider),
      accelerometerStream: accelerometerStream ??
          (caps.has(DeviceCapability.accelerometer)
              ? ref.watch(accelerometerStreamProvider)
              : null),
      blowThreshold: blowThreshold,
      requiredBlowSamples: requiredBlowSamples,
      calibrationDuration: calibrationDuration,
    );
  }
}

class _CandleModeView extends ConsumerStatefulWidget {
  const _CandleModeView({
    required this.micLevelStream,
    required this.hapticEngine,
    required this.accelerometerStream,
    required this.blowThreshold,
    required this.requiredBlowSamples,
    required this.calibrationDuration,
  });

  final MicLevelStream? micLevelStream;
  final HapticEngine? hapticEngine;
  final Accelerometer3DStream? accelerometerStream;
  final double blowThreshold;
  final int requiredBlowSamples;
  final Duration calibrationDuration;

  @override
  ConsumerState<_CandleModeView> createState() => _CandleModeViewState();
}

class _CandleModeViewState extends ConsumerState<_CandleModeView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final MicLevelStream _mic;
  late final HapticEngine _engine;
  late final HapticPatternPlayer _player;
  late final CandleBreathAnalyzer _breathAnalyzer;
  late final AnimationController _flicker;
  static const _physicsStep = Duration(microseconds: 16667);
  static const CandlePhysicsEngine _physicsEngine = CandlePhysicsEngine();
  final Stopwatch _physicsClock = Stopwatch();
  Duration _lastPhysicsAt = Duration.zero;
  Duration _physicsCarry = Duration.zero;
  StreamSubscription<MicLevel>? _micSub;
  StreamSubscription<Accel3>? _motionSub;
  StreamSubscription<ModeEvent>? _partnerSub;
  Timer? _partnerWindDecay;
  Timer? _partnerMotionDecay;
  Timer? _gestureWindDecay;
  Timer? _sharedGlowTimer;
  Timer? _bridgeHapticTimer;
  Timer? _waxTimer;
  Timer? _ignitionIntentTimer;
  Timer? _idleAnimationTimer;
  bool _ownsMic = false;
  bool _ownsEngine = false;

  bool _isLit = false;
  bool _soundEnabled = true;
  bool _gestureBreathOnly = false;
  bool _partnerWasBlowing = false;
  bool _bridgeActive = false;
  int _blowSamplesOverThreshold = 0;
  double _localWind = 0;
  double _partnerWind = 0;
  double _localTilt = 0;
  double _localMotion = 0;
  double _partnerTilt = 0;
  double _partnerMotion = 0;
  DateTime? _lastWindSentAt;
  DateTime? _lastMotionSentAt;
  double _lastWindSentLevel = 0;
  int _windSequence = 0;
  int _motionSequence = 0;
  final CandleRealtimeGuard _realtimeGuard = CandleRealtimeGuard();
  double _calibrationProgress = 0;
  bool _calibrated = false;
  DateTime? _lastSoundUpdateAt;
  DateTime? _lastLocalLightAt;
  DateTime? _lastPartnerLightAt;
  DateTime? _sharedGlowUntil;
  DateTime? _extinguishedAt;
  DateTime? _lastWaxTick;
  DateTime? _lastMemorySyncAt;
  CandleStyle _style = CandleStyle.classic;
  CandleWorldState _world = CandleWorldState.resting();
  CandleMemory _memory = CandleMemory.fresh(seed: 1);
  CandleMemoryRepository? _memoryRepository;
  bool _localShielded = false;
  bool _partnerShielded = false;
  bool _waitingForSharedIgnition = false;
  bool _partnerWishSealed = false;
  bool _localRevealRequested = false;
  bool _partnerRevealRequested = false;
  String? _partnerWish;
  bool _portalRequested = false;
  bool _partnerPortalRequested = false;
  int? _partnerPortalToken;
  late final int _portalToken;
  final Map<CandleStyle, ui.Image> _candleImages = {};
  ui.Image? _flameImage;
  ui.FragmentShader? _gpuFlameShader;
  final CandleQualityController _qualityController = CandleQualityController();
  CandleQualityProfile _quality = CandleQualityProfile.high;

  @override
  void initState() {
    super.initState();
    if (widget.micLevelStream == null) {
      _mic = FakeMicLevelStream();
      _ownsMic = true;
      _gestureBreathOnly = true;
    } else {
      _mic = widget.micLevelStream!;
    }
    if (widget.hapticEngine == null) {
      _engine = const NullHapticEngine();
      _ownsEngine = true;
    } else {
      _engine = widget.hapticEngine!;
    }
    _player = HapticPatternPlayer(_engine);
    _portalToken =
        (DateTime.now().microsecondsSinceEpoch ^ identityHashCode(this)) &
            0x7fffffff;
    _breathAnalyzer = CandleBreathAnalyzer(
      calibrationDuration: widget.calibrationDuration,
    );
    _calibrated = _breathAnalyzer.calibrated;
    _flicker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..addListener(_stepCandlePhysics);
    _physicsClock.start();
    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);

    _micSub = _mic.levels.listen(_onMicLevel);
    _motionSub = widget.accelerometerStream?.events.listen(_onMotion);
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
        .where((e) => e.type.startsWith('candle_'))
        .listen(_onPartnerEvent);
    final session = ref.read(sessionProvider).asData?.value;
    _memoryRepository = CandleMemoryRepository(
      store: ref.read(secureKeyStoreProvider),
      connectionId: session?.connectionId ?? 'local-preview',
    );
    unawaited(_loadMemory(_style));
    unawaited(_loadGpuFlameShader());
    _lastWaxTick = DateTime.now();
    _waxTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickWax());
    unawaited(_loadCandleImages());
    // A peer that kept the mode open through a transport handover can answer
    // this lightweight request with its current candle.  This closes the
    // recovery gap where a newly reopened screen used to start dark until the
    // next human interaction.
    unawaited(ref.read(modeEventBusProvider).send(const ModeEvent(
          type: 'candle_state_request',
        )));
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    var next = _quality;
    for (final timing in timings) {
      next = _qualityController.record(timing.totalSpan);
    }
    if (next != _quality && mounted) setState(() => _quality = next);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _lastPhysicsAt = Duration.zero;
        _physicsCarry = Duration.zero;
        _physicsClock
          ..reset()
          ..start();
        final smokeStillVisible = _extinguishedAt != null &&
            DateTime.now().difference(_extinguishedAt!) <
                const Duration(milliseconds: 4600);
        if ((_isLit || smokeStillVisible) && !_flicker.isAnimating) {
          _flicker.repeat();
        }
        if (_isLit && _soundEnabled) {
          unawaited(CandleSoundController.start(
            _style,
            intensity: _style.character.crackle,
          ));
        }
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _flicker.stop();
        _physicsClock.stop();
        _persistAndSyncMemory();
        unawaited(CandleSoundController.stop());
        unawaited(_player.stop());
        return;
      case AppLifecycleState.detached:
        _persistAndSyncMemory();
        unawaited(CandleSoundController.stop());
        return;
    }
  }

  void _stepCandlePhysics() {
    final now = _physicsClock.elapsed;
    var elapsed = now - _lastPhysicsAt;
    _lastPhysicsAt = now;
    if (elapsed > const Duration(milliseconds: 100)) {
      elapsed = const Duration(milliseconds: 100);
    }
    _physicsCarry += elapsed;
    var steps = 0;
    while (_physicsCarry >= _physicsStep && steps < 6) {
      _world = _physicsEngine.step(
        _world,
        CandlePhysicsInput(
          localBreath: _localWind,
          partnerBreath: _partnerWind,
          tilt: ((_localTilt + _partnerTilt) * .5).clamp(-1.0, 1.0),
          motionImpulse: (_localMotion + _partnerMotion).clamp(-1.0, 1.0),
          localShielded: _localShielded,
          partnerShielded: _partnerShielded,
          localTouchHeat: _localShielded ? 1 : 0,
          partnerTouchHeat: _partnerShielded ? 1 : 0,
        ),
        _physicsStep,
      );
      _physicsCarry -= _physicsStep;
      steps++;
    }
    if (steps > 0 && _isLit) {
      _updateSound(math.max(_localWind, _partnerWind), DateTime.now());
    }
  }

  Future<void> _loadGpuFlameShader() async {
    try {
      final program =
          await ui.FragmentProgram.fromAsset('shaders/candle_flame.frag');
      final shader = program.fragmentShader();
      if (!mounted) {
        shader.dispose();
        return;
      }
      setState(() => _gpuFlameShader = shader);
    } on Object {
      // CustomPainter's vector flame remains a complete fallback on devices
      // whose GPU driver cannot compile runtime effects.
    }
  }

  Future<void> _loadMemory(CandleStyle style) async {
    final loaded = await _memoryRepository?.load(style);
    if (!mounted || loaded == null || _style != style) return;
    setState(() => _memory = loaded);
    if (loaded.hasWish) {
      unawaited(ref.read(modeEventBusProvider).send(const ModeEvent(
            type: 'candle_wish',
            data: {'sealed': true},
          )));
    }
    _persistAndSyncMemory();
  }

  void _tickWax() {
    final now = DateTime.now();
    final previous = _lastWaxTick ?? now;
    _lastWaxTick = now;
    final lastSync = _lastMemorySyncAt;
    final shouldSync = lastSync == null ||
        now.difference(lastSync) >= const Duration(seconds: 10);
    if (!_isLit) {
      // The snapshot doubles as an inexpensive heartbeat.  When P2P falls
      // back to TURN (or returns to P2P), the first successful heartbeat
      // makes both screens converge without needing another tap.
      if (shouldSync) {
        _lastMemorySyncAt = now;
        _persistAndSyncMemory();
      }
      return;
    }
    final next = _memory.burn(
      elapsed: now.difference(previous),
      style: _style,
      localBreath: _localWind,
      partnerBreath: _partnerWind,
    );
    setState(() => _memory = next);
    if (shouldSync) {
      _lastMemorySyncAt = now;
      _persistAndSyncMemory();
    }
    if (next.isSpent && next.waxRemaining <= .081) {
      _revealWishAfterBurnout();
      _extinguishCandle();
    }
  }

  void _persistAndSyncMemory() {
    unawaited(_memoryRepository?.save(_style, _memory));
    unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
          type: 'candle_memory',
          data: {
            'style': _style.index,
            'wax': _memory.waxRemaining,
            'sessions': _memory.sessions,
            'smoke': _memory.smokeSignature,
          },
        )));
    _sendStateSnapshot();
  }

  void _sendStateSnapshot() {
    unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
          type: 'candle_state',
          data: {
            'style': _style.index,
            'lit': _isLit,
            'phase': _world.wickPhase.index,
            'energy': _world.flameEnergy,
            'wickTemperature': _world.wickTemperature,
            'moltenWax': _world.moltenWax,
          },
        )));
  }

  Future<void> _loadCandleImages() async {
    const assets = {
      CandleStyle.classic: 'assets/candles/candle_classic_natural_v2.png',
      CandleStyle.glass: 'assets/candles/candle_glass_natural_v2.png',
      CandleStyle.violet: 'assets/candles/candle_violet_natural_v2.png',
    };
    final decoded = <CandleStyle, ui.Image>{};
    ui.Image? decodedFlame;
    try {
      for (final entry in assets.entries) {
        final bytes = await rootBundle.load(entry.value);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          // The source masters stay high-resolution in the bundle, but the
          // candle never occupies enough physical pixels to justify decoding
          // them at 1K–1.5K wide on every phone.  A bounded decode keeps the
          // three materials below the frame-time and memory budget while
          // retaining ample detail on high-density displays.
          targetWidth: 720,
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        decoded[entry.key] = frame.image;
      }
      final flameBytes = await rootBundle.load(
        'assets/candles/candle_flame.png',
      );
      final flameCodec = await ui.instantiateImageCodec(
        flameBytes.buffer.asUint8List(
          flameBytes.offsetInBytes,
          flameBytes.lengthInBytes,
        ),
        targetWidth: 320,
      );
      final flameFrame = await flameCodec.getNextFrame();
      flameCodec.dispose();
      decodedFlame = flameFrame.image;
    } on Object {
      // The vector fallback below keeps the mode usable if an asset cannot
      // be decoded on an unusually constrained device.
      for (final image in decoded.values) {
        image.dispose();
      }
      decodedFlame?.dispose();
      return;
    }
    if (!mounted) {
      for (final image in decoded.values) {
        image.dispose();
      }
      decodedFlame.dispose();
      return;
    }
    setState(() {
      _candleImages.addAll(decoded);
      _flameImage = decodedFlame;
    });
  }

  void _onPartnerEvent(ModeEvent event) {
    if (!mounted) return;
    if (event.type == 'candle_light') {
      final styleIndex = (event.data['style'] as num?)?.toInt();
      if (styleIndex != null &&
          styleIndex >= 0 &&
          styleIndex < CandleStyle.values.length) {
        final partnerStyle = CandleStyle.values[styleIndex];
        if (_style != partnerStyle) {
          setState(() {
            _style = partnerStyle;
            _world = _world.copyWith(style: partnerStyle);
          });
          unawaited(_loadMemory(partnerStyle));
        }
      }
      final now = DateTime.now();
      _lastPartnerLightAt = now;
      final intent = event.data['intent'] as bool? ?? false;
      final confirmed = event.data['confirmed'] as bool? ?? false;
      if (_style.character.requiresSharedIgnition && !confirmed) {
        if (intent &&
            _waitingForSharedIgnition &&
            _lastLocalLightAt != null &&
            now.difference(_lastLocalLightAt!) < const Duration(seconds: 4)) {
          _completeSharedIgnition(broadcast: true);
        }
        return;
      }
      final shared = _isLit &&
          _lastLocalLightAt != null &&
          now.difference(_lastLocalLightAt!) < const Duration(seconds: 2);
      _lightCandle();
      if (shared || confirmed) _celebrateSharedLight();
    } else if (event.type == 'candle_blow') {
      if (!_realtimeGuard.accept('breath', event.data)) return;
      final level = (event.data['level'] as num?)?.toDouble() ?? 0;
      final extinguished =
          event.data['extinguished'] as bool? ?? level >= widget.blowThreshold;
      setState(() {
        final target = level.clamp(0.0, 1.0);
        _partnerWind = _partnerWind * 0.34 + target * 0.66;
      });
      if (level >= .16 && !_partnerWasBlowing) {
        _partnerWasBlowing = true;
        unawaited(_player.play(HapticPatterns.candleBreath));
      } else if (level < .08) {
        _partnerWasBlowing = false;
      }
      _partnerWindDecay?.cancel();
      if (!extinguished && level > 0) {
        _partnerWindDecay = Timer(const Duration(milliseconds: 450), () {
          if (mounted) {
            setState(() {
              _partnerWind = 0;
              _partnerWasBlowing = false;
            });
          }
        });
      }
      if (extinguished) _extinguishCandle();
    } else if (event.type == 'candle_motion') {
      if (!_realtimeGuard.accept('motion', event.data)) return;
      final tilt = ((event.data['tilt'] as num?)?.toDouble() ?? 0)
          .clamp(-1.0, 1.0)
          .toDouble();
      final impulse = ((event.data['impulse'] as num?)?.toDouble() ?? 0)
          .clamp(-1.0, 1.0)
          .toDouble();
      _partnerTilt = _partnerTilt * .38 + tilt * .62;
      _partnerMotion = _partnerMotion * .28 + impulse * .72;
      _partnerMotionDecay?.cancel();
      _partnerMotionDecay = Timer(const Duration(milliseconds: 380), () {
        _partnerTilt = 0;
        _partnerMotion = 0;
      });
    } else if (event.type == 'candle_shield') {
      final active = event.data['active'] as bool? ?? false;
      setState(() => _partnerShielded = active);
      if (active) unawaited(_player.play(HapticPatterns.candleShield));
      _refreshThermalBridge();
    } else if (event.type == 'candle_state_request') {
      _sendStateSnapshot();
    } else if (event.type == 'candle_state') {
      _applyPartnerSnapshot(event.data);
    } else if (event.type == 'candle_memory') {
      final styleIndex = (event.data['style'] as num?)?.toInt();
      if (styleIndex != _style.index) return;
      final remoteWax =
          ((event.data['wax'] as num?)?.toDouble() ?? 1).clamp(.08, 1.0);
      final remoteSessions =
          math.max(0, (event.data['sessions'] as num?)?.toInt() ?? 0);
      final remoteSmoke =
          ((event.data['smoke'] as num?)?.toInt() ?? 0).clamp(0, 2);
      setState(() {
        _memory = _memory.copyWith(
          waxRemaining: math.min(_memory.waxRemaining, remoteWax),
          sessions: math.max(_memory.sessions, remoteSessions),
          smokeSignature: remoteSessions > _memory.sessions
              ? remoteSmoke
              : _memory.smokeSignature,
        );
      });
      unawaited(_memoryRepository?.save(_style, _memory));
    } else if (event.type == 'candle_wish') {
      final sealed = event.data['sealed'] as bool? ?? false;
      final revealRequest = event.data['revealRequest'] as bool? ?? false;
      final revealedText = event.data['revealedText'] as String?;
      setState(() {
        if (sealed) _partnerWishSealed = true;
        if (revealRequest) _partnerRevealRequested = true;
        if (revealedText != null && revealedText.trim().isNotEmpty) {
          _partnerWish = revealedText.trim();
        }
      });
      if (_partnerRevealRequested && _localRevealRequested) {
        _shareSealedWish();
      }
    } else if (event.type == 'candle_portal') {
      setState(() {
        _partnerPortalRequested = event.data['enabled'] as bool? ?? false;
        _partnerPortalToken = (event.data['token'] as num?)?.toInt();
      });
    }
  }

  void _applyPartnerSnapshot(Map<String, Object?> data) {
    final styleIndex = (data['style'] as num?)?.toInt();
    if (styleIndex == null ||
        styleIndex < 0 ||
        styleIndex >= CandleStyle.values.length) {
      return;
    }
    final partnerStyle = CandleStyle.values[styleIndex];
    final partnerLit = data['lit'] as bool? ?? false;

    // A dark startup snapshot is not an extinguish command.  Keeping that
    // distinction prevents a reconnecting phone from accidentally blowing
    // out a candle that is still alive on the other screen.  Real
    // extinguishes continue to travel as reliable candle_blow transitions.
    if (!partnerLit) {
      if (!_isLit && _style != partnerStyle) {
        setState(() {
          _style = partnerStyle;
          _world = CandleWorldState.resting(style: partnerStyle);
        });
        unawaited(_loadMemory(partnerStyle));
      }
      return;
    }

    if (_style != partnerStyle) {
      setState(() {
        _style = partnerStyle;
        _world = _world.copyWith(style: partnerStyle);
      });
      unawaited(_loadMemory(partnerStyle));
    }
    if (!_isLit) {
      _lastPartnerLightAt = DateTime.now();
      _lightCandle();
    }
    final energy =
        ((data['energy'] as num?)?.toDouble() ?? 1).clamp(.15, 1.2).toDouble();
    final wickTemperature =
        ((data['wickTemperature'] as num?)?.toDouble() ?? .92)
            .clamp(.15, 1.2)
            .toDouble();
    final moltenWax = ((data['moltenWax'] as num?)?.toDouble() ?? .12)
        .clamp(0.0, 1.0)
        .toDouble();
    setState(() {
      _world = _world.copyWith(
        style: partnerStyle,
        wickPhase: CandleWickPhase.burning,
        flameEnergy: energy,
        wickTemperature: wickTemperature,
        moltenWax: math.max(_world.moltenWax, moltenWax),
      );
    });
  }

  void _celebrateSharedLight() {
    final now = DateTime.now();
    setState(() {
      _waitingForSharedIgnition = false;
      _sharedGlowUntil = now.add(const Duration(seconds: 2));
    });
    _sharedGlowTimer?.cancel();
    _sharedGlowTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _sharedGlowUntil = null);
    });
    unawaited(_player.play(HapticPatterns.candleTogether));
  }

  void _completeSharedIgnition({required bool broadcast}) {
    _ignitionIntentTimer?.cancel();
    _lightCandle();
    _celebrateSharedLight();
    if (broadcast) {
      unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
            type: 'candle_light',
            data: {'style': _style.index, 'confirmed': true},
          )));
    }
  }

  void _shareSealedWish() {
    final wish = _memory.sealedWish;
    if (wish == null || wish.isEmpty || _memory.wishRevealed) return;
    setState(() => _memory = _memory.copyWith(wishRevealed: true));
    unawaited(_memoryRepository?.save(_style, _memory));
    unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
          type: 'candle_wish',
          data: {'revealedText': wish},
        )));
    unawaited(_player.play(HapticPatterns.candleWish));
  }

  void _revealWishAfterBurnout() {
    _localRevealRequested = true;
    _partnerRevealRequested = true;
    _shareSealedWish();
  }

  void _onMicLevel(MicLevel sample) {
    if (!mounted) return;
    final reading = _breathAnalyzer.add(
      level: sample.level01,
      noiseLikeness: sample.noiseLikeness,
      at: sample.timestamp,
    );
    if (_calibrated != reading.calibrated ||
        (_calibrationProgress - reading.calibrationProgress).abs() >= .04) {
      setState(() {
        _calibrated = reading.calibrated;
        _calibrationProgress = reading.calibrationProgress;
      });
    }
    if (!_isLit || !reading.calibrated) return;
    final level = reading.pressure;
    // Microphone samples are noisy. A short low-pass filter keeps the flame
    // organic while still reacting quickly enough to a real breath.
    setState(() => _localWind = _localWind * 0.36 + level * 0.64);
    _sendWind(
      level,
      confidence: reading.confidence,
      extinguished: false,
      at: sample.timestamp,
    );
    _updateSound(level, sample.timestamp);
    _considerExtinguish(
      level,
      confidence: reading.confidence,
      at: sample.timestamp,
    );
  }

  void _considerExtinguish(
    double level, {
    required double confidence,
    required DateTime at,
  }) {
    final shieldCount = (_localShielded ? 1 : 0) + (_partnerShielded ? 1 : 0);
    final shield = shieldCount == 0
        ? 0.0
        : (_style.character.shieldEfficiency + (shieldCount - 1) * .07)
            .clamp(0.0, .96);
    final effectiveLevel = level * (1 - shield);
    final threshold =
        widget.blowThreshold * _style.character.extinguishResistance;
    if (effectiveLevel > threshold) {
      _blowSamplesOverThreshold++;
      if (_blowSamplesOverThreshold >= widget.requiredBlowSamples) {
        _extinguishCandle();
        _sendWind(
          level,
          confidence: confidence,
          extinguished: true,
          at: at,
          force: true,
        );
        _blowSamplesOverThreshold = 0;
      }
    } else {
      // Pressure dissipates rather than disappearing in one sample, which
      // prevents a brief microphone dip from making sustained breath feel
      // unresponsive.
      _blowSamplesOverThreshold = math.max(0, _blowSamplesOverThreshold - 1);
    }
  }

  void _sendWind(
    double level, {
    required double confidence,
    required bool extinguished,
    required DateTime at,
    bool force = false,
  }) {
    // A quiet microphone produces an endless stream of zero-value PCM
    // chunks. Send one transition back to zero after real breath, then stay
    // silent so the transport and the partner's notification layer do not
    // get flooded while the candle is simply burning.
    if (!force && level <= 0.02 && _lastWindSentLevel <= 0.02) return;
    // Twenty compact updates per second preserve breath nuance without
    // flooding the realtime transport.
    if (!force &&
        _lastWindSentAt != null &&
        at.difference(_lastWindSentAt!) < const Duration(milliseconds: 50)) {
      return;
    }
    _lastWindSentAt = at;
    _lastWindSentLevel = level;
    unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
          type: 'candle_blow',
          data: candleRealtimePayload(
            sequence: _windSequence++,
            elapsed: _physicsClock.elapsed,
            values: {
              'level': level,
              'confidence': confidence,
              'extinguished': extinguished,
            },
          ),
        )));
  }

  void _onMotion(Accel3 sample) {
    if (!_isLit) return;
    final tilt = (sample.x / 9.81).clamp(-1.0, 1.0).toDouble();
    final impulseMagnitude = (sample.netMagnitude / 5.2).clamp(0.0, 1.0);
    final direction = sample.x.abs() < .08 ? 0.0 : sample.x.sign;
    final impulse = impulseMagnitude * direction;
    _localTilt = _localTilt * .78 + tilt * .22;
    _localMotion = _localMotion * .42 + impulse * .58;

    final at = sample.timestamp;
    if (_lastMotionSentAt != null &&
        at.difference(_lastMotionSentAt!) < const Duration(milliseconds: 50)) {
      return;
    }
    if (_localTilt.abs() < .025 && _localMotion.abs() < .035) return;
    _lastMotionSentAt = at;
    unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
          type: 'candle_motion',
          data: candleRealtimePayload(
            sequence: _motionSequence++,
            elapsed: _physicsClock.elapsed,
            values: {
              'tilt': _localTilt,
              'impulse': _localMotion,
            },
          ),
        )));
  }

  void _onGestureBreath(DragUpdateDetails details) {
    if (!_gestureBreathOnly || !_isLit) return;
    final level = (details.delta.dx.abs() / 13).clamp(.04, 1.0).toDouble();
    _localWind = _localWind * .30 + level * .70;
    final now = DateTime.now();
    _sendWind(
      _localWind,
      confidence: 1,
      extinguished: false,
      at: now,
    );
    _considerExtinguish(level, confidence: 1, at: now);
    _gestureWindDecay?.cancel();
    _gestureWindDecay = Timer(const Duration(milliseconds: 260), () {
      _localWind = 0;
      _sendWind(
        0,
        confidence: 1,
        extinguished: false,
        at: DateTime.now(),
        force: true,
      );
    });
  }

  void _endGestureBreath(DragEndDetails _) {
    if (!_gestureBreathOnly) return;
    _gestureWindDecay?.cancel();
    _gestureWindDecay = Timer(const Duration(milliseconds: 120), () {
      _localWind = 0;
    });
  }

  void _updateSound(double pressure, DateTime at) {
    if (!_soundEnabled) return;
    if (_lastSoundUpdateAt != null &&
        at.difference(_lastSoundUpdateAt!) <
            const Duration(milliseconds: 180)) {
      return;
    }
    _lastSoundUpdateAt = at;
    unawaited(CandleSoundController.update(
      intensity: (.24 + _world.flameEnergy * .76) *
          (.72 + _style.character.crackle * .28),
      turbulence: math.max(_world.turbulence, pressure * .72),
      ember: _world.ember,
      sharedHeat: math.max(_world.sharedHeat, _world.sharedStillness),
    ));
  }

  void _lightCandle() {
    if (_isLit) return;
    setState(() {
      _isLit = true;
      _extinguishedAt = null;
      _blowSamplesOverThreshold = 0;
      _lastWaxTick = DateTime.now();
      _world = CandleWorldState.resting(style: _style, lit: true);
    });
    _idleAnimationTimer?.cancel();
    if (!_physicsClock.isRunning) {
      _lastPhysicsAt = Duration.zero;
      _physicsCarry = Duration.zero;
      _physicsClock
        ..reset()
        ..start();
    }
    if (!_flicker.isAnimating) _flicker.repeat();
    HapticFeedback.lightImpact();
    unawaited(_player.play(HapticPatterns.tap));
    if (_soundEnabled) {
      unawaited(CandleSoundController.ignite(_style));
    }
  }

  void _extinguishCandle() {
    if (!_isLit) return;
    setState(() {
      _isLit = false;
      _localWind = 0;
      _partnerWind = 0;
      _extinguishedAt = DateTime.now();
      _memory = _memory.finishSession();
      _world = _world.copyWith(
        wickPhase: CandleWickPhase.smoldering,
        extinguishExposure: 1,
      );
    });
    _refreshThermalBridge();
    _idleAnimationTimer?.cancel();
    _idleAnimationTimer = Timer(const Duration(milliseconds: 4600), () {
      if (!mounted || _isLit) return;
      _flicker.stop();
      _physicsClock.stop();
    });
    _persistAndSyncMemory();
    HapticFeedback.mediumImpact();
    unawaited(_player.play(HapticPatterns.candleOut));
    if (_soundEnabled) unawaited(CandleSoundController.extinguish());
  }

  void _onTap() {
    if (!_isLit) {
      _lastLocalLightAt = DateTime.now();
      if (_style.character.requiresSharedIgnition) {
        setState(() => _waitingForSharedIgnition = true);
        unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
              type: 'candle_light',
              data: {'style': _style.index, 'intent': true},
            )));
        final partnerAt = _lastPartnerLightAt;
        if (partnerAt != null &&
            DateTime.now().difference(partnerAt) < const Duration(seconds: 4)) {
          _completeSharedIgnition(broadcast: true);
          return;
        }
        _ignitionIntentTimer?.cancel();
        _ignitionIntentTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _waitingForSharedIgnition = false);
        });
      } else {
        _lightCandle();
        unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
              type: 'candle_light',
              data: {'style': _style.index},
            )));
      }
    }
  }

  void _startShield(LongPressStartDetails _) {
    if (!_isLit || _localShielded) return;
    setState(() => _localShielded = true);
    unawaited(_player.play(HapticPatterns.candleShield));
    unawaited(ref.read(modeEventBusProvider).send(const ModeEvent(
          type: 'candle_shield',
          data: {'active': true},
        )));
    _refreshThermalBridge();
  }

  void _endShield(LongPressEndDetails _) {
    if (!_localShielded) return;
    setState(() => _localShielded = false);
    unawaited(ref.read(modeEventBusProvider).send(const ModeEvent(
          type: 'candle_shield',
          data: {'active': false},
        )));
    _refreshThermalBridge();
  }

  void _refreshThermalBridge() {
    final active = _isLit && _localShielded && _partnerShielded;
    if (_bridgeActive == active) return;
    _bridgeActive = active;
    _bridgeHapticTimer?.cancel();
    if (active) {
      unawaited(_playThermalBridgeCycle());
    } else {
      unawaited(_player.stop());
    }
  }

  Future<void> _playThermalBridgeCycle() async {
    if (!_bridgeActive || !mounted) return;
    await _player.play(HapticPatterns.candleBridge);
    if (!_bridgeActive || !mounted) return;
    _bridgeHapticTimer = Timer(
      const Duration(milliseconds: 520),
      () => unawaited(_playThermalBridgeCycle()),
    );
  }

  void _togglePortal() {
    setState(() => _portalRequested = !_portalRequested);
    unawaited(_player.play(HapticPatterns.candlePortal));
    unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
          type: 'candle_portal',
          data: {'enabled': _portalRequested, 'token': _portalToken},
        )));
  }

  bool get _portalActive =>
      _portalRequested &&
      _partnerPortalRequested &&
      _partnerPortalToken != null;

  int get _portalSide {
    final partner = _partnerPortalToken;
    if (!_portalActive || partner == null) return 0;
    return _portalToken <= partner ? -1 : 1;
  }

  Future<void> _openWishSheet() async {
    final result = await showModalBottomSheet<_CandleWishResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CandleWishSheet(
        memory: _memory,
        partnerSealed: _partnerWishSealed,
        partnerWish: _partnerWish,
      ),
    );
    if (!mounted || result == null) return;
    final wish = result.sealedWish?.trim();
    if (wish != null && wish.isNotEmpty) {
      setState(() => _memory = _memory.copyWith(sealedWish: wish));
      unawaited(_memoryRepository?.save(_style, _memory));
      unawaited(ref.read(modeEventBusProvider).send(const ModeEvent(
            type: 'candle_wish',
            data: {'sealed': true},
          )));
      unawaited(_player.play(HapticPatterns.candleWish));
    }
    if (result.requestReveal) {
      setState(() => _localRevealRequested = true);
      unawaited(ref.read(modeEventBusProvider).send(const ModeEvent(
            type: 'candle_wish',
            data: {'revealRequest': true},
          )));
      if (_partnerRevealRequested) _shareSealedWish();
    }
  }

  void _selectStyle(CandleStyle style) {
    if (_style == style) return;
    if (_isLit && style.character.requiresSharedIgnition) {
      _extinguishCandle();
    }
    unawaited(_memoryRepository?.save(_style, _memory));
    setState(() {
      _style = style;
      _world = _world.copyWith(style: style);
      _waitingForSharedIgnition = false;
      _memory = CandleMemory.fresh(seed: 1);
    });
    unawaited(_loadMemory(style));
    if (_isLit && _soundEnabled) {
      unawaited(CandleSoundController.start(
        style,
        intensity: style.character.crackle,
      ));
    }
    if (_isLit) {
      unawaited(ref.read(modeEventBusProvider).send(ModeEvent(
            type: 'candle_light',
            data: {'style': style.index},
          )));
    }
  }

  void _toggleSound() {
    setState(() => _soundEnabled = !_soundEnabled);
    if (_soundEnabled && _isLit) {
      unawaited(CandleSoundController.start(
        _style,
        intensity: _style.character.crackle,
      ));
    } else {
      unawaited(CandleSoundController.stop());
    }
  }

  @override
  void dispose() {
    _micSub?.cancel();
    _motionSub?.cancel();
    _partnerSub?.cancel();
    _partnerWindDecay?.cancel();
    _partnerMotionDecay?.cancel();
    _gestureWindDecay?.cancel();
    _sharedGlowTimer?.cancel();
    _bridgeHapticTimer?.cancel();
    _waxTimer?.cancel();
    _ignitionIntentTimer?.cancel();
    _idleAnimationTimer?.cancel();
    _flicker.removeListener(_stepCandlePhysics);
    _physicsClock.stop();
    WidgetsBinding.instance.removeObserver(this);
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    unawaited(_memoryRepository?.save(_style, _memory));
    _flicker.dispose();
    unawaited(_player.stop());
    if (_ownsMic) unawaited(_mic.dispose());
    if (_ownsEngine) unawaited(_engine.cancel());
    for (final image in _candleImages.values) {
      image.dispose();
    }
    _flameImage?.dispose();
    _gpuFlameShader?.dispose();
    unawaited(CandleSoundController.stop());
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
              child: RepaintBoundary(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onTap,
                  onLongPressStart: _startShield,
                  onLongPressEnd: _endShield,
                  onHorizontalDragUpdate:
                      _gestureBreathOnly ? _onGestureBreath : null,
                  onHorizontalDragEnd:
                      _gestureBreathOnly ? _endGestureBreath : null,
                  child: AnimatedBuilder(
                    animation: _flicker,
                    builder: (context, _) {
                      final extinguishedAt = _extinguishedAt;
                      final smokeProgress = extinguishedAt == null
                          ? 1.0
                          : DateTime.now()
                                  .difference(extinguishedAt)
                                  .inMilliseconds /
                              4200;
                      final sampledForces = CandleForces.resolve(
                        localPressure: _localWind,
                        partnerPressure: _partnerWind,
                        style: _style,
                        localShielded: _localShielded,
                        partnerShielded: _partnerShielded,
                      );
                      final world = _world;
                      final forces = CandleForces(
                        lean: world.lean,
                        pressure: sampledForces.pressure,
                        turbulence: world.turbulence,
                        heightScale: world.flameHeight,
                      );
                      final sharedUntil = _sharedGlowUntil;
                      final ritualGlow = sharedUntil == null
                          ? 0.0
                          : (sharedUntil
                                      .difference(DateTime.now())
                                      .inMilliseconds /
                                  2000)
                              .clamp(0.0, 1.0)
                              .toDouble();
                      final sharedGlow = math.max(
                        ritualGlow,
                        (world.sharedHeat * .52 + world.sharedStillness * .46)
                            .clamp(0.0, 1.0),
                      );
                      final reduceMotion =
                          MediaQuery.disableAnimationsOf(context);
                      return CustomPaint(
                        painter: _CandlePainter(
                          isLit: _isLit,
                          flicker: reduceMotion ? .24 : _flicker.value,
                          forces: forces,
                          localWind: _localWind,
                          partnerWind: _partnerWind,
                          sharedGlow: sharedGlow,
                          smokeProgress: smokeProgress.clamp(0.0, 1.0),
                          showSmokeMemory: extinguishedAt != null,
                          style: _style,
                          memory: _memory,
                          localShielded: _localShielded,
                          partnerShielded: _partnerShielded,
                          portalSide: _portalSide,
                          candleImage: _candleImages[_style],
                          flameImage: _flameImage,
                          gpuFlameShader: _gpuFlameShader,
                          world: world,
                          quality: _quality,
                          reduceMotion: reduceMotion,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 126,
              child: Text(
                t.candleMemory(_memory.sessions),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .4,
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 82,
              child: Row(
                children: [
                  _CandleActionChip(
                    key: const ValueKey('candle-wish'),
                    icon: _memory.hasWish
                        ? Icons.lock_rounded
                        : Icons.auto_awesome_rounded,
                    label: _memory.hasWish ? t.candleWishSealed : t.candleWish,
                    onTap: _openWishSheet,
                  ),
                  const Spacer(),
                  _CandleActionChip(
                    key: const ValueKey('candle-portal'),
                    icon: _portalActive
                        ? Icons.mobile_friendly_rounded
                        : Icons.mobile_screen_share_rounded,
                    label: t.candlePortal,
                    active: _portalRequested,
                    onTap: _togglePortal,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 22,
              child: _CandleStylePicker(
                selected: _style,
                onSelected: _selectStyle,
              ),
            ),
            Positioned(
              top: 14,
              left: 64,
              right: 64,
              child: Text(
                !_calibrated
                    ? t.candleCalibrating
                    : _waitingForSharedIgnition
                        ? t.candleWaitingForPartner
                        : _isLit
                            ? _gestureBreathOnly
                                ? t.candleGestureBreathHint
                                : t.candleBlowHint
                            : _style.character.requiresSharedIgnition
                                ? t.candlePromiseHint
                                : t.candleTouchHint,
                maxLines: 2,
                overflow: TextOverflow.fade,
                softWrap: true,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ),
            if (!_calibrated)
              Positioned(
                top: 42,
                left: 84,
                right: 84,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    value: _calibrationProgress,
                    color: AppColors.pulse,
                    backgroundColor: Colors.white.withValues(alpha: .08),
                  ),
                ),
              ),
            if (_sharedGlowUntil != null &&
                _sharedGlowUntil!.isAfter(DateTime.now()))
              Positioned(
                top: 52,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    t.candleTogether,
                    style: const TextStyle(
                      color: Color(0xFFFFD58A),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .8,
                    ),
                  ),
                ),
              ),
            if (_portalRequested)
              Positioned(
                top: 76,
                left: 30,
                right: 30,
                child: Text(
                  _portalActive ? t.candlePortalReady : t.candlePortalWaiting,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _portalActive
                        ? const Color(0xFFD9BBFF)
                        : AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (_isLit && (_localShielded || _partnerShielded))
              Positioned(
                top: 96,
                left: 30,
                right: 30,
                child: Text(
                  t.candleShieldHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFAEDBFF),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                tooltip: _soundEnabled ? t.candleSoundOff : t.candleSoundOn,
                color: AppColors.textSecondary,
                icon: Icon(
                  _soundEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                ),
                onPressed: _toggleSound,
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

class _CandlePainter extends CustomPainter {
  _CandlePainter({
    required this.isLit,
    required this.flicker,
    required this.forces,
    required this.localWind,
    required this.partnerWind,
    required this.sharedGlow,
    required this.smokeProgress,
    required this.showSmokeMemory,
    required this.style,
    required this.memory,
    required this.localShielded,
    required this.partnerShielded,
    required this.portalSide,
    required this.candleImage,
    required this.flameImage,
    required this.gpuFlameShader,
    required this.world,
    required this.quality,
    required this.reduceMotion,
  });

  final bool isLit;
  final double flicker;
  final CandleForces forces;
  final double localWind;
  final double partnerWind;
  final double sharedGlow;
  final double smokeProgress;
  final bool showSmokeMemory;
  final CandleStyle style;
  final CandleMemory memory;
  final bool localShielded;
  final bool partnerShielded;
  final int portalSide;
  final ui.Image? candleImage;
  final ui.Image? flameImage;
  final ui.FragmentShader? gpuFlameShader;
  final CandleWorldState world;
  final CandleQualityProfile quality;
  final bool reduceMotion;

  double get wind => forces.lean;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = flicker * math.pi * 2;
    // Keep the object comfortably inside the portrait composition. Its size
    // is tied to screen width (not a cropped media viewport), while the
    // vertical anchor leaves room for the complete flame, base and shadow.
    final centerX = portalSide < 0
        ? size.width - 1
        : portalSide > 0
            ? 1.0
            : size.width / 2;
    final center = Offset(centerX, size.height * 0.46);
    final candleWidth =
        size.shortestSide * (style == CandleStyle.glass ? 0.31 : 0.255);
    final candleHeight =
        size.shortestSide * (style == CandleStyle.glass ? 0.39 : 0.46);

    final bodyRect = Rect.fromCenter(
      center: center + Offset(0, candleHeight * 0.23),
      width: candleWidth,
      height: candleHeight,
    );
    final image = candleImage;
    final photoreal =
        image == null ? null : _photorealLayout(size, image, centerX);
    final visualBody = photoreal?.visualBounds ?? bodyRect;
    final wickBase = photoreal?.wickBase ?? Offset(center.dx, bodyRect.top - 3);

    _drawAtmosphere(canvas, size, wickBase, phase);
    _drawSurfaceShadow(canvas, visualBody, visualBody.width);

    if (image != null && photoreal != null) {
      _drawPhotorealCandle(canvas, image, photoreal);
    } else {
      switch (style) {
        case CandleStyle.classic:
          _drawPillar(
            canvas,
            bodyRect,
            candleWidth,
            phase,
            const _WaxPalette(
              dark: Color(0xFF8A6A48),
              mid: Color(0xFFE7D0AA),
              light: Color(0xFFFFF8E9),
              pool: Color(0xFFFFEAC8),
            ),
          );
          break;
        case CandleStyle.glass:
          _drawGlassCandle(canvas, bodyRect, candleWidth, phase);
          break;
        case CandleStyle.violet:
          _drawPillar(
            canvas,
            bodyRect,
            candleWidth,
            phase,
            const _WaxPalette(
              dark: Color(0xFF32134F),
              mid: Color(0xFF8150B9),
              light: Color(0xFFD8B9FF),
              pool: Color(0xFFBA8BEA),
            ),
            crystalline: true,
          );
          break;
      }
      _drawWick(canvas, wickBase);
    }

    _drawThermalMaterialResponse(canvas, visualBody, wickBase, phase);
    _drawWaxMemory(canvas, visualBody, phase);
    if (portalSide != 0) _drawPortalEdge(canvas, size, phase);

    _drawAirflow(canvas, size, wickBase, phase);
    if (isLit) {
      _drawFlameContact(canvas, wickBase, visualBody, phase);
      final shader = gpuFlameShader;
      final texture = flameImage;
      if (shader != null && texture != null) {
        _drawGpuFlame(canvas, size, wickBase, shader, texture);
      } else {
        _drawFlame(canvas, wickBase, visualBody, phase);
      }
      _drawBurningWickCrown(
        canvas,
        wickBase,
        phase,
        redrawWick: candleImage == null,
      );
    } else {
      _drawExtinguishedWick(canvas, wickBase, phase);
    }
    if (localShielded || partnerShielded) {
      _drawShieldDome(canvas, wickBase, visualBody, phase);
    }
  }

  _PhotorealCandleLayout _photorealLayout(
    Size size,
    ui.Image image,
    double centerX,
  ) {
    final widthFactor = style == CandleStyle.glass ? .48 : .55;
    final imageWidth = size.shortestSide * widthFactor;
    final imageHeight = imageWidth * image.height / image.width;
    final centerY = size.height * (style == CandleStyle.glass ? .49 : .50);
    final imageRect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: imageWidth,
      height: imageHeight,
    );

    final normalized = switch (style) {
      CandleStyle.classic => const (
          left: .16,
          top: .18,
          right: .85,
          bottom: .89,
          wickY: .274,
        ),
      CandleStyle.glass => const (
          left: .12,
          top: .01,
          right: .88,
          bottom: .97,
          wickY: .135,
        ),
      CandleStyle.violet => const (
          left: .08,
          top: .035,
          right: .93,
          bottom: .94,
          wickY: .095,
        ),
    };
    final visualBounds = Rect.fromLTRB(
      imageRect.left + imageRect.width * normalized.left,
      imageRect.top + imageRect.height * normalized.top,
      imageRect.left + imageRect.width * normalized.right,
      imageRect.top + imageRect.height * normalized.bottom,
    );
    final wickBase = Offset(
      imageRect.center.dx,
      imageRect.top + imageRect.height * normalized.wickY,
    );
    return _PhotorealCandleLayout(
      imageRect: imageRect,
      visualBounds: visualBounds,
      wickBase: wickBase,
    );
  }

  void _drawPhotorealCandle(
    Canvas canvas,
    ui.Image image,
    _PhotorealCandleLayout layout,
  ) {
    // The bodies have clean alpha and neutral light. All warm illumination is
    // added from the live world state so the material cannot disagree with the
    // flame or look like a pre-lit photograph pasted behind it.
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      layout.imageRect,
      Paint()
        ..isAntiAlias = true
        ..filterQuality = quality == CandleQualityProfile.high
            ? FilterQuality.high
            : FilterQuality.medium,
    );
    // Re-light the neutral master through its own alpha. This preserves the
    // photographed silhouette and surface detail while making the body react
    // to the simulated temperature instead of remaining a static cut-out.
    final thermalAlpha =
        (world.shellTemperature * world.flameEnergy * .085).clamp(0.0, .09);
    if (thermalAlpha > .002 && quality != CandleQualityProfile.economy) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        layout.imageRect,
        Paint()
          ..color = Colors.white.withValues(alpha: thermalAlpha)
          ..colorFilter = const ColorFilter.mode(
            Color(0xFFFFA15A),
            BlendMode.modulate,
          )
          ..blendMode = BlendMode.plus
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.medium,
      );
    }
  }

  void _drawThermalMaterialResponse(
    Canvas canvas,
    Rect bounds,
    Offset wickBase,
    double phase,
  ) {
    final material = style.material;
    final energy = world.flameEnergy.clamp(0.0, 1.0);
    final molten = world.moltenWax.clamp(0.0, 1.0);
    if (energy < .002 && molten < .01) return;

    final surfaceShift = world.waxSurfaceOffset * bounds.width * .075;
    final poolCenter = wickBase + Offset(surfaceShift, 5.5);
    final poolRect = Rect.fromCenter(
      center: poolCenter,
      width: bounds.width * (.40 + molten * .16),
      height: bounds.width * (.075 + molten * .045),
    );
    final ripple = math.sin(phase * 1.7) * world.turbulence * 1.8;

    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(bounds, Radius.circular(bounds.width * .11)),
    );
    canvas.drawOval(
      poolRect.shift(Offset(ripple, 0)),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          center: Alignment(
            (world.waxSurfaceOffset * .42).clamp(-1.0, 1.0),
            -.24,
          ),
          colors: [
            const Color(0xFFFFF0C0).withValues(alpha: .18 * energy),
            const Color(0xFFFFA04E).withValues(
              alpha: .09 * energy * material.subsurfaceScattering,
            ),
            Colors.transparent,
          ],
          stops: const [0, .46, 1],
        ).createShader(poolRect),
    );

    if (style == CandleStyle.glass && quality != CandleQualityProfile.economy) {
      final refracted = Rect.fromLTWH(
        bounds.left + bounds.width * (.18 + surfaceShift / bounds.width),
        bounds.top + bounds.height * .10,
        bounds.width * .28,
        bounds.height * .80,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          refracted,
          Radius.circular(refracted.width * .42),
        ),
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFFFD79A).withValues(
                alpha: .13 * energy * material.glassRefraction,
              ),
              const Color(0xFFC99BFF).withValues(
                alpha: .055 * energy * material.glassRefraction,
              ),
              Colors.transparent,
            ],
          ).createShader(refracted)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    } else {
      final scatter = Rect.fromCircle(
        center: wickBase + const Offset(0, 24),
        radius: bounds.width * .42,
      );
      canvas.drawOval(
        scatter,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFFB568).withValues(
                alpha: .07 * energy * material.subsurfaceScattering,
              ),
              Colors.transparent,
            ],
          ).createShader(scatter),
      );
    }
    canvas.restore();
  }

  void _drawGpuFlame(
    Canvas canvas,
    Size size,
    Offset wickBase,
    ui.FragmentShader shader,
    ui.Image texture,
  ) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, flicker * 8)
      ..setFloat(3, wickBase.dx)
      ..setFloat(4, wickBase.dy)
      ..setFloat(5, forces.lean)
      ..setFloat(6, forces.pressure.clamp(0.0, 1.0))
      ..setFloat(7, style.character.warmth)
      ..setFloat(8, sharedGlow)
      ..setFloat(9, isLit ? 1 : 0)
      ..setFloat(10, world.flameEnergy)
      ..setFloat(11, world.turbulence)
      ..setFloat(12, world.coreTemperature)
      ..setFloat(13, world.ember)
      ..setImageSampler(0, texture);
    final effectBounds = Rect.fromLTRB(
      wickBase.dx - 132,
      wickBase.dy - 150,
      wickBase.dx + 132,
      wickBase.dy + 100,
    ).intersect(Offset.zero & size);
    canvas.drawRect(
      effectBounds,
      Paint()
        ..shader = shader
        ..blendMode = BlendMode.plus
        ..isAntiAlias = true,
    );
  }

  void _drawFlameContact(
    Canvas canvas,
    Offset wickBase,
    Rect body,
    double phase,
  ) {
    final energy = world.flameEnergy.clamp(0.0, 1.0);
    final pulse = (.92 + math.sin(phase * 2.4) * .08) * energy;
    final poolCenter = wickBase +
        Offset(
          forces.lean * 1.4 + world.waxSurfaceOffset * body.width * .07,
          8,
        );
    final pool = Rect.fromCenter(
      center: poolCenter,
      width: body.width * (.42 + sharedGlow * .05),
      height: body.width * .13,
    );

    // The light must visibly belong to the wax before the emissive flame is
    // drawn. This warm pool is the contact shadow's inverse: it anchors the
    // fire to the material instead of letting it float above a photograph.
    canvas.drawOval(
      pool,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFD58A).withValues(alpha: .24 * pulse),
            const Color(0xFFFF8A39).withValues(alpha: .08 * pulse),
            Colors.transparent,
          ],
          stops: const [0, .46, 1],
        ).createShader(pool)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
    );
    if (quality == CandleQualityProfile.economy) return;
    canvas.drawCircle(
      wickBase + const Offset(0, 1),
      5.2,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: .34 * pulse),
            const Color(0xFFFF6A2C).withValues(alpha: .18 * pulse),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(
          center: wickBase + const Offset(0, 1),
          radius: 5.2,
        )),
    );
  }

  void _drawBurningWickCrown(
    Canvas canvas,
    Offset wickBase,
    double phase, {
    required bool redrawWick,
  }) {
    final sway = forces.lean * 1.1 + math.sin(phase * 2.1) * .22;
    if (redrawWick) {
      final path = Path()
        ..moveTo(wickBase.dx + .2, wickBase.dy + 1.2)
        ..cubicTo(
          wickBase.dx - .6,
          wickBase.dy - .6,
          wickBase.dx + sway,
          wickBase.dy - 3.5,
          wickBase.dx + sway * .72,
          wickBase.dy - 6.4,
        );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.25
          ..color = const Color(0xFF1B1112).withValues(alpha: .88),
      );
    }
    canvas.drawCircle(
      wickBase + Offset(sway * .72, -6.4),
      1.25,
      Paint()
        ..color = const Color(0xFFFF8A3D).withValues(
          alpha: .72 + math.sin(phase * 3.6) * .10,
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .7),
    );
  }

  void _drawWaxMemory(Canvas canvas, Rect bounds, double phase) {
    if (bounds.isEmpty) return;
    final consumed = 1 - memory.waxRemaining;
    final visibleTop = bounds.top + bounds.height * consumed * .22;
    final memoryBounds = Rect.fromLTRB(
      bounds.left,
      visibleTop,
      bounds.right,
      bounds.bottom,
    );
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(bounds, Radius.circular(bounds.width * .10)),
    );

    // The shared candle grows thin translucent strata rather than displaying
    // a conventional progress bar. Each completed ritual adds one layer.
    final layers = math.min(8, memory.sessions);
    for (var i = 0; i < layers; i++) {
      final seed = memory.signatureSeed * .0001 + i * 1.73;
      final y = memoryBounds.bottom -
          memoryBounds.height * (.10 + i / math.max(10, layers + 3));
      final path = Path()..moveTo(memoryBounds.left, y);
      for (var step = 1; step <= 6; step++) {
        final x = memoryBounds.left + memoryBounds.width * step / 6;
        final wave =
            math.sin(seed + step * 1.41 + phase * .12) * (1.6 + (i % 3));
        path.lineTo(x, y + wave);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1 + (i.isEven ? .4 : 0)
          ..color = Color.lerp(
            const Color(0xFFFFB65F),
            const Color(0xFFC18BFF),
            i / math.max(1, layers - 1),
          )!
              .withValues(alpha: .13 + memory.sharedBreath * .11),
      );
    }

    // The current burn amount stays in the simulation and encrypted memory.
    // Only completed shared sessions become visible strata: a transient level
    // line looks artificial against the candle's irregular photoreal rim.
    canvas.restore();
  }

  void _drawShieldDome(
    Canvas canvas,
    Offset wickBase,
    Rect body,
    double phase,
  ) {
    final count = (localShielded ? 1 : 0) + (partnerShielded ? 1 : 0);
    final pulse = .72 + math.sin(phase * 1.4) * .08;
    final dome = Rect.fromCenter(
      center: Offset(wickBase.dx, wickBase.dy + body.width * .10),
      width: body.width * 1.72,
      height: body.width * 1.38,
    );
    canvas.drawArc(
      dome,
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = count == 2 ? 2.2 : 1.35
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            const Color(0xFFBBDFFF).withValues(alpha: .55 * pulse),
            const Color(0xFFE1C6FF).withValues(alpha: .35 * pulse),
            Colors.transparent,
          ],
        ).createShader(dome)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8),
    );
    canvas.drawOval(
      dome,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -.45),
          colors: [
            const Color(0xFFBFE6FF).withValues(alpha: .055 * count),
            Colors.transparent,
          ],
        ).createShader(dome),
    );
  }

  void _drawPortalEdge(Canvas canvas, Size size, double phase) {
    final left = portalSide > 0;
    final rect = Rect.fromLTWH(left ? 0 : size.width - 8, 0, 8, size.height);
    final pulse = .64 + math.sin(phase * 1.3) * .18;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            const Color(0xFFC28CFF).withValues(alpha: .42 * pulse),
            const Color(0xFFFFA66B).withValues(alpha: .36 * pulse),
            Colors.transparent,
          ],
        ).createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
  }

  void _drawAtmosphere(
    Canvas canvas,
    Size size,
    Offset wickBase,
    double phase,
  ) {
    final character = style.character;
    final pulse = 0.96 +
        math.sin(phase * 1.7) * 0.04 * character.flickerAmount +
        forces.turbulence * math.sin(phase * 5.3) * .025;
    final center = wickBase + Offset(wind * 8, -34);
    final radiusFactor = switch (quality) {
      CandleQualityProfile.high => .72,
      CandleQualityProfile.balanced => .60,
      CandleQualityProfile.economy => .50,
    };
    final rect = Rect.fromCircle(
      center: center,
      radius: size.shortestSide * radiusFactor,
    );
    final energy = world.flameEnergy.clamp(0.0, 1.0);
    final warmAlpha = isLit
        ? (0.20 + sharedGlow * .12) *
            pulse *
            character.warmth *
            (.30 + energy * .70)
        : 0.0;
    // Rasterize only the area where the radial gradient has visible energy.
    // Drawing a transparent shader over the entire physical display wasted
    // millions of fragments per second on high-density phones.
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.16),
          radius: 0.84,
          colors: [
            Color.lerp(
              const Color(0xFFFFA34A),
              const Color(0xFFC380FF),
              style == CandleStyle.violet ? .24 : 0,
            )!
                .withValues(alpha: warmAlpha),
            const Color(0xFF7132A6).withValues(alpha: isLit ? 0.10 : 0.04),
            Colors.transparent,
          ],
          stops: const [0, 0.42, 1],
        ).createShader(rect),
    );

    if (!isLit) return;
    canvas.drawCircle(
      center,
      118,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFC36A).withValues(alpha: 0.15 * pulse * energy),
            const Color(0xFFFF8A38).withValues(alpha: 0.045 * pulse * energy),
            Colors.transparent,
          ],
          stops: const [0, .38, 1],
        ).createShader(Rect.fromCircle(center: center, radius: 118)),
    );
  }

  void _drawSurfaceShadow(Canvas canvas, Rect bodyRect, double candleWidth) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(bodyRect.center.dx - wind * 4, bodyRect.bottom + 9),
        width: candleWidth * 1.7,
        height: candleWidth * .34,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.52)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    if (!isLit) return;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(bodyRect.center.dx + wind * 8, bodyRect.bottom + 7),
        width: candleWidth * 1.25,
        height: candleWidth * .22,
      ),
      Paint()
        ..color = const Color(0xFFFF9E43).withValues(alpha: 0.13)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
  }

  void _drawPillar(
    Canvas canvas,
    Rect bodyRect,
    double candleWidth,
    double phase,
    _WaxPalette palette, {
    bool crystalline = false,
  }) {
    final body = RRect.fromRectAndRadius(bodyRect, const Radius.circular(8));
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          colors: [
            palette.dark,
            palette.mid,
            palette.light,
            palette.mid,
            palette.dark,
          ],
          stops: const [0, .19, .47, .72, 1],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(bodyRect),
    );

    // Fine vertical wax texture breaks the perfectly digital gradient.
    final texture = Paint()
      ..strokeWidth = .7
      ..color = Colors.white.withValues(alpha: crystalline ? .06 : .09);
    for (var i = 1; i < 9; i++) {
      final x = bodyRect.left + bodyRect.width * i / 10;
      final wobble = math.sin(i * 2.7) * 1.8;
      canvas.drawLine(
        Offset(x, bodyRect.top + 14 + wobble),
        Offset(x + wobble, bodyRect.bottom - 8),
        texture,
      );
    }

    // Rounded top, recessed molten pool and irregular rim create depth.
    final topOval = Rect.fromCenter(
      center: Offset(bodyRect.center.dx, bodyRect.top + 2),
      width: candleWidth,
      height: candleWidth * .31,
    );
    canvas.drawOval(topOval, Paint()..color = palette.light);
    final poolRect = Rect.fromCenter(
      center: topOval.center + const Offset(0, 1),
      width: candleWidth * .69,
      height: candleWidth * .18,
    );
    canvas.drawOval(
      poolRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            palette.pool.withValues(alpha: isLit ? .98 : .72),
            palette.mid.withValues(alpha: .88),
          ],
        ).createShader(poolRect),
    );
    canvas.drawArc(
      topOval.deflate(1),
      math.pi * .04,
      math.pi * .9,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );

    final drip = Path()
      ..moveTo(bodyRect.right - candleWidth * .26, bodyRect.top + 3)
      ..cubicTo(
        bodyRect.right - candleWidth * .20,
        bodyRect.top + 22,
        bodyRect.right - candleWidth * .26,
        bodyRect.top + 49,
        bodyRect.right - candleWidth * .35,
        bodyRect.top + 52,
      )
      ..cubicTo(
        bodyRect.right - candleWidth * .43,
        bodyRect.top + 38,
        bodyRect.right - candleWidth * .41,
        bodyRect.top + 17,
        bodyRect.right - candleWidth * .43,
        bodyRect.top + 5,
      )
      ..close();
    canvas.drawPath(drip, Paint()..color = palette.mid.withValues(alpha: .72));

    if (crystalline) {
      final glint = Paint()
        ..color = const Color(0xFFECCFFF).withValues(alpha: .55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      for (var i = 0; i < 7; i++) {
        final x = bodyRect.left + 12 + (i * 17.0) % (bodyRect.width - 24);
        final y = bodyRect.top + 28 + (i * 31.0) % (bodyRect.height - 42);
        final r = i.isEven ? 1.4 : .8;
        canvas.drawCircle(Offset(x, y), r, glint);
      }
    }

    if (isLit) {
      canvas.drawOval(
        Rect.fromCenter(
          center: bodyRect.topCenter + Offset(wind * 3, 8),
          width: candleWidth * .78,
          height: candleWidth * .32,
        ),
        Paint()
          ..color = const Color(0xFFFFB85B).withValues(alpha: .14)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  void _drawGlassCandle(
    Canvas canvas,
    Rect bodyRect,
    double candleWidth,
    double phase,
  ) {
    final radius = Radius.circular(candleWidth * .28);
    final glass = RRect.fromRectAndRadius(bodyRect, radius);
    final waxRect = Rect.fromLTRB(
      bodyRect.left + 7,
      bodyRect.top + bodyRect.height * .31,
      bodyRect.right - 7,
      bodyRect.bottom - 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(waxRect, Radius.circular(candleWidth * .20)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFB58ADD), Color(0xFF7847A6), Color(0xFF3C1D58)],
          stops: [0, .48, 1],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(waxRect),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(waxRect.center.dx, waxRect.top + 2),
        width: waxRect.width,
        height: candleWidth * .18,
      ),
      Paint()..color = const Color(0xFFD7B4F4).withValues(alpha: .88),
    );
    canvas.drawRRect(
      glass,
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFF9B86C8).withValues(alpha: .18),
            Colors.white.withValues(alpha: .20),
            const Color(0xFF38234F).withValues(alpha: .16),
            Colors.white.withValues(alpha: .08),
          ],
          stops: const [0, .22, .62, 1],
        ).createShader(bodyRect),
    );
    canvas.drawRRect(
      glass,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: .38),
    );

    // Thick glass rim and asymmetric specular streaks.
    final rim = Rect.fromCenter(
      center: Offset(bodyRect.center.dx, bodyRect.top + 4),
      width: bodyRect.width,
      height: candleWidth * .26,
    );
    canvas.drawOval(
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: .18),
            Colors.white.withValues(alpha: .65),
            const Color(0xFF725694).withValues(alpha: .35),
          ],
        ).createShader(rim),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          bodyRect.left + 11,
          bodyRect.top + 20,
          4,
          bodyRect.height * .58,
        ),
        const Radius.circular(4),
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: .34)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          bodyRect.right - 12,
          bodyRect.top + 35,
          2,
          bodyRect.height * .33,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = Colors.white.withValues(alpha: .13),
    );

    if (isLit) {
      final reflection = Offset(
        bodyRect.center.dx + math.sin(phase * 1.3) * 2,
        waxRect.top + 9,
      );
      canvas.drawCircle(
        reflection,
        candleWidth * .36,
        Paint()
          ..color = const Color(0xFFFFA84D).withValues(alpha: .12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }
  }

  void _drawWick(Canvas canvas, Offset wickBase) {
    final wick = Path()
      ..moveTo(wickBase.dx, wickBase.dy + 13)
      ..quadraticBezierTo(
        wickBase.dx - 1.5,
        wickBase.dy + 5,
        wickBase.dx + wind * 1.5,
        wickBase.dy,
      );
    canvas.drawPath(
      wick,
      Paint()
        ..color = const Color(0xFF251B1A)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawFlame(
    Canvas canvas,
    Offset wickBase,
    Rect bodyRect,
    double phase,
  ) {
    final character = style.character;
    final gust = forces.pressure.clamp(0.0, 1.0);
    final unstable = forces.turbulence;
    final turbulence =
        (math.sin(phase * 1.9) * 2.2 + math.sin(phase * 3.7 + 1.2) * 1.0) *
                character.flickerAmount +
            math.sin(phase * 7.1) * unstable * 3.4;
    final height = 45.0 * forces.heightScale +
        math.sin(phase * 2.3) * 2.7 * character.flickerAmount;
    final width = 16.5 +
        gust * 5 +
        unstable * 4 +
        math.cos(phase * 2.8) * 1.2 * character.flickerAmount;
    final lean = wind * (25 + gust * 15) + turbulence;
    final base = wickBase + const Offset(0, 2);
    final tip = base + Offset(lean, -height);
    final glowCenter = Offset.lerp(base, tip, .52)!;

    canvas.drawCircle(
      glowCenter,
      90 - gust * 13 + sharedGlow * 16,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFC35F).withValues(
              alpha: .40 - gust * .09 + sharedGlow * .08,
            ),
            const Color(0xFFFF8738).withValues(alpha: .13 - gust * .04),
            Colors.transparent,
          ],
          stops: const [0, .34, 1],
        ).createShader(
          Rect.fromCircle(
            center: glowCenter,
            radius: 90 - gust * 13 + sharedGlow * 16,
          ),
        ),
    );

    final sprite = flameImage;
    if (sprite != null) {
      _drawFlameSprite(
        canvas,
        sprite,
        base: base,
        height: height,
        width: width,
        gust: gust,
        phase: phase,
      );
    } else {
      final bounds = Rect.fromLTRB(
        math.min(base.dx, tip.dx) - width,
        tip.dy,
        math.max(base.dx, tip.dx) + width,
        base.dy + 5,
      );
      final outer = _flamePath(base: base, tip: tip, width: width);
      canvas.drawPath(
        outer,
        Paint()
          ..shader = const LinearGradient(
            colors: [
              Color(0xFFFFF4A8),
              Color(0xFFFFC54D),
              Color(0xFFFF7B2F),
              Color(0xFFE43D18),
            ],
            stops: [0, .35, .76, 1],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(bounds),
      );

      final innerTip = Offset.lerp(base, tip, .64)! + Offset(wind * 2, 2);
      final inner = _flamePath(
        base: base + const Offset(0, 1),
        tip: innerTip,
        width: width * .43,
      );
      canvas.drawPath(
        inner,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = const LinearGradient(
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFFFF0A0),
              Color(0xFFFFA33C),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(bounds),
      );

      canvas.drawOval(
        Rect.fromCenter(center: base, width: width * .78, height: 9),
        Paint()
          ..color = const Color(0xFF769CFF).withValues(alpha: .62)
          ..blendMode = BlendMode.plus,
      );
    }

    _drawInnerFlame(canvas, base, tip, width, phase, unstable);
    _drawHeatShimmer(canvas, tip, phase, unstable);

    // Warm reflection in the molten wax/glass immediately below the flame.
    canvas.drawOval(
      Rect.fromCenter(
        center: bodyRect.topCenter + const Offset(0, 6),
        width: bodyRect.width * .72,
        height: bodyRect.width * .24,
      ),
      Paint()
        ..color = const Color(0xFFFFB349).withValues(alpha: .18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
  }

  void _drawInnerFlame(
    Canvas canvas,
    Offset base,
    Offset tip,
    double width,
    double phase,
    double unstable,
  ) {
    final innerTip = Offset.lerp(base, tip, .58)! +
        Offset(math.sin(phase * 3.1) * (1 + unstable * 2), 2);
    final inner = _flamePath(
      base: base + const Offset(0, 1),
      tip: innerTip,
      width: width * .34,
    );
    final bounds = Rect.fromPoints(
      Offset(base.dx - width, tip.dy),
      Offset(base.dx + width, base.dy + 4),
    );
    canvas.drawPath(
      inner,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: .82),
            const Color(0xFFFFE985).withValues(alpha: .72),
            const Color(0xFFFF9A36).withValues(alpha: .38),
          ],
        ).createShader(bounds),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: base + const Offset(0, 1.8),
        width: width * .48,
        height: 4.2,
      ),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = const RadialGradient(
          colors: [Color(0xA0B8D2FF), Color(0x705278FF), Colors.transparent],
          stops: [0, .46, 1],
        ).createShader(Rect.fromCircle(center: base, radius: width)),
    );
  }

  void _drawHeatShimmer(
    Canvas canvas,
    Offset tip,
    double phase,
    double unstable,
  ) {
    for (var i = 0; i < 3; i++) {
      final rise = 18.0 + i * 14;
      final drift =
          math.sin(phase * (1.1 + i * .17) + i * 2.1) * (3 + unstable * 5);
      final path = Path()
        ..moveTo(tip.dx, tip.dy - 2 - i * 2)
        ..quadraticBezierTo(
          tip.dx - drift,
          tip.dy - rise * .55,
          tip.dx + drift,
          tip.dy - rise,
        );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFFFFD69A).withValues(alpha: .045 - i * .01)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
      );
    }
  }

  void _drawFlameSprite(
    Canvas canvas,
    ui.Image image, {
    required Offset base,
    required double height,
    required double width,
    required double gust,
    required double phase,
  }) {
    final spriteHeight = height * (1.50 - gust * .18);
    final spriteWidth = width * (3.0 + gust * .42);
    final angle = wind * (.28 + gust * .12) + math.sin(phase * 2.1) * .018;
    canvas.save();
    canvas.translate(base.dx, base.dy + 2);
    canvas.rotate(angle);
    canvas.scale(1 + gust * .18, 1 - gust * .16);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTRB(
        -spriteWidth / 2,
        -spriteHeight,
        spriteWidth / 2,
        4,
      ),
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  Path _flamePath({
    required Offset base,
    required Offset tip,
    required double width,
  }) {
    final direction = tip - base;
    return Path()
      ..moveTo(base.dx, base.dy + 3)
      ..cubicTo(
        base.dx - width * .85,
        base.dy + direction.dy * .24,
        tip.dx - width * .34,
        tip.dy - direction.dy * .16,
        tip.dx,
        tip.dy,
      )
      ..cubicTo(
        tip.dx + width * .42,
        tip.dy - direction.dy * .18,
        base.dx + width * .86,
        base.dy + direction.dy * .27,
        base.dx,
        base.dy + 3,
      )
      ..close();
  }

  void _drawAirflow(
    Canvas canvas,
    Size size,
    Offset wickBase,
    double phase,
  ) {
    void stream(double strength, bool fromLeft) {
      if (strength < .06) return;
      final alpha = (.10 + strength * .22).clamp(0.0, .30);
      final direction = fromLeft ? 1.0 : -1.0;
      final paint = Paint()
        ..color = const Color(0xFFDCCBFF).withValues(alpha: alpha)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .6);
      final streams = switch (quality) {
        CandleQualityProfile.high => 4,
        CandleQualityProfile.balanced => 3,
        CandleQualityProfile.economy => 2,
      };
      for (var i = 0; i < streams; i++) {
        final travel = (flicker * (1.15 + i * .08) + i * .23) % 1;
        final startX = fromLeft
            ? size.width * .10 + travel * size.width * .30
            : size.width * .90 - travel * size.width * .30;
        final y = wickBase.dy - 42 + i * 14 + math.sin(phase + i) * 3;
        final length = 10 + strength * 18;
        canvas.drawLine(
          Offset(startX, y),
          Offset(startX + direction * length, y + math.sin(i * 1.8) * 2),
          paint,
        );
      }
    }

    stream(localWind, true);
    stream(partnerWind, false);
  }

  void _drawExtinguishedWick(Canvas canvas, Offset wickBase, double phase) {
    final timedEmber = smokeProgress < .30 ? (1 - smokeProgress / .30) : 0.0;
    final emberAlpha = math.max(timedEmber, world.ember);
    if (emberAlpha > 0) {
      canvas.drawCircle(
        wickBase,
        8,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFF7A37).withValues(alpha: emberAlpha * .75),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: wickBase, radius: 8)),
      );
    }

    if (showSmokeMemory && smokeProgress > .34) {
      _drawSmokeSigil(canvas, wickBase, phase);
    }
    if (smokeProgress >= 1 && world.smokeDensity < .015) return;
    final timedFade =
        smokeProgress >= 1 ? 0.0 : math.pow(1 - smokeProgress, 1.45).toDouble();
    final fade = math.max(timedFade, world.smokeDensity).clamp(0.0, 1.0);
    final rise = 24 + smokeProgress * 88;
    final drift = math.sin(phase * .55 + smokeProgress * 4) * 12 +
        world.lean * 20 +
        world.turbulence * math.sin(phase * 2.7) * 7 +
        smokeProgress * 8;
    final trails = switch (quality) {
      CandleQualityProfile.high => 4,
      CandleQualityProfile.balanced => 3,
      CandleQualityProfile.economy => 2,
    };
    for (var i = 0; i < trails; i++) {
      final offset = (i - 1) * 3.0;
      final smoke = Path()
        ..moveTo(wickBase.dx + offset, wickBase.dy - 1)
        ..cubicTo(
          wickBase.dx - 9 + offset,
          wickBase.dy - rise * .28,
          wickBase.dx + 13 + drift * .35,
          wickBase.dy - rise * .56,
          wickBase.dx + drift + offset,
          wickBase.dy - rise,
        );
      canvas.drawPath(
        smoke,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2 - i * .75
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFC9BED4).withValues(
            alpha: fade * (.18 - i * .035),
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.5 + i),
      );
    }
  }

  void _drawSmokeSigil(Canvas canvas, Offset wickBase, double phase) {
    final reveal = ((smokeProgress - .34) / .46).clamp(0.0, 1.0);
    final center = wickBase +
        Offset(
          math.sin(phase * .42) * 4,
          -92 - reveal * 18,
        );
    final scale = 18 + reveal * 11;
    final path = Path();
    switch (memory.smokeSignature) {
      case 0:
        // A continuous infinity path: two people, one unbroken trace.
        path.moveTo(center.dx - scale, center.dy);
        path.cubicTo(
          center.dx - scale * .45,
          center.dy - scale,
          center.dx + scale * .45,
          center.dy + scale,
          center.dx + scale,
          center.dy,
        );
        path.cubicTo(
          center.dx + scale * .45,
          center.dy - scale,
          center.dx - scale * .45,
          center.dy + scale,
          center.dx - scale,
          center.dy,
        );
        break;
      case 1:
        // A softly imperfect heart created from the session's smoke.
        path.moveTo(center.dx, center.dy + scale * .82);
        path.cubicTo(
          center.dx - scale * 1.30,
          center.dy + scale * .05,
          center.dx - scale * .75,
          center.dy - scale,
          center.dx,
          center.dy - scale * .26,
        );
        path.cubicTo(
          center.dx + scale * .75,
          center.dy - scale,
          center.dx + scale * 1.30,
          center.dy + scale * .05,
          center.dx,
          center.dy + scale * .82,
        );
        break;
      default:
        // Two orbits cross once and continue, like two separate lives
        // touching without becoming identical.
        path.addOval(Rect.fromCenter(
          center: center + Offset(-scale * .28, 0),
          width: scale * 1.45,
          height: scale * .72,
        ));
        path.addOval(Rect.fromCenter(
          center: center + Offset(scale * .28, 0),
          width: scale * 1.45,
          height: scale * .72,
        ));
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.1
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(
          const Color(0xFFC8BDD3),
          const Color(0xFFD9B9FF),
          memory.sharedBreath,
        )!
            .withValues(alpha: .08 + reveal * .42)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4),
    );
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) =>
      old.isLit != isLit ||
      old.flicker != flicker ||
      old.forces.lean != forces.lean ||
      old.forces.pressure != forces.pressure ||
      old.forces.turbulence != forces.turbulence ||
      old.forces.heightScale != forces.heightScale ||
      old.localWind != localWind ||
      old.partnerWind != partnerWind ||
      old.sharedGlow != sharedGlow ||
      old.smokeProgress != smokeProgress ||
      old.showSmokeMemory != showSmokeMemory ||
      old.memory != memory ||
      old.localShielded != localShielded ||
      old.partnerShielded != partnerShielded ||
      old.portalSide != portalSide ||
      old.candleImage != candleImage ||
      old.flameImage != flameImage ||
      old.gpuFlameShader != gpuFlameShader ||
      old.world.flameEnergy != world.flameEnergy ||
      old.world.coreTemperature != world.coreTemperature ||
      old.world.shellTemperature != world.shellTemperature ||
      old.world.moltenWax != world.moltenWax ||
      old.world.waxSurfaceOffset != world.waxSurfaceOffset ||
      old.world.smokeDensity != world.smokeDensity ||
      old.world.ember != world.ember ||
      old.world.sharedHeat != world.sharedHeat ||
      old.world.sharedStillness != world.sharedStillness ||
      old.quality != quality ||
      old.reduceMotion != reduceMotion ||
      old.style != style;
}

class _PhotorealCandleLayout {
  const _PhotorealCandleLayout({
    required this.imageRect,
    required this.visualBounds,
    required this.wickBase,
  });

  final Rect imageRect;
  final Rect visualBounds;
  final Offset wickBase;
}

class _WaxPalette {
  const _WaxPalette({
    required this.dark,
    required this.mid,
    required this.light,
    required this.pool,
  });

  final Color dark;
  final Color mid;
  final Color light;
  final Color pool;
}

class _CandleStylePicker extends StatelessWidget {
  const _CandleStylePicker({required this.selected, required this.onSelected});

  final CandleStyle selected;
  final ValueChanged<CandleStyle> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final labels = [t.candleClassic, t.candleGlass, t.candleViolet];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF211631).withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          children: CandleStyle.values.map((style) {
            final active = style == selected;
            return Expanded(
              child: Semantics(
                selected: active,
                button: true,
                child: InkWell(
                  key: ValueKey('candle-style-${style.name}'),
                  borderRadius: BorderRadius.circular(19),
                  onTap: () => onSelected(style),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.pulse.withValues(alpha: 0.28)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: Text(
                      labels[style.index],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: active ? Colors.white : AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(growable: false),
        ),
      ),
    );
  }
}

class _CandleActionChip extends StatelessWidget {
  const _CandleActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? AppColors.pulse.withValues(alpha: .28)
          : const Color(0xFF211631).withValues(alpha: .82),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: const Color(0xFFD9BCFF)),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 126),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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

class _CandleWishResult {
  const _CandleWishResult({this.sealedWish, this.requestReveal = false});

  final String? sealedWish;
  final bool requestReveal;
}

class _CandleWishSheet extends StatefulWidget {
  const _CandleWishSheet({
    required this.memory,
    required this.partnerSealed,
    required this.partnerWish,
  });

  final CandleMemory memory;
  final bool partnerSealed;
  final String? partnerWish;

  @override
  State<_CandleWishSheet> createState() => _CandleWishSheetState();
}

class _CandleWishSheetState extends State<_CandleWishSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final hasWish = widget.memory.hasWish;
    final partnerWish = widget.partnerWish;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFF171020),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        color: Color(0xFFD7B3FF),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        t.candleWish,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t.candleWishHint,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (!hasWish) ...[
                    TextField(
                      key: const ValueKey('candle-wish-field'),
                      controller: _controller,
                      autofocus: true,
                      maxLength: 80,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: .055),
                        hintText: t.candleWish,
                        hintStyle: const TextStyle(color: AppColors.textMuted),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      key: const ValueKey('candle-seal-wish'),
                      onPressed: () {
                        final value = _controller.text.trim();
                        if (value.isEmpty) return;
                        Navigator.pop(
                          context,
                          _CandleWishResult(sealedWish: value),
                        );
                      },
                      child: Text(t.candleSealWish),
                    ),
                  ] else ...[
                    _WishStatusLine(
                      icon: Icons.lock_rounded,
                      text: t.candleWishSealed,
                    ),
                    if (widget.partnerSealed)
                      _WishStatusLine(
                        icon: Icons.favorite_rounded,
                        text: t.candlePartnerWishSealed,
                      ),
                    if (partnerWish != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        t.candlePartnerWish,
                        style: const TextStyle(
                          color: Color(0xFFD7B3FF),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        partnerWish,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          height: 1.4,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                        key: const ValueKey('candle-reveal-wish'),
                        onPressed: () => Navigator.pop(
                          context,
                          const _CandleWishResult(requestReveal: true),
                        ),
                        child: Text(t.candleRevealWish),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WishStatusLine extends StatelessWidget {
  const _WishStatusLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFFD7B3FF)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
