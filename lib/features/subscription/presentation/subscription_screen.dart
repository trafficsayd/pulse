import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../application/subscription_controller.dart';
import '../domain/entitlements.dart';

/// Minimal, non-pushy paywall. Shown when the user opens a locked mode or
/// hits a tier-bound limit. Mirrors the dark hub aesthetic on purpose so
/// the transition feels in-app, not interruptive.
class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final entitlements = ref.watch(subscriptionControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(
                t.subscriptionTitle,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                t.subscriptionDescription,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              _StatusBadge(entitlements: entitlements),
              const Spacer(),
              Text(
                t.subscriptionPrice,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref
                    .read(subscriptionControllerProvider.notifier)
                    .markSubscribed(),
                child: Text(t.subscriptionSubscribe),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  // TODO(iap): hook into Apple/Google restore-purchase APIs.
                },
                child: Text(t.subscriptionRestore),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}
