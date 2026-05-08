import 'package:flutter/material.dart';
import 'package:pulse/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../routing/routes.dart';
import '../theme/app_colors.dart';

/// Three-tab bottom navigation matching the design.
///
/// Tabs (left → right):
/// - "Мои люди"   →  [Routes.people]
/// - "Pulse"       →  [Routes.hub]   (the center, accentuated tab)
/// - "Подкрасться" →  [Routes.sneakIn]
///
/// The center tab is rendered as a violet glowing disc with the Pulse
/// glyph. Inactive tabs are textual icons in muted gray.
enum BottomNavTab { people, pulse, sneakIn }

class BottomNavShell extends StatelessWidget {
  const BottomNavShell({
    super.key,
    required this.current,
    required this.body,
    this.background = AppColors.background,
  });

  final BottomNavTab current;
  final Widget body;
  final Color background;

  void _go(BuildContext context, BottomNavTab tab) {
    if (tab == current) return;
    switch (tab) {
      case BottomNavTab.people:
        context.go(Routes.people);
      case BottomNavTab.pulse:
        context.go(Routes.hub);
      case BottomNavTab.sneakIn:
        context.go(Routes.sneakIn);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: background,
      extendBody: true,
      body: body,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 88,
          decoration: const BoxDecoration(
            color: AppColors.background,
            border: Border(
              top: BorderSide(color: AppColors.outlineSoft),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _SideTab(
                  icon: Icons.groups_2_rounded,
                  label: t.navPeople,
                  active: current == BottomNavTab.people,
                  onTap: () => _go(context, BottomNavTab.people),
                ),
              ),
              SizedBox(
                width: 96,
                child: _CenterTab(
                  label: t.navPulse,
                  active: current == BottomNavTab.pulse,
                  onTap: () => _go(context, BottomNavTab.pulse),
                ),
              ),
              Expanded(
                child: _SideTab(
                  icon: Icons.notifications_active_rounded,
                  label: t.navSneakIn,
                  active: current == BottomNavTab.sneakIn,
                  onTap: () => _go(context, BottomNavTab.sneakIn),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideTab extends StatelessWidget {
  const _SideTab({
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
    final color = active ? AppColors.pulse : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterTab extends StatelessWidget {
  const _CenterTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.pulse,
              boxShadow: [
                BoxShadow(
                  color: AppColors.pulseGlow,
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: active ? AppColors.pulse : AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
