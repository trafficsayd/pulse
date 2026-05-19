import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_localizations.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/pulse_mockup.dart';
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
      body: PulseBackdrop(
        child: SafeArea(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            children: [
              PulseHeader(title: t.modesCatalogTitle),
              const SizedBox(height: 16),
              _CatalogSection(
                title:
                    t.modesCatalogTrialSection(unlockedCount, starters.length),
                modes: starters,
              ),
              const SizedBox(height: 12),
              _CatalogSection(
                title: t.modesCatalogPaidSection,
                modes: paid,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogSection extends StatelessWidget {
  const _CatalogSection({required this.title, required this.modes});

  final String title;
  final List<PulseModeDescriptor> modes;

  @override
  Widget build(BuildContext context) {
    return PulsePanel(
      radius: 28,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
          _Grid(modes: modes),
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
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      crossAxisCount: 3,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 0.88,
      children: [
        for (final m in modes) _ModeTile(mode: m),
      ],
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
          color: AppColors.background.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: unlocked
                ? color.withValues(alpha: 0.44)
                : AppColors.outlineSoft,
          ),
          boxShadow: unlocked
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.16),
                    blurRadius: 18,
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.all(8),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PulseGlowCircle(
                  size: 58,
                  color: color,
                  fill: color.withValues(alpha: unlocked ? 0.15 : 0.08),
                  blur: unlocked ? 18 : 0,
                  borderWidth: 1.2,
                  child: Text(
                    mode.glyph,
                    style: const TextStyle(fontSize: 25),
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
                    fontWeight: FontWeight.w700,
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
