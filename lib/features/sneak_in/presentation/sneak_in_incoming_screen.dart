import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_localizations.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/connection_avatar.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/pulse_mockup.dart';
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
      body: PulseBackdrop(
        child: SafeArea(
          child: GestureDetector(
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 200) {
                context.go(Routes.sneakIn);
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PulseHeader(
                    title: t.sneakInIncomingTitle,
                    leading: PulseRoundButton(
                      icon: Icons.keyboard_arrow_down_rounded,
                      onTap: () => context.go(Routes.sneakIn),
                      subtle: true,
                    ),
                    trailing: PulseRoundButton(
                      icon: Icons.close_rounded,
                      onTap: () => context.go(Routes.hub),
                      subtle: true,
                    ),
                  ),
                  const SizedBox(height: 42),
                  Text(
                    t.sneakInIncomingTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.heart,
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 34),
                  Center(
                    child: PulseGlowCircle(
                      size: 236,
                      color: AppColors.pulse,
                      blur: 54,
                      fill: AppColors.surface.withValues(alpha: 0.72),
                      borderWidth: 1.4,
                      child: connection == null
                          ? const Icon(
                              Icons.notifications_active_rounded,
                              size: 70,
                              color: AppColors.pulse,
                            )
                          : ConnectionAvatar(
                              emoji: connection.emoji,
                              colorIndex: connection.colorIndex,
                              size: 146,
                              fontSize: 84,
                              showRing: false,
                              glow: true,
                            ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  if (connection != null)
                    Center(
                      child: Text(
                        connection.nickname,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 24,
                          height: 1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      t.sneakInIncomingSubtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  PulsePanel(
                    radius: 24,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.keyboard_double_arrow_down_rounded,
                          color: AppColors.pulse,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          t.sneakInPullDownToReply,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 56,
                    child: GradientButton(
                      label: t.sneakInPullDownToReply,
                      icon: Icons.reply_rounded,
                      onPressed: () => context.go(Routes.sneakIn),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go(Routes.hub),
                    child: Text(t.sneakInIgnore),
                  ),
                ],
              ),
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
