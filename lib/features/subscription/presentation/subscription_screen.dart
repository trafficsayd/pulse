import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pulse/l10n/app_localizations.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/pulse_mockup.dart';
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
      body: PulseBackdrop(
        child: SafeArea(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            children: [
              PulseHeader(title: t.subscriptionTitle),
              const SizedBox(height: 14),
              Center(
                child: PulseGlowCircle(
                  size: 154,
                  color: AppColors.pulse,
                  blur: 46,
                  fill: AppColors.surface.withValues(alpha: 0.72),
                  borderWidth: 1.2,
                  child: const Icon(
                    Icons.lock_open_rounded,
                    size: 58,
                    color: AppColors.pulse,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                t.subscriptionTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t.subscriptionTagline,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.38,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              PulsePanel(
                radius: 30,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
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
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _StatusBadge(entitlements: entitlements),
              const SizedBox(height: 14),
              PulsePanel(
                radius: 28,
                padding: const EdgeInsets.symmetric(vertical: 18),
                color: AppColors.pulse.withValues(alpha: 0.12),
                borderColor: AppColors.pulse.withValues(alpha: 0.38),
                child: Column(
                  children: [
                    Text(
                      t.subscriptionPrice,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.subscriptionFreeTrial7Days,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 56,
                child: GradientButton(
                  label: entitlements.tier == SubscriptionTier.subscribed
                      ? t.subscriptionContinueTrial
                      : t.subscriptionTryFree,
                  onPressed: () => ref
                      .read(subscriptionControllerProvider.notifier)
                      .markSubscribed(),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () {},
                  child: Text(t.subscriptionRestore),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _FootLink(label: t.subscriptionTermsOfUse, onTap: () {}),
                  const SizedBox(width: 16),
                  const Text('·', style: TextStyle(color: AppColors.textMuted)),
                  const SizedBox(width: 16),
                  _FootLink(label: t.subscriptionPrivacyPolicy, onTap: () {}),
                ],
              ),
            ],
          ),
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
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          PulseGlowCircle(
            size: 38,
            color: AppColors.pulse,
            fill: AppColors.pulse.withValues(alpha: 0.13),
            blur: 12,
            borderWidth: 1,
            child: Icon(icon, color: AppColors.pulse, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                height: 1.25,
                fontWeight: FontWeight.w600,
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
