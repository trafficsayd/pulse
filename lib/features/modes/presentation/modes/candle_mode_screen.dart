import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../../core/theme/app_colors.dart';
import 'mode_close_button.dart';

/// "Candle" — tap to light a virtual candle. Long-press anywhere to "blow"
/// the flame out (the spec uses microphone breath; on web we substitute a
/// long-press because mic capture is not yet wired).
///
/// The partner side mirrors local state for the foundation PR; the mode
/// runner replaces this once the real transport is wired.
class CandleModeScreen extends StatefulWidget {
  const CandleModeScreen({super.key});

  @override
  State<CandleModeScreen> createState() => _CandleModeScreenState();
}

class _CandleModeScreenState extends State<CandleModeScreen>
    with SingleTickerProviderStateMixin {
  bool _localLit = false;
  bool _partnerLit = false;
  late final AnimationController _flicker;

  @override
  void initState() {
    super.initState();
    _flicker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _flicker.dispose();
    super.dispose();
  }

  void _toggleLight() {
    setState(() {
      _localLit = !_localLit;
      _partnerLit = _localLit; // simulated mirror
    });
    if (_localLit) HapticFeedback.lightImpact();
  }

  void _extinguish() {
    if (!_localLit && !_partnerLit) return;
    setState(() {
      _localLit = false;
      _partnerLit = false;
    });
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleLight,
              onLongPress: _extinguish,
              child: Row(
                children: [
                  Expanded(
                    child: _Candle(lit: _localLit, flicker: _flicker),
                  ),
                  Expanded(
                    child: _Candle(lit: _partnerLit, flicker: _flicker),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  t.candleHint,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const Positioned(
              top: 8,
              right: 8,
              child: ModeCloseButton(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Candle extends StatelessWidget {
  const _Candle({required this.lit, required this.flicker});

  final bool lit;
  final Animation<double> flicker;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: flicker,
      builder: (context, _) {
        final glow = lit ? (0.7 + flicker.value * 0.3) : 0.0;
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 0.7,
              colors: [
                AppColors.pulse.withValues(alpha: glow * 0.45),
                AppColors.background,
              ],
            ),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.translate(
                offset: Offset(math.sin(flicker.value * math.pi) * 1.4, 0),
                child: Icon(
                  Icons.local_fire_department_rounded,
                  size: lit ? 84 : 56,
                  color: lit
                      ? AppColors.pulse.withValues(alpha: 0.6 + glow * 0.4)
                      : AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 28,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.outline),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
