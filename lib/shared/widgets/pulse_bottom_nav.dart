import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';

/// Tabs surfaced by [PulseBottomNav].
enum PulseNavTab { people, hub, sneakIn }

/// Pill-shaped bottom navigation used across the three primary tabs in the
/// design (My People / Pulse / Sneak In). Switching is route-driven instead
/// of stateful so deep links keep working.
class PulseBottomNav extends StatelessWidget {
  const PulseBottomNav({super.key, required this.active});

  final PulseNavTab active;

  void _go(BuildContext context, PulseNavTab tab) {
    if (tab == active) return;
    final path = switch (tab) {
      PulseNavTab.people => Routes.people,
      PulseNavTab.hub => Routes.hub,
      PulseNavTab.sneakIn => Routes.sneakIn,
    };
    context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.outline),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _NavItem(
              icon: Icons.people_alt_rounded,
              label: t.navMyPeople,
              active: active == PulseNavTab.people,
              onTap: () => _go(context, PulseNavTab.people),
            ),
            _NavItem(
              icon: Icons.favorite_rounded,
              label: t.navPulse,
              active: active == PulseNavTab.hub,
              onTap: () => _go(context, PulseNavTab.hub),
            ),
            _NavItem(
              icon: Icons.bolt_rounded,
              label: t.navSneakIn,
              active: active == PulseNavTab.sneakIn,
              onTap: () => _go(context, PulseNavTab.sneakIn),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: active ? AppColors.heroGradient : null,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: active ? Colors.white : AppColors.textSecondary,
            ),
            if (active) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
