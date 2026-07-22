import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_localizations.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/bottom_nav_shell.dart';
import '../../../core/widgets/connection_avatar.dart';
import '../../../core/widgets/pulse_mockup.dart';
import '../../../core/widgets/section_header.dart';
import '../../connections/application/connections_controller.dart';
import '../../connections/domain/connection.dart';
import '../../connections/domain/connection_status.dart';
import '../../subscription/application/subscription_controller.dart';

/// "My People" — saved connections list with status, transport hint, and
/// per-row affordances.
///
/// Layout matches the mockup: each row shows the avatar, nickname,
/// localized status line, and a trailing icon depending on the row's
/// state — a play button for the active connection, a small lock icon
/// for archived, and the row itself navigates to the connection's
/// settings on tap.
class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final state = ref.watch(connectionsControllerProvider);

    return BottomNavShell(
      current: BottomNavTab.people,
      body: PulseBackdrop(
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 104),
            child: Column(
              children: [
                PulseHeader(
                  title: t.peopleTitle,
                  leading: PulseRoundButton(
                    icon: Icons.settings_rounded,
                    onTap: () => context.go(Routes.settings),
                    subtle: true,
                  ),
                  trailing: PulseRoundButton(
                    icon: Icons.person_add_alt_1_rounded,
                    onTap: () => _onAddConnection(context, ref),
                    color: AppColors.pulse,
                    subtle: true,
                  ),
                ),
                const SizedBox(height: 14),
                PulsePanel(
                  radius: 24,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        color: AppColors.pulse,
                        size: 17,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t.peopleLongPressHint,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: state.connections.isEmpty
                      ? Center(
                          child: PulsePanel(
                            child: Text(
                              t.peopleEmpty,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: state.connections.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) =>
                              _PersonRow(connection: state.connections[index]),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// MONETIZATION (spec §9): the "add connection" affordance on this screen
/// is a second entry point into a brand-new pairing flow (the first being
/// [PairingScreen] itself on first launch), so it needs the exact same
/// saved-connections cap check before it hands control to the pairing
/// screen — otherwise a user could dodge the paywall entirely by only ever
/// using this button.
void _onAddConnection(BuildContext context, WidgetRef ref) {
  final maxConnections =
      ref.read(subscriptionControllerProvider.notifier).maxConnections;
  final canAdd = ref
      .read(connectionsControllerProvider.notifier)
      .canAddConnection(maxConnections);
  if (!canAdd) {
    context.go(Routes.subscription);
    return;
  }
  context.go(Routes.pairing);
}

class _PersonRow extends ConsumerWidget {
  const _PersonRow({required this.connection});

  final Connection connection;

  String _statusLabel(AppLocalizations t) {
    switch (connection.status) {
      case ConnectionStatus.active:
        return t.peopleStatusActiveWithYou;
      case ConnectionStatus.paused:
        if (connection.permissions.allowSneakIn) {
          return t.peopleStatusPausedSneakIn;
        }
        return t.peopleStatusPaused;
      case ConnectionStatus.archived:
        return t.peopleStatusArchived;
    }
  }

  Color _statusColor() {
    switch (connection.status) {
      case ConnectionStatus.active:
        return AppColors.transportDirect;
      case ConnectionStatus.paused:
        return AppColors.textSecondary;
      case ConnectionStatus.archived:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final muted = connection.status == ConnectionStatus.archived;
    return PulsePanel(
      radius: 26,
      padding: EdgeInsets.zero,
      borderColor: connection.status == ConnectionStatus.active
          ? AppColors.pulse.withValues(alpha: 0.42)
          : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: () => context.go(Routes.connectionSettingsPath(connection.id)),
          onLongPress: () => _showActions(context, ref),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Row(
              children: [
                Opacity(
                  opacity: muted ? 0.45 : 1,
                  child: ConnectionAvatar(
                    emoji: connection.emoji,
                    colorIndex: connection.colorIndex,
                    size: 56,
                    glow: connection.status == ConnectionStatus.active,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connection.nickname,
                        style: TextStyle(
                          color: muted
                              ? AppColors.textSecondary
                              : AppColors.textPrimary,
                          fontSize: 17,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _statusColor(),
                              boxShadow: [
                                BoxShadow(
                                  color: _statusColor().withValues(alpha: 0.5),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              _statusLabel(t),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _statusColor(),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _TrailingAction(connection: connection),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              SectionHeader(connection.nickname),
              const SizedBox(height: 4),
              ListTile(
                leading: const Icon(Icons.bolt_rounded, color: AppColors.pulse),
                title: Text(t.peopleMakeActive),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await ref
                      .read(connectionsControllerProvider.notifier)
                      .makeActive(connection.id);
                  if (context.mounted) context.go(Routes.hub);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.notifications_active_rounded,
                  color: AppColors.heart,
                ),
                title: Text(t.peopleSneakIn),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.go(Routes.sneakIn);
                },
              ),
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: Text(t.peoplePermissions),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.go(Routes.connectionSettingsPath(connection.id));
                },
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: Text(t.peopleArchive),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await ref
                      .read(connectionsControllerProvider.notifier)
                      .archive(connection.id);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.danger,
                ),
                title: Text(
                  t.peopleDelete,
                  style: const TextStyle(color: AppColors.danger),
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await ref
                      .read(connectionsControllerProvider.notifier)
                      .delete(connection.id);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _TrailingAction extends ConsumerWidget {
  const _TrailingAction({required this.connection});

  final Connection connection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (connection.status) {
      case ConnectionStatus.active:
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.pulse.withValues(alpha: 0.15),
            border: Border.all(color: AppColors.pulse),
          ),
          child: const Icon(
            Icons.play_arrow_rounded,
            color: AppColors.pulse,
            size: 22,
          ),
        );
      case ConnectionStatus.paused:
        return IconButton(
          onPressed: () => context.go(Routes.sneakIn),
          icon: const Icon(
            Icons.notifications_active_outlined,
            color: AppColors.textSecondary,
          ),
        );
      case ConnectionStatus.archived:
        return const Padding(
          padding: EdgeInsets.only(right: 8),
          child: Icon(
            Icons.lock_outline_rounded,
            color: AppColors.textMuted,
            size: 20,
          ),
        );
    }
  }
}
