import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../application/mode_registry.dart';
import '../domain/pulse_mode.dart';
import '../../subscription/application/subscription_controller.dart';

/// Catalogue of every mode in the app, split into the trial-friendly
/// starter set and the paid library. Tapping an unlocked mode jumps into
/// it; tapping a locked mode goes through the paywall.
class ModesBrowserScreen extends ConsumerWidget {
  const ModesBrowserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final notifier = ref.read(subscriptionControllerProvider.notifier);
    final starters = kAllModes.where((m) => m.isStarter).toList();
    final paid = kAllModes.where((m) => !m.isStarter).toList();
    final unlockedTrial =
        starters.where((m) => notifier.isModeUnlocked(m.id)).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(t.modesBrowserTitle)),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionHeader(
              label: t.modesAvailableInTrial(unlockedTrial, starters.length),
            ),
            const SizedBox(height: 12),
            _ModeGrid(modes: starters, ref: ref),
            const SizedBox(height: 24),
            _SectionHeader(label: t.modesAvailableOnSubscription),
            const SizedBox(height: 12),
            _ModeGrid(modes: paid, ref: ref),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 13,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _ModeGrid extends StatelessWidget {
  const _ModeGrid({required this.modes, required this.ref});
  final List<PulseModeDescriptor> modes;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: modes.length,
      itemBuilder: (context, i) {
        final mode = modes[i];
        final unlocked = ref
            .read(subscriptionControllerProvider.notifier)
            .isModeUnlocked(mode.id);
        return _Tile(mode: mode, unlocked: unlocked);
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.mode, required this.unlocked});
  final PulseModeDescriptor mode;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () {
        if (unlocked) {
          context.push(Routes.modePath(mode.id.name));
        } else {
          context.push(Routes.subscription);
        }
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surface,
              border: Border.all(color: AppColors.outline, width: 1.2),
            ),
            alignment: Alignment.center,
            child: Icon(
              mode.icon,
              color: unlocked ? AppColors.pulse : AppColors.textMuted,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _label(t, mode.id),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: unlocked ? AppColors.textPrimary : AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (!unlocked)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 12,
                color: AppColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  String _label(AppLocalizations t, PulseModeId id) => switch (id) {
        PulseModeId.tapTap => t.modeTapTap,
        PulseModeId.halfHeart => t.modeHalfHeart,
        PulseModeId.candle => t.modeCandle,
        PulseModeId.whisper => t.modeWhisper,
        PulseModeId.bell => t.modeBell,
        PulseModeId.ray => t.modeRay,
        PulseModeId.constellation => t.modeConstellation,
        PulseModeId.sketch => t.modeSketch,
        PulseModeId.goosebumps => t.modeGoosebumps,
        PulseModeId.thread => t.modeThread,
        PulseModeId.thunder => t.modeThunder,
        PulseModeId.fireworks => t.modeFireworks,
        PulseModeId.balance => t.modeBalance,
        PulseModeId.sandbox => t.modeSandbox,
        PulseModeId.breath => t.modeBreath,
        PulseModeId.sync => t.modeSync,
      };
}
