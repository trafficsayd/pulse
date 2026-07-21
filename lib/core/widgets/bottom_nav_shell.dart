import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/app_localizations.dart';

import '../routing/routes.dart';
import '../theme/app_colors.dart';
import 'pulse_mockup.dart';

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
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SizedBox(
          height: 86,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 68,
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppColors.outlineSoft),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.34),
                        blurRadius: 26,
                        offset: const Offset(0, 14),
                      ),
                    ],
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
                      const SizedBox(width: 106),
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
              Positioned(
                top: -2,
                child: _CenterTab(
                  label: t.navPulse,
                  active: current == BottomNavTab.pulse,
                  onTap: () => _go(context, BottomNavTab.pulse),
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
      borderRadius: BorderRadius.circular(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: -0.15,
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
      borderRadius: BorderRadius.circular(42),
      child: Column(
        children: [
          const PulseGlowCircle(
            size: 64,
            color: AppColors.pulse,
            fill: AppColors.pulse,
            blur: 34,
            borderWidth: 0,
            child: Icon(
              Icons.graphic_eq_rounded,
              color: Colors.white,
              size: 29,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: active ? AppColors.pulse : AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
