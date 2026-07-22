import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_localizations.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/connection_avatar.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/pulse_mockup.dart';
import '../../connections/application/connections_controller.dart';
import '../../connections/domain/connection.dart';
import '../../modes/primitives/haptic_pattern_player.dart';
import '../../session/application/mode_event.dart';
import '../../session/application/mode_event_bus.dart';

/// "Sneak In!" — full-screen overlay shown when an inbound short signal
/// arrives. Pull down to reply, tap "Ignore" to dismiss.
///
/// While it is on screen it also listens to the live session for further
/// inbound sneak signals from the partner: each one pops a transient sender
/// bubble for ~2s and fires a short vibration, so the mechanic is felt even
/// if the same overlay is already up.
class SneakInIncomingScreen extends ConsumerStatefulWidget {
  const SneakInIncomingScreen({
    required this.connectionId,
    this.hapticEngine,
    super.key,
  });

  final String connectionId;

  /// Optional override for the vibration engine. Defaults to
  /// [NullHapticEngine] (silent no-op on devices without a vibrator), mirroring
  /// the mode screens so widget tests can inject a [RecordingHapticEngine].
  final HapticEngine? hapticEngine;

  @override
  ConsumerState<SneakInIncomingScreen> createState() =>
      _SneakInIncomingScreenState();
}

class _SneakInIncomingScreenState extends ConsumerState<SneakInIncomingScreen> {
  late final HapticEngine _engine;
  late final HapticPatternPlayer _player;
  bool _ownsEngine = false;

  StreamSubscription<ModeEvent>? _sneakSub;
  Timer? _bubbleTimer;

  /// Sender id of the sneak currently shown in the floating bubble, or null
  /// when no bubble is visible. Drives the 2-second overlay.
  String? _bubbleSenderId;

  /// Monotonic counter bumped on every inbound sneak so [AnimatedSwitcher]
  /// re-animates even when the same sender fires twice in a row.
  int _bubbleSeq = 0;

  @override
  void initState() {
    super.initState();
    if (widget.hapticEngine == null) {
      _engine = const NullHapticEngine();
      _ownsEngine = true;
    } else {
      _engine = widget.hapticEngine!;
    }
    _player = HapticPatternPlayer(_engine);

    // Subscribe to inbound sneak signals from the partner. Reuses the shared
    // encrypted event channel via the mode event bus.
    _sneakSub = ref.read(modeEventBusProvider).sneaks.listen(_onSneak);
  }

  void _onSneak(ModeEvent event) {
    if (!mounted) return;
    // Attribute to the sender id carried on the wire, falling back to the
    // connection this overlay was opened for.
    final sender = event.sneakSenderId ?? widget.connectionId;
    setState(() {
      _bubbleSenderId = sender;
      _bubbleSeq++;
    });

    // Short "acknowledged" buzz — the same pattern the rest of the app uses
    // for a Sneak In. Fire-and-forget; disposal cancels any in-flight buzz.
    unawaited(_player.play(HapticPatterns.triple));

    // TODO(audio): play the signal's sound asset once the audio pipeline and
    // `assets/sounds/sneak/*.opus` bytes ship. Until then we intentionally
    // limit inbound feedback to vibration + the visual bubble — no new
    // dependency is added here.

    _bubbleTimer?.cancel();
    _bubbleTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _bubbleSenderId = null);
    });
  }

  @override
  void dispose() {
    _sneakSub?.cancel();
    _bubbleTimer?.cancel();
    unawaited(_player.stop());
    if (_ownsEngine) {
      unawaited(_engine.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final state = ref.watch(connectionsControllerProvider);
    final connection = _findById(state.connections, widget.connectionId);
    final bubbleConnection = _bubbleSenderId == null
        ? null
        : _findById(state.connections, _bubbleSenderId!);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: PulseBackdrop(
        child: SafeArea(
          child: GestureDetector(
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 200) {
                context.go(Routes.sneakIn);
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PulseHeader(
                        title: t.sneakInIncomingTitle,
                        leading: PulseRoundButton(
                          icon: Icons.keyboard_arrow_down_rounded,
                          onTap: () => context.go(Routes.sneakIn),
                          subtle: true,
                        ),
                        trailing: PulseRoundButton(
                          icon: Icons.close_rounded,
                          onTap: () => context.go(Routes.hub),
                          subtle: true,
                        ),
                      ),
                      const SizedBox(height: 42),
                      Text(
                        t.sneakInIncomingTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.heart,
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 34),
                      Center(
                        child: PulseGlowCircle(
                          size: 236,
                          color: AppColors.pulse,
                          blur: 54,
                          fill: AppColors.surface.withValues(alpha: 0.72),
                          borderWidth: 1.4,
                          child: connection == null
                              ? const Icon(
                                  Icons.notifications_active_rounded,
                                  size: 70,
                                  color: AppColors.pulse,
                                )
                              : ConnectionAvatar(
                                  emoji: connection.emoji,
                                  colorIndex: connection.colorIndex,
                                  size: 146,
                                  fontSize: 84,
                                  showRing: false,
                                  glow: true,
                                ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      if (connection != null)
                        Center(
                          child: Text(
                            connection.nickname,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 24,
                              height: 1,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Center(
                        child: Text(
                          t.sneakInIncomingSubtitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      PulsePanel(
                        radius: 24,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.keyboard_double_arrow_down_rounded,
                              color: AppColors.pulse,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              t.sneakInPullDownToReply,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 56,
                        child: GradientButton(
                          label: t.sneakInPullDownToReply,
                          icon: Icons.reply_rounded,
                          onPressed: () => context.go(Routes.sneakIn),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => context.go(Routes.hub),
                        child: Text(t.sneakInIgnore),
                      ),
                    ],
                  ),
                ),
                // Transient "sender bubble": floats in for ~2s each time a
                // fresh inbound sneak lands. Reuses existing copy only (the
                // sender's nickname + the incoming subtitle) — no new strings.
                Positioned(
                  top: 74,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _bubbleSenderId == null
                          ? const SizedBox.shrink()
                          : _SenderBubble(
                              key: ValueKey('${_bubbleSenderId!}:$_bubbleSeq'),
                              connection: bubbleConnection,
                              subtitle: t.sneakInIncomingSubtitle,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Connection? _findById(List<Connection> list, String id) {
    for (final c in list) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// Small floating chip announcing an inbound sneak signal from [connection].
/// Purely visual (no new user-facing strings — reuses the nickname and the
/// existing incoming subtitle).
class _SenderBubble extends StatelessWidget {
  const _SenderBubble({
    required this.connection,
    required this.subtitle,
    super.key,
  });

  final Connection? connection;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: PulsePanel(
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (connection != null)
              ConnectionAvatar(
                emoji: connection!.emoji,
                colorIndex: connection!.colorIndex,
                size: 28,
                showRing: false,
              )
            else
              const Icon(
                Icons.notifications_active_rounded,
                color: AppColors.pulse,
                size: 24,
              ),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (connection != null)
                  Text(
                    connection!.nickname,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
