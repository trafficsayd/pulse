import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../subscription/application/subscription_controller.dart';
import '../application/mode_registry.dart';
import '../domain/pulse_mode.dart';

/// Resolves a mode by id from the URL, checks the user's tier, and renders
/// either the mode's screen or bounces to the paywall if it's locked.
class ModeRunnerScreen extends ConsumerWidget {
  const ModeRunnerScreen({required this.modeIdRaw, super.key});

  final String modeIdRaw;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = _parseId(modeIdRaw);
    if (id == null) {
      // Unknown mode id — never crash, just bounce back to the hub.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(Routes.hub);
      });
      return const _Empty();
    }
    final descriptor = findMode(id);
    if (descriptor == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(Routes.hub);
      });
      return const _Empty();
    }

    final unlocked =
        ref.watch(subscriptionControllerProvider.notifier).isModeUnlocked(id);
    if (!unlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(Routes.subscription);
      });
      return const _Empty();
    }

    return descriptor.builder(context);
  }

  static PulseModeId? _parseId(String raw) {
    for (final id in PulseModeId.values) {
      if (id.name == raw) return id;
    }
    return null;
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: SizedBox.shrink(),
    );
  }
}
