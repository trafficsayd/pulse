import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import 'mode_close_button.dart';

/// Paid "Sync" mode: two halves of the screen pulse on slightly different
/// rhythms; the user taps to nudge their half into phase with the
/// (simulated) partner half. When the two phases are close, both halves
/// glow brighter.
class SyncModeScreen extends ConsumerStatefulWidget {
  const SyncModeScreen({super.key});

  @override
  ConsumerState<SyncModeScreen> createState() => _SyncModeScreenState();
}

class _SyncModeScreenState extends ConsumerState<SyncModeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  /// User-controlled phase offset (0..1). Each tap nudges by 0.05.
  double _userPhase = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _nudge() {
    setState(() => _userPhase = (_userPhase + 0.05) % 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTap: _nudge,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final partner = _ctrl.value;
            final user = (_ctrl.value + _userPhase) % 1.0;
            final phaseDiff = (partner - user).abs();
            final inSync = phaseDiff < 0.06 || phaseDiff > 0.94;
            final intensity = inSync ? 1.0 : 0.4;

            return DecoratedBox(
              decoration: const BoxDecoration(
                gradient: AppColors.backgroundGradient,
              ),
              child: Stack(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _PhaseHalf(
                          phase: user,
                          color: AppColors.pulse,
                          intensity: intensity,
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                      Expanded(
                        child: _PhaseHalf(
                          phase: partner,
                          color: AppColors.pulsePink,
                          intensity: intensity,
                          alignment: Alignment.centerRight,
                        ),
                      ),
                    ],
                  ),
                  const ModeCloseButton(),
                  Positioned(
                    bottom: 32,
                    left: 0,
                    right: 0,
                    child: Text(
                      t.syncHint,
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
      ),
    );
  }
}

class _PhaseHalf extends StatelessWidget {
  const _PhaseHalf({
    required this.phase,
    required this.color,
    required this.intensity,
    required this.alignment,
  });

  final double phase;
  final Color color;
  final double intensity;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    // 0..1 wave shape; peaks at 0.5.
    final wave = 1 - (phase * 2 - 1).abs();
    final size = 80 + 120 * wave;
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.4 * intensity),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4 * intensity),
                blurRadius: 30 + 30 * wave * intensity,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
