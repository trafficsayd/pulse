import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pulse/l10n/app_localizations.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glow_ring.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/section_header.dart';
import '../application/subscription_controller.dart';
import '../domain/entitlements.dart';

/// Subscription paywall — minimal, in-app, dark.
///
/// Layout: a soft violet halo around a key icon at the top, the title and
/// tagline, a benefits list, the price, the "Try free" gradient CTA, and
/// "Restore purchases" / Terms / Privacy footer.
class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final entitlements = ref.watch(subscriptionControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PulseAppBar(title: t.subscriptionTitle),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            const SizedBox(height: 8),
            Center(
              child: GlowRing(
                size: 140,
                color: AppColors.pulse,
                blurRadius: 36,
                fill: AppColors.surface,
                strokeWidth: 1.5,
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  size: 64,
                  color: Color(0xFFFFD86A),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              t.subscriptionTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w300,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t.subscriptionTagline,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            _BenefitTile(
              icon: Icons.auto_awesome_rounded,
              text: t.subscriptionFeatureAllModes,
            ),
            _BenefitTile(
              icon: Icons.notifications_active_rounded,
              text: t.subscriptionFeatureUnlimitedSneak,
            ),
            _BenefitTile(
              icon: Icons.groups_rounded,
              text: t.subscriptionFeatureUpToTen,
            ),
            _BenefitTile(
              icon: Icons.trending_up_rounded,
              text: t.subscriptionFeaturePriority,
            ),
            const SizedBox(height: 24),
            _StatusBadge(entitlements: entitlements),
            const SizedBox(height: 16),
            Center(
              child: Text(
                t.subscriptionPrice,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                t.subscriptionFreeTrial7Days,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 16),
            GradientButton(
              label: entitlements.tier == SubscriptionTier.subscribed
                  ? t.subscriptionContinueTrial
                  : t.subscriptionTryFree,
              onPressed: () => ref
                  .read(subscriptionControllerProvider.notifier)
                  .markSubscribed(),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () {
                  // TODO(iap): hook into Apple/Google restore-purchase APIs.
                },
                child: Text(t.subscriptionRestore),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _FootLink(label: t.subscriptionTermsOfUse, onTap: () {}),
                const SizedBox(width: 16),
                Text(
                  '·',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(width: 16),
                _FootLink(label: t.subscriptionPrivacyPolicy, onTap: () {}),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _BenefitTile extends StatelessWidget {
  const _BenefitTile({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.pulse.withValues(alpha: 0.16),
            ),
            child: Icon(icon, color: AppColors.pulse, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.entitlements});

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
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.outline),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _FootLink extends StatelessWidget {
  const _FootLink({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
        ),
      ),
    );
  }
}
