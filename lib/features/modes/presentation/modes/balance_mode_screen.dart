import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import 'mode_close_button.dart';

/// Paid "Balance" mode: a violet dot constantly drifts off-centre under a
/// simulated wind force. The user drags it back. The mode rewards calm,
/// shared focus rather than rapid input.
class BalanceModeScreen extends ConsumerStatefulWidget {
  const BalanceModeScreen({super.key});

  @override
  ConsumerState<BalanceModeScreen> createState() => _BalanceModeScreenState();
}

class _BalanceModeScreenState extends ConsumerState<BalanceModeScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Offset _ballPos = Offset.zero;
  Offset _drift = const Offset(0.4, 0.2);
  Size _arena = Size.zero;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  void _tick(Duration _) {
    if (_arena == Size.zero) return;
    setState(() {
      _ballPos = Offset(
        (_ballPos.dx + _drift.dx).clamp(-_arena.width / 2, _arena.width / 2),
        (_ballPos.dy + _drift.dy).clamp(-_arena.height / 2, _arena.height / 2),
      );
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          _arena = Size(constraints.maxWidth * 0.7, constraints.maxHeight * 0.5);
          final center = Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
          final ballScreen = center + _ballPos;
          final centered = _ballPos.distance < 12;
          return DecoratedBox(
            decoration: const BoxDecoration(
              gradient: AppColors.backgroundGradient,
            ),
            child: Stack(
              children: [
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: centered
                            ? AppColors.pulse
                            : AppColors.outline,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: ballScreen.dx - 18,
                  top: ballScreen.dy - 18,
                  child: GestureDetector(
                    onPanUpdate: (d) {
                      setState(() {
                        _ballPos += d.delta;
                        // Reset drift slightly so each user nudge feels real.
                        _drift = Offset(_drift.dx * 0.95, _drift.dy * 0.95);
                      });
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.heroGradient,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.pulseHalo,
                            blurRadius: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const ModeCloseButton(),
                Positioned(
                  bottom: 32,
                  left: 0,
                  right: 0,
                  child: Text(
                    t.balanceHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
