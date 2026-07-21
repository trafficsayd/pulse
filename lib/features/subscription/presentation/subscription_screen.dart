import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/pulse_mockup.dart';
import '../../../l10n/app_localizations.dart';
import '../application/iap_providers.dart';
import '../application/subscription_controller.dart';
import '../data/iap_diagnostics.dart';
import '../data/iap_product_ids.dart';
import '../data/iap_service.dart';
import '../domain/entitlements.dart';

/// Subscription paywall — minimal, in-app, dark.
///
/// Layout: a soft violet halo around a key icon at the top, the title and
/// tagline, a benefits list, the price, the "Try free" gradient CTA, and
/// "Restore purchases" / Terms / Privacy footer.
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _busyBuy = false;
  bool _busyRestore = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final entitlements = ref.watch(subscriptionControllerProvider);

    // Surface store-side events outside of an explicit buy/restore call.
    // The controller's own listener handles state updates; we're only
    // responsible for snackbars and the "payment processing" indicator.
    ref.listen<AsyncValue<IapEvent>>(purchaseUpdatesProvider, (prev, next) {
      next.whenData((event) => _handleAmbientEvent(context, event, t));
    });

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
              _ActiveUntilBanner(entitlements: entitlements),
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
                child: _SubscribeButton(
                  busy: _busyBuy,
                  entitlements: entitlements,
                  label: entitlements.tier == SubscriptionTier.subscribed
                      ? t.subscriptionContinueTrial
                      : t.subscriptionTryFree,
                  onPressed: _busyBuy ? null : () => _onBuyPressed(t),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _busyRestore ? null : () => _onRestorePressed(t),
                  child: _busyRestore
                      ? _inlineProgress(t.subscriptionRestoring)
                      : Text(t.subscriptionRestore),
                ),
              ),
              if (entitlements.tier == SubscriptionTier.subscribed) ...[
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    onPressed: _openManageSubscription,
                    child: Text(t.subscriptionManage),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _FootLink(
                    label: t.subscriptionTermsOfUse,
                    onTap: () => _launchUrl(
                      'https://pulse-app.app/terms',
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    '·',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(width: 16),
                  _FootLink(
                    label: t.subscriptionPrivacyPolicy,
                    onTap: () => _launchUrl(
                      'https://pulse-app.app/privacy',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onBuyPressed(AppLocalizations t) async {
    setState(() => _busyBuy = true);
    final controller = ref.read(subscriptionControllerProvider.notifier);
    try {
      final result = await controller.buyPremium();
      if (!mounted) return;
      _handleFlowResult(result, t, isRestore: false);
    } finally {
      if (mounted) setState(() => _busyBuy = false);
    }
  }

  Future<void> _onRestorePressed(AppLocalizations t) async {
    setState(() => _busyRestore = true);
    _showSnack(t.subscriptionRestoring);
    final controller = ref.read(subscriptionControllerProvider.notifier);
    try {
      final result = await controller.restorePurchases();
      if (!mounted) return;
      _handleFlowResult(result, t, isRestore: true);
    } finally {
      if (mounted) setState(() => _busyRestore = false);
    }
  }

  void _handleFlowResult(
    SubscriptionFlowResult result,
    AppLocalizations t, {
    required bool isRestore,
  }) {
    switch (result) {
      case SubscriptionFlowResult.success:
        _showSnack(
          isRestore ? t.subscriptionRestoreSuccess : t.subscriptionTryFree,
        );
      case SubscriptionFlowResult.pending:
        _showPersistentSnack(t.subscriptionPurchasePending);
      case SubscriptionFlowResult.nothingToRestore:
        _showSnack(t.subscriptionRestoreNothing);
      case SubscriptionFlowResult.canceled:
        // Silent on purpose — spec: user cancels are not surfaced.
        break;
      case SubscriptionFlowResult.productUnavailable:
        _showSnack(t.subscriptionErrorItemUnavailable);
      case SubscriptionFlowResult.error:
        final controller = ref.read(subscriptionControllerProvider.notifier);
        _showSnack(_localisedError(t, controller.lastError));
    }
  }

  void _handleAmbientEvent(
    BuildContext context,
    IapEvent event,
    AppLocalizations t,
  ) {
    switch (event) {
      case IapPendingEvent():
        _showPersistentSnack(t.subscriptionPurchasePending);
      case IapErrorEvent(:final code):
        _showSnack(_localisedError(t, code));
      case IapPurchasedEvent():
      case IapCanceledEvent():
        ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    }
  }

  String _localisedError(AppLocalizations t, IapErrorCode? code) {
    return switch (code) {
      IapErrorCode.paymentInvalid => t.subscriptionErrorPaymentInvalid,
      IapErrorCode.paymentNotAllowed => t.subscriptionErrorPaymentNotAllowed,
      IapErrorCode.billingUnavailable => t.subscriptionErrorBillingUnavailable,
      IapErrorCode.itemUnavailable => t.subscriptionErrorItemUnavailable,
      IapErrorCode.generic || null => t.subscriptionErrorGeneric,
    };
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showPersistentSnack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(minutes: 1),
      ));
  }

  Future<void> _openManageSubscription() async {
    final url = _manageSubscriptionUrl();
    if (url == null) return;
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Uri? _manageSubscriptionUrl() {
    if (kIsWeb) return null;
    if (Platform.isIOS || Platform.isMacOS) {
      return Uri.parse('https://apps.apple.com/account/subscriptions');
    }
    if (Platform.isAndroid) {
      return Uri.parse(
        'https://play.google.com/store/account/subscriptions'
        '?sku=${IapProductIds.premiumMonthly}'
        '&package=io.pulseapp.pulse',
      );
    }
    return null;
  }

  Widget _inlineProgress(String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(label),
        ],
      );
}

class _SubscribeButton extends StatelessWidget {
  const _SubscribeButton({
    required this.busy,
    required this.label,
    required this.entitlements,
    required this.onPressed,
  });

  final bool busy;
  final String label;
  final Entitlements entitlements;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(child: GradientButton(label: label, onPressed: null)),
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Colors.white,
            ),
          ),
        ],
      );
    }
    return GradientButton(label: label, onPressed: onPressed);
  }
}

class _ActiveUntilBanner extends StatelessWidget {
  const _ActiveUntilBanner({required this.entitlements});

  final Entitlements entitlements;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    if (entitlements.tier != SubscriptionTier.subscribed) {
      return const SizedBox.shrink();
    }
    final expiresAt = entitlements.expiresAt;
    if (expiresAt == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.pulse.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.pulse.withValues(alpha: 0.4)),
        ),
        child: Text(
          t.subscriptionActiveUntil(_formatDate(expiresAt)),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    final d = date.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
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
