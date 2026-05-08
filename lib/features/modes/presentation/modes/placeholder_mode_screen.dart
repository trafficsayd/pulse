import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';

/// Generic placeholder for modes that have a registered descriptor but no
/// implementation yet. Used so the carousel can show all modes without
/// crashing if the user long-presses one that hasn't shipped yet.
class PlaceholderModeScreen extends StatelessWidget {
  const PlaceholderModeScreen({required this.titleKey, super.key});

  final String titleKey;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.construction_rounded,
                size: 64,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 16),
              Text(
                _localized(t, titleKey),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(t.hubExit),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _localized(AppLocalizations t, String key) => switch (key) {
        'modeTapTap' => t.modeTapTap,
        'modeHalfHeart' => t.modeHalfHeart,
        'modeCandle' => t.modeCandle,
        'modeWhisper' => t.modeWhisper,
        'modeBell' => t.modeBell,
        'modeRay' => t.modeRay,
        'modeConstellation' => t.modeConstellation,
        'modeGoosebumps' => t.modeGoosebumps,
        'modeThread' => t.modeThread,
        'modeThunder' => t.modeThunder,
        'modeFireworks' => t.modeFireworks,
        'modeBalance' => t.modeBalance,
        'modeSandbox' => t.modeSandbox,
        'modeBreath' => t.modeBreath,
        'modeSync' => t.modeSync,
        _ => key,
      };
}
