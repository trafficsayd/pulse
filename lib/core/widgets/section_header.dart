import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Small uppercase label used to delimit groups of controls in
/// settings-style screens (e.g. "Разрешения", "Статус").
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Common back-arrow + centered-title app bar.
///
/// Distinct from the Material default so the back chevron can sit flush
/// against the left edge and the title centered exactly to match the
/// mockup. The optional [trailing] spot is used for the small `(i)` icon
/// on subscription/sneak-in screens.
class PulseAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PulseAppBar({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.showBack = true,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final bool showBack;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (showBack)
            Positioned(
              left: 4,
              top: 0,
              bottom: 0,
              child: IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 28),
                color: AppColors.textPrimary,
                onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              ),
            ),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
          if (trailing != null)
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(child: trailing!),
            ),
        ],
      ),
    );
  }
}
