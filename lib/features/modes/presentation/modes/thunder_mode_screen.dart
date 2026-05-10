import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import 'mode_close_button.dart';

/// Paid "Thunder" mode: rapid-fire taps build up intensity until a flash
/// fills the screen, then everything decays back to dark. Builds on the
/// Tap-Tap rhythmic primitive but with a heavier, weather-y aesthetic.
class ThunderModeScreen extends ConsumerStatefulWidget {
  const ThunderModeScreen({super.key});

  @override
  ConsumerState<ThunderModeScreen> createState() => _ThunderModeScreenState();
}

class _ThunderModeScreenState extends ConsumerState<ThunderModeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  double _charge = 0;
  int _lastTapMs = 0;

  void _strike() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final delta = now - _lastTapMs;
    _lastTapMs = now;
    setState(() {
      // Quick succession charges the storm; a long gap relaxes it.
      _charge = (delta < 600 ? _charge + 0.25 : _charge * 0.5 + 0.2)
          .clamp(0.0, 1.0);
    });
    if (_charge >= 0.95) {
      _flash.forward(from: 0).whenComplete(() {
        if (mounted) setState(() => _charge = 0);
      });
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTap: _strike,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _flash,
          builder: (context, _) {
            final flash = _flash.value;
            // The screen washes with violet→white at the peak of a strike.
            final overlay = Color.lerp(
              AppColors.background,
              Colors.white,
              flash,
            )!;
            return Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppColors.backgroundGradient,
                  ),
                ),
                Center(
                  child: Container(
                    width: 220 + 80 * _charge,
                    height: 220 + 80 * _charge,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.pulse.withValues(alpha: 0.25 * _charge),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.pulseHalo,
                          blurRadius: 60 * _charge,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.bolt_rounded,
                      size: 96,
                      color: AppColors.pulse.withValues(
                        alpha: 0.4 + 0.6 * _charge,
                      ),
                    ),
                  ),
                ),
                if (flash > 0)
                  IgnorePointer(
                    child: ColoredBox(
                      color: overlay.withValues(alpha: flash),
                    ),
                  ),
                const ModeCloseButton(),
                Positioned(
                  bottom: 32,
                  left: 0,
                  right: 0,
                  child: Text(
                    t.thunderHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
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
