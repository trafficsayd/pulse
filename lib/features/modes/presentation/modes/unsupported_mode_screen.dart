import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../capabilities/domain/device_capability.dart';
import '../modes_catalog_screen.dart' show capabilityLabel;

/// Full-screen "this mode can't run on this device" state.
///
/// Used by capability-gated modes (Whisper, Bell) when the user lands on
/// the runner but [DeviceCapabilities.hasAll] returns false. The catalog
/// grid already shows the same data as a snackbar; this widget is the
/// landing-page equivalent for direct-launch (deep link, last-used mode
/// restore) so a missing sensor never leaves the user staring at a blank
/// canvas.
class UnsupportedModeScreen extends StatelessWidget {
  const UnsupportedModeScreen({
    required this.title,
    required this.missing,
    this.onExit,
    super.key,
  });

  final String title;
  final Set<DeviceCapability> missing;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final names = missing.map((c) => capabilityLabel(t, c)).toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.do_not_disturb_on_outlined,
                  size: 56,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t.modesUnsupportedTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                if (names.isNotEmpty)
                  Text(
                    t.modesUnsupportedNeeds(names.join(', ')),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                const SizedBox(height: 28),
                OutlinedButton(
                  onPressed: onExit ?? () => Navigator.of(context).maybePop(),
                  child: Text(t.hubExit),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
