import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/routes.dart';
import '../../../../core/theme/app_colors.dart';

/// Small X icon used by every mode screen to leave the active session.
///
/// Pops the route stack when possible (the hub uses [GoRouter.push] to enter a
/// mode). If the user reached the screen via a deep link with no stack to pop,
/// falls through to a `go(Routes.hub)` so they're never stranded.
class ModeCloseButton extends StatelessWidget {
  const ModeCloseButton({this.color, super.key});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return IconButton(
      onPressed: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(Routes.hub);
        }
      },
      icon: const Icon(Icons.close_rounded),
      color: color ?? AppColors.textSecondary,
      tooltip: t.hubExit,
    );
  }
}
