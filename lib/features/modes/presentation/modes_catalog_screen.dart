import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pulse/l10n/app_localizations.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/section_header.dart';
import '../../subscription/application/subscription_controller.dart';
import '../application/mode_registry.dart';
import '../domain/pulse_mode.dart';

/// "Modes" catalog — full grid of every shipped mode, split into starter
/// (trial) and paid sections. Tapping a starter mode launches it, tapping
/// a locked paid mode bounces to the subscription paywall.
class ModesCatalogScreen extends ConsumerWidget {
  const ModesCatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final starters = kStarterModes;
    final paid = kPaidModes;
    final unlockedCount = starters.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PulseAppBar(title: t.modesCatalogTitle),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SectionHeader(
            t.modesCatalogTrialSection(unlockedCount, starters.length),
          ),
          _Grid(modes: starters),
          SectionHeader(t.modesCatalogPaidSection),
          _Grid(modes: paid),
        ],
      ),
    );
  }
}

class _Grid extends ConsumerWidget {
  const _Grid({required this.modes});

  final List<PulseModeDescriptor> modes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.95,
        children: [
          for (final m in modes) _ModeTile(mode: m),
        ],
      ),
    );
  }
}

class _ModeTile extends ConsumerWidget {
  const _ModeTile({required this.mode});

  final PulseModeDescriptor mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = ref
        .read(subscriptionControllerProvider.notifier)
        .isModeUnlocked(mode.id);
    final color = unlocked ? mode.tint : AppColors.textMuted;
    return GestureDetector(
      onTap: () {
        if (!unlocked) {
          context.go(Routes.subscription);
          return;
        }
        context.go(Routes.modePath(mode.id.name));
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.outlineSoft),
        ),
        padding: const EdgeInsets.all(8),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.16),
                    border: Border.all(color: color, width: 1.4),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    mode.glyph,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _label(context, mode),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: unlocked
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (!unlocked)
              const Positioned(
                top: 6,
                right: 6,
                child: Icon(
                  Icons.lock_rounded,
                  size: 14,
                  color: AppColors.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _label(BuildContext context, PulseModeDescriptor mode) {
    final t = AppLocalizations.of(context)!;
    return localizedModeTitle(mode, t);
  }
}
