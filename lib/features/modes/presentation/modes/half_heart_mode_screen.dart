import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../l10n/app_localizations.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';

/// "Half-Heart" — each side touches their half. While both halves are held,
/// they pulse together as one heart. Partner state is driven by the event
/// bus: local hold events are sent, partner hold events are received.
class HalfHeartModeScreen extends ConsumerStatefulWidget {
  const HalfHeartModeScreen({super.key});

  @override
  ConsumerState<HalfHeartModeScreen> createState() =>
      _HalfHeartModeScreenState();
}

class _HalfHeartModeScreenState extends ConsumerState<HalfHeartModeScreen>
    with SingleTickerProviderStateMixin {
  bool _localHeld = false;
  bool _partnerHeld = false;
  StreamSubscription<ModeEvent>? _partnerSub;
  Timer? _localKeepAlive;
  Timer? _partnerExpiry;

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _partnerSub = ref
        .read(modeEventBusProvider)
        .incoming
        .where((e) => e.type == 'hold_start' || e.type == 'hold_end')
        .listen(_onPartnerHold);
  }

  void _onPartnerHold(ModeEvent event) {
    if (!mounted) return;
    final held = event.type == 'hold_start';
    _partnerExpiry?.cancel();
    if (held) {
      _partnerExpiry = Timer(const Duration(milliseconds: 1300), () {
        if (mounted) setState(() => _partnerHeld = false);
      });
    }
    setState(() => _partnerHeld = held);
  }

  @override
  void dispose() {
    _partnerSub?.cancel();
    _localKeepAlive?.cancel();
    _partnerExpiry?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _setLocal(bool held) {
    if (held == _localHeld) return;
    setState(() => _localHeld = held);
    if (held) HapticFeedback.lightImpact();
    // Send hold event to partner.
    final bus = ref.read(modeEventBusProvider);
    unawaited(bus.send(ModeEvent(type: held ? 'hold_start' : 'hold_end')));
    _localKeepAlive?.cancel();
    if (held) {
      _localKeepAlive = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => unawaited(bus.send(const ModeEvent(type: 'hold_start'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final bothHeld = _localHeld && _partnerHeld;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Row(
              children: [
                Expanded(
                  child: _Half(
                    isLeft: true,
                    isHeld: _localHeld,
                    bothHeld: bothHeld,
                    pulse: _pulse,
                    onPointerDown: () => _setLocal(true),
                    onPointerUp: () => _setLocal(false),
                  ),
                ),
                Expanded(
                  child: _Half(
                    isLeft: false,
                    isHeld: _partnerHeld,
                    bothHeld: bothHeld,
                    pulse: _pulse,
                    // Right half mirrors the partner. No direct touch on this
                    // device — only the inbound stream toggles it.
                    onPointerDown: null,
                    onPointerUp: null,
                  ),
                ),
              ],
            ),
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  t.halfHeartHint,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                  ),
                ),
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

class _Half extends StatelessWidget {
  const _Half({
    required this.isLeft,
    required this.isHeld,
    required this.bothHeld,
    required this.pulse,
    required this.onPointerDown,
    required this.onPointerUp,
  });

  final bool isLeft;
  final bool isHeld;
  final bool bothHeld;
  final Animation<double> pulse;
  final VoidCallback? onPointerDown;
  final VoidCallback? onPointerUp;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: onPointerDown == null ? null : (_) => onPointerDown!(),
      onPointerUp: onPointerUp == null ? null : (_) => onPointerUp!(),
      onPointerCancel: onPointerUp == null ? null : (_) => onPointerUp!(),
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (context, _) {
          final intensity =
              bothHeld ? (0.6 + 0.4 * pulse.value) : (isHeld ? 0.5 : 0.18);
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
                end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
                colors: [
                  AppColors.pulse.withValues(alpha: intensity),
                  AppColors.background,
                ],
              ),
            ),
            child: Center(
              child: Icon(
                isLeft
                    ? Icons.favorite_border_rounded
                    : Icons.favorite_border_rounded,
                size: 96,
                color: AppColors.pulse.withValues(
                  alpha: bothHeld ? 1.0 : (isHeld ? 0.7 : 0.25),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
