import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../capabilities/application/capability_providers.dart';
import '../../../capabilities/domain/device_capability.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import '../../application/whisper/audio_feeling_controller.dart';
import '../../application/whisper/whisper_feeling.dart';
import '../../application/whisper/whisper_protocol.dart';
import '../../primitives/haptic_pattern_player.dart';
import '../../primitives/mic_level_stream.dart';
import '../../primitives/primitive_providers.dart';
import 'unsupported_mode_screen.dart';

/// A privacy-first Audio-to-Feeling experience.
///
/// Microphone samples are reduced locally to intensity, breathiness and
/// perceived proximity. Only those non-reversible parameters cross the
/// encrypted session. When microphone access is unavailable, holding the
/// central surface sends the same kind of feeling without capturing audio.
class WhisperModeScreen extends ConsumerWidget {
  const WhisperModeScreen({
    super.key,
    this.micLevelStream,
    this.hapticEngine,
    this.threshold = 0.15,
    this.requiredConsecutive = 2,
  });

  final MicLevelStream? micLevelStream;
  final HapticEngine? hapticEngine;
  final double threshold;
  final int requiredConsecutive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
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
    if (!caps.has(DeviceCapability.vibration)) {
      return UnsupportedModeScreen(
        title: t.modeWhisper,
        missing: const {DeviceCapability.vibration},
      );
    }
    final hasMicrophone = caps.has(DeviceCapability.microphone);
    return _WhisperModeView(
      micLevelStream: hasMicrophone
          ? micLevelStream ?? ref.watch(micLevelStreamProvider)
          : null,
      hapticEngine: hapticEngine ?? ref.watch(hapticEngineProvider),
      threshold: threshold,
      requiredConsecutive: requiredConsecutive,
      hasMicrophone: hasMicrophone,
    );
  }
}

class _WhisperModeView extends ConsumerStatefulWidget {
  const _WhisperModeView({
    required this.micLevelStream,
    required this.hapticEngine,
    required this.threshold,
    required this.requiredConsecutive,
    required this.hasMicrophone,
  });

  final MicLevelStream? micLevelStream;
  final HapticEngine hapticEngine;
  final double threshold;
  final int requiredConsecutive;
  final bool hasMicrophone;

  @override
  ConsumerState<_WhisperModeView> createState() => _WhisperModeViewState();
}

class _WhisperModeViewState extends ConsumerState<_WhisperModeView>
    with SingleTickerProviderStateMixin {
  final AudioFeelingController _feelingController = AudioFeelingController();
  final WhisperReceiver _receiver = WhisperReceiver();
  StreamSubscription<MicLevel>? _micSubscription;
  StreamSubscription<ModeEvent>? _partnerSubscription;
  late final HapticPatternPlayer _hapticPlayer;
  late final AnimationController _motion;
  Timer? _fallbackTimer;
  DateTime? _fallbackStartedAt;
  WhisperFeeling? _local;
  WhisperFeeling? _partner;
  DateTime? _partnerReceivedAt;
  int _partnerTicksOverThreshold = 0;
  bool _manualSending = false;

  @override
  void initState() {
    super.initState();
    _hapticPlayer = HapticPatternPlayer(widget.hapticEngine);
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();
    _micSubscription = widget.micLevelStream?.levels.listen(_onMicLevel);
    _partnerSubscription = ref
        .read(modeEventBusProvider)
        .incoming
        .where((event) => event.type == WhisperProtocol.eventType)
        .listen(_onPartnerEvent);
  }

  void _onMicLevel(MicLevel sample) {
    if (!mounted || _manualSending) return;
    final feeling = _feelingController.process(sample);
    setState(() => _local = feeling);
    _sendIfNeeded(feeling);
  }

  void _onPartnerEvent(ModeEvent event) {
    final feeling = WhisperProtocol.tryDecode(event);
    if (!mounted || feeling == null || !_receiver.accept(feeling)) return;
    setState(() {
      _partner = feeling;
      _partnerReceivedAt = DateTime.now();
    });
    if (feeling.intensity > widget.threshold) {
      _partnerTicksOverThreshold++;
      if (_partnerTicksOverThreshold == widget.requiredConsecutive) {
        unawaited(_hapticPlayer.play(HapticPatterns.whisper));
      }
    } else {
      _partnerTicksOverThreshold = 0;
    }
  }

  void _sendIfNeeded(WhisperFeeling feeling, {bool force = false}) {
    if (!_feelingController.shouldSend(feeling, force: force)) return;
    unawaited(
      ref.read(modeEventBusProvider).send(WhisperProtocol.encode(feeling)),
    );
  }

  void _startFallback() {
    if (_manualSending) return;
    setState(() => _manualSending = true);
    _fallbackStartedAt = DateTime.now();
    _fallbackTimer = Timer.periodic(
      const Duration(milliseconds: 80),
      (_) => _emitFallbackFrame(),
    );
    _emitFallbackFrame();
  }

  void _emitFallbackFrame() {
    if (!mounted || !_manualSending) return;
    final now = DateTime.now();
    final elapsed = now.difference(_fallbackStartedAt!).inMilliseconds;
    final phase = (elapsed % 2400) / 2400;
    final feeling = _feelingController.fallback(phase, now);
    setState(() => _local = feeling);
    _sendIfNeeded(feeling);
  }

  void _stopFallback() {
    if (!_manualSending) return;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    final silence = _feelingController.silence(
      DateTime.now(),
      isFallback: true,
    );
    setState(() {
      _manualSending = false;
      _local = silence;
    });
    _sendIfNeeded(silence, force: true);
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    unawaited(_micSubscription?.cancel());
    unawaited(_partnerSubscription?.cancel());
    unawaited(_hapticPlayer.stop());
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isRussian = Localizations.localeOf(context).languageCode == 'ru';
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.modeWhisper,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 28,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: t.hubExit,
                    color: AppColors.textSecondary,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: _PrivacyBadge(
                  label: isRussian
                      ? 'Аудио не записывается'
                      : 'Audio is never recorded',
                ),
              ),
              Expanded(
                child: AnimatedBuilder(
                  animation: _motion,
                  builder: (context, _) {
                    final partner = _decayedPartner();
                    return Semantics(
                      label: isRussian
                          ? 'Живая волна шёпота'
                          : 'Living whisper wave',
                      child: CustomPaint(
                        key: const Key('whisper-feeling-canvas'),
                        painter: _WhisperMembranePainter(
                          local: _local,
                          partner: partner,
                          phase: _motion.value,
                        ),
                        child: Center(
                          child: _FeelingCore(
                            local: _local,
                            partner: partner,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Text(
                widget.hasMicrophone
                    ? t.whisperHint
                    : (isRussian
                        ? 'Микрофон недоступен. Удерживайте круг, чтобы передать мягкую волну.'
                        : 'Microphone unavailable. Hold the circle to send a soft wave.'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              Semantics(
                button: true,
                label: isRussian
                    ? 'Удерживать для тихой волны'
                    : 'Hold for a quiet wave',
                child: GestureDetector(
                  key: const Key('whisper-fallback-control'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => _startFallback(),
                  onTapUp: (_) => _stopFallback(),
                  onTapCancel: _stopFallback,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: double.infinity,
                    height: 58,
                    decoration: BoxDecoration(
                      color: _manualSending
                          ? const Color(0xFF242034)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _manualSending
                            ? const Color(0xFFA897D8)
                            : AppColors.outline,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _manualSending
                              ? Icons.graphic_eq_rounded
                              : Icons.touch_app_rounded,
                          color: _manualSending
                              ? const Color(0xFFD7CBFF)
                              : AppColors.textSecondary,
                          size: 21,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _manualSending
                              ? (isRussian ? 'Передаю тепло' : 'Sending warmth')
                              : (isRussian
                                  ? 'Удерживать без микрофона'
                                  : 'Hold without microphone'),
                          style: TextStyle(
                            color: _manualSending
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  WhisperFeeling? _decayedPartner() {
    final partner = _partner;
    final receivedAt = _partnerReceivedAt;
    if (partner == null || receivedAt == null || partner.isSilent) {
      return partner;
    }
    final age = DateTime.now().difference(receivedAt).inMilliseconds / 1000;
    final decay = math.exp(-math.max(0, age - 0.35) / 0.9).clamp(0.0, 1.0);
    return WhisperFeeling(
      sequence: partner.sequence,
      capturedAtMs: partner.capturedAtMs,
      intensity: partner.intensity * decay,
      breathiness: partner.breathiness,
      proximity: partner.proximity * decay,
      isFallback: partner.isFallback,
    );
  }
}

class _PrivacyBadge extends StatelessWidget {
  const _PrivacyBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('whisper-privacy-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF111A18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF24443B)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            size: 14,
            color: Color(0xFF89C9B5),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF9DD1C0),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeelingCore extends StatelessWidget {
  const _FeelingCore({required this.local, required this.partner});

  final WhisperFeeling? local;
  final WhisperFeeling? partner;

  @override
  Widget build(BuildContext context) {
    final localLevel = local?.intensity ?? 0;
    final partnerLevel = partner?.intensity ?? 0;
    final active = math.max(localLevel, partnerLevel);
    return AnimatedScale(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      scale: 1 + active * 0.08,
      child: Container(
        width: 104,
        height: 104,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.lerp(
            const Color(0xFF171923),
            const Color(0xFF262136),
            active,
          ),
          border: Border.all(
            color: partnerLevel > localLevel
                ? const Color(0xFFD4C5FF)
                : const Color(0xFF9DDFF0),
            width: 1.2,
          ),
        ),
        child: Icon(
          partnerLevel > 0.03 ? Icons.waves_rounded : Icons.air_rounded,
          size: 31,
          color: AppColors.textPrimary.withValues(alpha: 0.88),
        ),
      ),
    );
  }
}

class _WhisperMembranePainter extends CustomPainter {
  const _WhisperMembranePainter({
    required this.local,
    required this.partner,
    required this.phase,
  });

  final WhisperFeeling? local;
  final WhisperFeeling? partner;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final shortest = size.shortestSide;
    final base = shortest * 0.18;
    _drawFeeling(
      canvas,
      center,
      base,
      local,
      phase,
      const Color(0xFF76CFE5),
      clockwise: true,
    );
    _drawFeeling(
      canvas,
      center,
      base * 1.06,
      partner,
      1 - phase,
      const Color(0xFFC2AEFF),
      clockwise: false,
    );
    if ((local?.intensity ?? 0) < 0.01 && (partner?.intensity ?? 0) < 0.01) {
      canvas.drawCircle(
        center,
        base * (1.42 + math.sin(phase * math.pi * 2) * 0.018),
        Paint()
          ..color = const Color(0xFF343846)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  void _drawFeeling(
    Canvas canvas,
    Offset center,
    double base,
    WhisperFeeling? feeling,
    double time,
    Color color, {
    required bool clockwise,
  }) {
    if (feeling == null || feeling.intensity <= 0.005) return;
    final intensity = feeling.intensity.clamp(0.0, 1.0);
    final air = feeling.breathiness.clamp(0.0, 1.0);
    final proximity = feeling.proximity.clamp(0.0, 1.0);
    for (var ring = 0; ring < 4; ring++) {
      final progress = (time + ring * 0.23) % 1;
      final radius = base * (1.15 + proximity * 0.48 + progress * 1.02);
      final opacity = intensity * (1 - progress) * (0.34 - ring * 0.035);
      if (opacity <= 0.01) continue;
      final path = Path();
      const points = 96;
      for (var i = 0; i <= points; i++) {
        final angle = i / points * math.pi * 2;
        final direction = clockwise ? 1.0 : -1.0;
        final texture =
            math.sin(angle * (3 + ring) + time * math.pi * 2 * direction) *
                base *
                (0.012 + air * 0.035) *
                intensity;
        final r = radius + texture;
        final point = center + Offset(math.cos(angle), math.sin(angle)) * r;
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: opacity.clamp(0.0, 1.0))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1 + intensity * 1.2
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WhisperMembranePainter oldDelegate) =>
      oldDelegate.local != local ||
      oldDelegate.partner != partner ||
      oldDelegate.phase != phase;
}
