import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';

/// Side drawer with the four secondary destinations (Settings, Connection,
/// Modes catalogue, Subscription). Lives on the Hub but is summoned via
/// the burger icon to keep the main canvas uncluttered.
class PulseDrawer extends StatelessWidget {
  const PulseDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Drawer(
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const _BrandHeader(),
            const SizedBox(height: 16),
            const Divider(color: AppColors.outline, height: 1),
            const SizedBox(height: 8),
            _DrawerLink(
              icon: Icons.settings_rounded,
              label: t.drawerSettings,
              onTap: () {
                Navigator.of(context).pop();
                context.push(Routes.settings);
              },
            ),
            _DrawerLink(
              icon: Icons.wifi_tethering_rounded,
              label: t.drawerConnection,
              onTap: () {
                Navigator.of(context).pop();
                context.push(Routes.connectionDetails);
              },
            ),
            _DrawerLink(
              icon: Icons.grid_view_rounded,
              label: t.drawerModes,
              onTap: () {
                Navigator.of(context).pop();
                context.push(Routes.modesBrowser);
              },
            ),
            _DrawerLink(
              icon: Icons.workspace_premium_rounded,
              label: t.drawerSubscription,
              onTap: () {
                Navigator.of(context).pop();
                context.push(Routes.subscription);
              },
            ),
            const Spacer(),
            const _PrivacyFooter(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.heroGradient,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.favorite_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Text(
            'Pulse',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerLink extends StatelessWidget {
  const _DrawerLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary),
      title: Text(
        label,
        style: const TextStyle(color: AppColors.textPrimary),
      ),
      onTap: onTap,
      trailing:
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
    );
  }
}

class _PrivacyFooter extends StatelessWidget {
  const _PrivacyFooter();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        t.connectionPrivacyNote,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
      ),
    );
  }
}
