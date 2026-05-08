import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pulse/l10n/app_localizations.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/connection_avatar.dart';
import '../../../core/widgets/glow_ring.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../connections/application/connections_controller.dart';
import '../../connections/domain/connection.dart';

/// "Sneak In!" — full-screen overlay shown when an inbound short signal
/// arrives. Pull down to reply, tap "Ignore" to dismiss.
class SneakInIncomingScreen extends ConsumerWidget {
  const SneakInIncomingScreen({required this.connectionId, super.key});

  final String connectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final state = ref.watch(connectionsControllerProvider);
    final connection = _findById(state.connections, connectionId);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: GestureDetector(
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 200) {
              context.go(Routes.sneakIn);
            }
          },
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    onPressed: () => context.go(Routes.hub),
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  t.sneakInIncomingTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.heart,
                    fontSize: 36,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 32),
                Center(
                  child: GlowRing(
                    size: 220,
                    color: AppColors.pulse,
                    blurRadius: 40,
                    fill: AppColors.surface,
                    strokeWidth: 1.5,
                    child: connection == null
                        ? const Icon(
                            Icons.notifications_active_rounded,
                            size: 64,
                            color: AppColors.pulse,
                          )
                        : ConnectionAvatar(
                            emoji: connection.emoji,
                            colorIndex: connection.colorIndex,
                            size: 140,
                            fontSize: 80,
                            showRing: false,
                            glow: true,
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                if (connection != null)
                  Center(
                    child: Text(
                      connection.nickname,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    t.sneakInIncomingSubtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
                const Spacer(),
                Center(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.pulse,
                        size: 32,
                      ),
                      Text(
                        t.sneakInPullDownToReply,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                GradientButton(
                  label: t.sneakInPullDownToReply,
                  icon: Icons.reply_rounded,
                  onPressed: () => context.go(Routes.sneakIn),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.go(Routes.hub),
                  child: Text(t.sneakInIgnore),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Connection? _findById(List<Connection> list, String id) {
    for (final c in list) {
      if (c.id == id) return c;
    }
    return null;
  }
}
