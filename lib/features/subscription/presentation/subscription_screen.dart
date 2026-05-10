import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/hero_button.dart';
import '../application/subscription_controller.dart';
import '../domain/entitlements.dart';

/// Paywall styled to match the design mockup: crown halo, four feature
/// bullets, a 150 ₽ "disk" emphasising the price, and a pink→violet hero
/// CTA. The trial pill stays in the same slot so the user always knows
/// where they stand.
class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final entitlements = ref.watch(subscriptionControllerProvider);
    final isSubscribed = entitlements.tier == SubscriptionTier.subscribed;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                const _CrownHalo(),
                const SizedBox(height: 20),
                Text(
                  t.subscriptionTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),
                if (!isSubscribed)
                  Center(child: _TrialPill(entitlements: entitlements)),
                const SizedBox(height: 24),
                _FeatureBullet(text: t.subscriptionFeatureAllModes),
                _FeatureBullet(text: t.subscriptionFeatureUnlimitedSneakIn),
                _FeatureBullet(text: t.subscriptionFeatureUpToTen),
                _FeatureBullet(text: t.subscriptionFeaturePriority),
                const Spacer(),
                Center(child: _PriceDisk(label: t.subscriptionPrice)),
                const SizedBox(height: 24),
                HeroButton(
                  label: isSubscribed
                      ? t.subscriptionSubscribe
                      : t.subscriptionTryFree,
                  icon: Icons.workspace_premium_rounded,
                  onPressed: isSubscribed
                      ? null
                      : () => ref
                          .read(subscriptionControllerProvider.notifier)
                          .markSubscribed(),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    // TODO(iap): hook into Apple/Google restore-purchase APIs.
                  },
                  child: Text(
                    t.subscriptionRestore,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                Text(
                  t.subscriptionTermsAndPrivacy,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CrownHalo extends StatelessWidget {
  const _CrownHalo();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 96,
        height: 96,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.heroGradient,
          boxShadow: [
            BoxShadow(color: AppColors.pulseHalo, blurRadius: 32),
          ],
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.workspace_premium_rounded,
          color: Colors.white,
          size: 44,
        ),
      ),
    );
  }
}

class _TrialPill extends StatelessWidget {
  const _TrialPill({required this.entitlements});
  final Entitlements entitlements;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final label = switch (entitlements.tier) {
      SubscriptionTier.subscribed => null,
      SubscriptionTier.trial =>
        t.subscriptionTrialDaysLeft(entitlements.trialDaysRemaining()),
      SubscriptionTier.expired => t.subscriptionTrialExpired,
    };
    if (label == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.pulse.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.pulse.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.pulse,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _FeatureBullet extends StatelessWidget {
  const _FeatureBullet({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.pulse.withValues(alpha: 0.18),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.check_rounded,
              size: 14,
              color: AppColors.pulse,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceDisk extends StatelessWidget {
  const _PriceDisk({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface,
        border: Border.all(color: AppColors.pulse, width: 1.4),
        boxShadow: const [
          BoxShadow(color: AppColors.pulseHalo, blurRadius: 24),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
