import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import 'mode_close_button.dart';

/// Paid "Breath" mode: a violet halo expands and contracts on a 4s
/// inhale-hold-exhale cycle. The user follows along — this is meant to be
/// a calm-down primitive, the dramatic opposite of Thunder.
class BreathModeScreen extends ConsumerStatefulWidget {
  const BreathModeScreen({super.key});

  @override
  ConsumerState<BreathModeScreen> createState() => _BreathModeScreenState();
}

class _BreathModeScreenState extends ConsumerState<BreathModeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          // Sin curve on [0,1] so the halo eases in and out smoothly.
          final phase = (1 - (_ctrl.value * 2 - 1).abs());
          final size = 160 + 220 * phase;
          return DecoratedBox(
            decoration: const BoxDecoration(
              gradient: AppColors.backgroundGradient,
            ),
            child: Stack(
              children: [
                Center(
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.heroGradient,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.pulseHalo,
                          blurRadius: 40 + 30 * phase,
                        ),
                      ],
                    ),
                  ),
                ),
                const ModeCloseButton(),
                Positioned(
                  bottom: 32,
                  left: 0,
                  right: 0,
                  child: Text(
                    t.breathHint,
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
